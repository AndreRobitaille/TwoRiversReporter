module Topics
  class SummaryContextBuilder
    def initialize(topic, meeting)
      @topic = topic
      @meeting = meeting
    end

    def build_context_json(kb_context_chunks: [])
      agenda_items = agenda_items_data
      continuity = continuity_context

      {
        topic_metadata: topic_metadata,
        meeting_metadata: {
          id: @meeting.id,
          body_name: @meeting.body_name,
          meeting_date: @meeting.starts_at&.to_date,
          source_type: analysis_source_type
        },
        agenda_items: agenda_items,
        continuity_context: continuity,
        resident_reported_context: resident_reported_context,
        source_catalog: source_catalog,
        citation_ids: collect_citation_ids(agenda_items, continuity),
        citation_references: collect_citation_references(agenda_items, continuity),
        knowledgebase_context: kb_context_chunks
      }
    end

    private

    def topic_metadata
      {
        id: @topic.id,
        canonical_name: @topic.canonical_name,
        lifecycle_status: @topic.lifecycle_status,
        first_seen_at: @topic.first_seen_at&.to_date,
        last_seen_at: @topic.last_seen_at&.to_date
      }
    end

    def agenda_items_data
      # Find agenda items for this meeting linked to this topic
      # Use substantive rows only so structural section headers never become
      # standalone evidence items in topic summaries.
      item_ids = @meeting.agenda_items.substantive.joins(:agenda_item_topics)
                       .where(agenda_item_topics: { topic_id: @topic.id })
                       .distinct
                       .pluck(:id)

      items = @meeting.agenda_items.substantive.where(id: item_ids).includes(:parent).order(:order_index)

      # Build an agenda-ID → item_details entry lookup from the
      # meeting's latest MeetingSummary. This is the substantive content
      # the minutes analyzer wrote for each item (e.g. "Council approved
      # a $240,000 bid for Main St repaving"). Without this, the per-meeting
      # TopicSummary prompt only sees agenda structure (item.summary, which
      # is usually nil) and writes generic "agenda includes an item titled..."
      # factual_record entries. See issue #94.
      item_details_by_id = build_item_details_index

      items.map do |item|
        # Agenda Item Document Attachments
        doc_attachments = item.meeting_documents.flat_map do |doc|
          snapshot = Citations::SourceCatalog.snapshot(doc)
          resolver = Citations::Resolver.new(meeting: @meeting, catalog: [ snapshot ])
          pages = Citations::SourceCatalog.pages_for(doc)
          locations = pages.any? ? pages.map { |page| [ { "kind" => "pdf_page", "page_number" => page.page_number }, page.cleaned_text ] } :
            [ [ { "kind" => "whole_source" }, doc.extracted_text ] ]
          locations.map do |location, text|
            reference = resolver.canonical_reference({ "source_id" => snapshot["source_id"], "location" => location })
            reference.deep_symbolize_keys.merge(id: doc.id, type: doc.document_type,
              text_preview: text&.truncate(2000, separator: " "))
          end
        end

        # Base Agenda Item Citation
        item_citation = {
          citation_id: "agenda-#{item.id}",
          label: item.parent.present? ? "Agenda Item #{item.number}: #{item.display_context_title}" : "Agenda Item #{item.number}: #{item.title}",
          text_preview: [ item.summary, item.recommended_action ].compact.join("\n")
        }

        matched_details = item_details_by_id[item.id]
        references = analysis_source_citations(matched_details)

        {
          id: item.id,
          number: item.number,
          title: item.display_context_title,
          summary: item.summary,
          recommended_action: item.recommended_action,
          item_details_summary: matched_details&.dig("summary"),
          item_details_activity_level: matched_details&.dig("activity_level"),
          item_details_vote: matched_details&.dig("vote"),
          item_details_decision: matched_details&.dig("decision"),
          item_details_public_hearing: matched_details&.dig("public_hearing"),
          item_details_motion: matched_details&.dig("motion"),
          item_details_citation: references.first,
          item_details_citations: references,
          item_details_unresolved_citations: unresolved_analysis_citations(matched_details),
          citation: item_citation,
          attachments: doc_attachments
        }
      end
    end

    def build_item_details_index
      summary = latest_summary
      return {} unless summary&.generation_data.is_a?(Hash)

      details = summary.generation_data["item_details"]
      return {} unless details.is_a?(Array)

      Topics::ItemDetailsMatcher.new(@meeting.agenda_items.substantive.includes(:parent).to_a, details).build
    end

    def latest_summary
      @latest_summary ||= ResidentContent::MeetingSelection.preferred_summary(@meeting)
    end

    def analysis_source_citations(details)
      return [] unless details && latest_summary

      values = details["citations"] || details["citation"]
      references = values.is_a?(Array) ? values : [ values ].compact
      resolver = analysis_citation_resolver
      references.filter_map do |reference|
        next unless resolver.resolve(reference)[:status] == "resolved"
        resolver.canonical_reference(reference).deep_symbolize_keys
      end
    end

    def unresolved_analysis_citations(details)
      return [] unless details && latest_summary

      analysis_citation_resolver.resolve_all(details["citations"] || details["citation"])
        .select { |reference| reference[:status] == "unresolved" }
    end

    def analysis_citation_resolver
      @analysis_citation_resolver ||= Citations::Resolver.for_summary(latest_summary)
    end

    def analysis_source_type
      data = latest_summary&.generation_data
      data["source_type"] if data.is_a?(Hash)
    end

    def continuity_context
      cutoff_time = @meeting.starts_at || Time.current

      # Recent history events
      recent_events = @topic.topic_status_events
        .where("occurred_at <= ?", cutoff_time)
        .order(occurred_at: :desc).limit(3).map do |e|
        # Build citation if source_ref has IDs
        citation = nil
        if e.source_ref.present? && e.source_ref["meeting_id"]
          # Create a synthetic citation for continuity
          citation = {
            citation_id: "continuity-#{e.id}",
            label: "Event on #{e.occurred_at.to_date}"
          }
        end

        {
          date: e.occurred_at.to_date,
          status: e.lifecycle_status,
          evidence: e.evidence_type,
          notes: e.notes,
          citation: citation
        }
      end

      # Recent appearances (excluding current meeting)
      prior_appearances = @topic.topic_appearances
        .joins(:agenda_item)
        .merge(AgendaItem.substantive)
        .where("appeared_at < ?", cutoff_time)
        .order(appeared_at: :desc).limit(3)
        .map do |a|
          {
            date: a.appeared_at.to_date,
            meeting_body: a.body_name,
            evidence: a.evidence_type,
            citation_id: "appearance-#{a.id}",
            label: "#{a.body_name} meeting on #{a.appeared_at.to_date}"
          }
        end


      {
        recent_status_events: recent_events,
        prior_appearances: prior_appearances
      }
    end

    def resident_reported_context
      return nil if @topic.source_notes.blank?

      {
        label: "Resident-reported (no official record)",
        source_type: @topic.source_type,
        notes: @topic.source_notes,
        added_by: @topic.added_by,
        added_at: @topic.added_at
      }
    end

    def source_catalog
      summary_sources = latest_summary&.generation_data&.dig("source_catalog") || []
      attachments = @meeting.agenda_items.substantive.joins(:agenda_item_topics)
        .where(agenda_item_topics: { topic_id: @topic.id }).flat_map(&:meeting_documents)
      (summary_sources + attachments.map { |document| Citations::SourceCatalog.snapshot(document) }).uniq
    end

    def collect_citation_references(agenda_items, continuity)
      references = agenda_items.flat_map do |item|
        [ item[:citation], *item[:item_details_citations], *item[:attachments] ]
      end
      references.concat(continuity[:recent_status_events].filter_map { |event| event[:citation] })
      references.concat(continuity[:prior_appearances])
      references.compact.to_h do |reference|
        [ reference[:citation_id], reference.except(:text_preview, :notes, :date, :meeting_body, :evidence) ]
      end
    end

    def collect_citation_ids(agenda_items, continuity)
      collect_citation_references(agenda_items, continuity).keys.compact
    end
  end
end
