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
        agenda_items: agenda_items,
        continuity_context: continuity,
        resident_reported_context: resident_reported_context,
        citation_ids: collect_citation_ids(agenda_items, continuity),
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

      # Build a normalized-title → item_details entry lookup from the
      # meeting's latest MeetingSummary. This is the substantive content
      # the minutes analyzer wrote for each item (e.g. "Council approved
      # a $240,000 bid for Main St repaving"). Without this, the per-meeting
      # TopicSummary prompt only sees agenda structure (item.summary, which
      # is usually nil) and writes generic "agenda includes an item titled..."
      # factual_record entries. See issue #94.
      item_details_by_norm_title = build_item_details_index

      items.map do |item|
        # Agenda Item Document Attachments
        doc_attachments = item.meeting_documents.flat_map do |doc|
          # Use extractions if available for granular page citations
          if doc.extractions.any?
            doc.extractions.map do |ex|
              {
                id: doc.id,
                type: doc.document_type,
                citation_id: "doc-#{doc.id}-p#{ex.page_number}",
                label: "#{doc.document_type.humanize} (Page #{ex.page_number})",
                text_preview: ex.cleaned_text&.truncate(1000, separator: " ")
              }
            end
          else
            # Fallback to whole document
            [ {
              id: doc.id,
              type: doc.document_type,
              citation_id: "doc-#{doc.id}",
              label: "#{doc.document_type.humanize}",
              text_preview: doc.extracted_text&.truncate(2000, separator: " ")
            } ]
          end
        end

        # Base Agenda Item Citation
        item_citation = {
          citation_id: "agenda-#{item.id}",
          label: item.parent.present? ? "Agenda Item #{item.number}: #{item.display_context_title}" : "Agenda Item #{item.number}: #{item.title}",
          text_preview: [ item.summary, item.recommended_action ].compact.join("\n")
        }

        matched_details = item_details_for(item, item_details_by_norm_title)

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
          citation: item_citation,
          attachments: doc_attachments
        }
      end
    end

    def build_item_details_index
      summary = @meeting.meeting_summaries.order(created_at: :desc).first
      return {} unless summary&.generation_data.is_a?(Hash)

      details = summary.generation_data["item_details"]
      return {} unless details.is_a?(Array)

      title_counts = substantive_title_counts

      details.each_with_object({}) do |entry, index|
        next unless entry.is_a?(Hash)
        title = entry["agenda_item_title"]
        next unless title.is_a?(String)
        normalized = Topics::TitleNormalizer.normalize(title)
        next if title_counts[normalized].to_i > 1

        index[normalized] = entry
      end
    end

    def item_details_for(item, item_details_by_norm_title)
      contextual = Topics::TitleNormalizer.normalize(item.display_context_title.to_s)
      bare = Topics::TitleNormalizer.normalize(item.title.to_s)

      item_details_by_norm_title[contextual] || item_details_by_norm_title[bare]
    end

    def substantive_title_counts
      @meeting.agenda_items.substantive.each_with_object(Hash.new(0)) do |item, counts|
        normalized = Topics::TitleNormalizer.normalize(item.title.to_s)
        counts[normalized] += 1 if normalized.present?
      end
    end

    def continuity_context
      # Recent history events
      recent_events = @topic.topic_status_events.order(occurred_at: :desc).limit(3).map do |e|
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
      # Use meeting.starts_at if available, else current time
      cutoff_time = @meeting.starts_at || Time.current

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

    def collect_citation_ids(agenda_items, continuity)
      ids = []

      agenda_items.each do |item|
        ids << item.dig(:citation, :citation_id)
        item[:attachments].each do |attachment|
          ids << attachment[:citation_id]
        end
      end

      continuity[:recent_status_events].each do |event|
        ids << event.dig(:citation, :citation_id)
      end

      continuity[:prior_appearances].each do |appearance|
        ids << appearance[:citation_id]
      end

      ids.compact.uniq
    end
  end
end
