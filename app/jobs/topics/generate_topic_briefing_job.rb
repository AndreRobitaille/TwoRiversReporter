module Topics
  class GenerateTopicBriefingJob < ApplicationJob
    queue_as :default

    RAW_CONTEXT_MEETING_LIMIT = 3

    def perform(topic_id:, meeting_id:)
      topic = Topic.find(topic_id)
      meeting = Meeting.find(meeting_id)

      return unless topic.approved?
      effective_meeting = context_meeting_for(topic, meeting)
      return unless effective_meeting

      context = build_briefing_context(topic, effective_meeting)
      evidence = GenerationEvidence.capture(topic: topic, meeting: effective_meeting, context: context,
        query: briefing_query(topic), kind: "topic_briefing")
      return unless evidence
      existing = TopicBriefing.find_by(topic: topic)
      original = existing&.attributes&.slice("id", "updated_at")
      if existing&.generation_tier == "full" && existing.generation_data.is_a?(Hash) && existing.generation_data["evidence_manifest"] == evidence
        # A later correction can restore the exact retained inputs. Revalidate
        # under the publication lock and reuse that completed analysis for free.
        if existing.evidence_withdrawn_at?
          topic.with_lock do
            current = TopicBriefing.find_by(topic: topic)
            return unless current&.attributes&.slice("id", "updated_at") == original && evidence_current?(topic.id, meeting.id, evidence)
            current.update!(evidence_withdrawn_at: nil, withdrawal_correction: nil)
          end
        end
        return
      end

      ai_service = Ai::OpenAiService.new
      retrieval_service = RetrievalService.new
      context[:knowledgebase_context] = retrieve_knowledge(topic, retrieval_service)
      return unless evidence_current?(topic.id, meeting.id, evidence)
      analysis_json_str = ai_service.analyze_topic_briefing(context, source: topic)
      analysis_json = parse_json_safely(analysis_json_str, topic)
      return if analysis_json.empty?
      return unless evidence_current?(topic.id, meeting.id, evidence)

      Citations::TopicAnalysis.copy_references!(analysis_json, references: context[:citation_references])
      analysis_json["source_catalog"] = context[:source_catalog].deep_dup
      analysis_json["evidence_manifest"] = evidence.deep_dup
      rendered = ai_service.render_topic_briefing(analysis_json.to_json, source: topic)

      topic.with_lock do
        current = TopicBriefing.find_by(topic: topic)
        return unless current&.attributes&.slice("id", "updated_at") == original && evidence_current?(topic.id, meeting.id, evidence)

        save_briefing(topic, effective_meeting, analysis_json, rendered)
        propagate_impact(topic, analysis_json)
      end
    end

    private

    def evidence_current?(topic_id, meeting_id, evidence)
      ActiveRecord::Base.uncached do
        topic, meeting = Topic.find(topic_id), Meeting.find(meeting_id)
        effective_meeting = context_meeting_for(topic, meeting)
        return false unless effective_meeting

        context = build_briefing_context(topic, effective_meeting)
        GenerationEvidence.capture(topic: topic, meeting: effective_meeting, context: context,
          query: briefing_query(topic), kind: "topic_briefing") == evidence
      end
    rescue ActiveRecord::RecordNotFound
      false
    end

    def briefing_query(topic)
      "#{topic.canonical_name} #{topic.topic_aliases.order(:name).pluck(:name).join(' ')}"
    end

    def retrieve_knowledge(topic, retrieval_service)
      chunks = retrieval_service.retrieve_topic_context(topic: topic, query_text: briefing_query(topic), limit: 5, max_chars: 6000)
      retrieval_service.format_topic_context(chunks)
    end

    def build_briefing_context(topic, meeting, retrieval_service = nil)
      prior_summaries = topic.topic_summaries
        .joins(:meeting)
        .where(meetings: { id: TopicAppearance.joins(:agenda_item).merge(AgendaItem.substantive).where(topic_id: topic.id).select(:meeting_id) })
        .order("meetings.starts_at ASC", :id)
        .includes(:meeting).to_a.select { |summary| GenerationEvidence.summary_current?(summary) }

      recent_meeting_ids = topic.topic_appearances
        .joins(agenda_item: :meeting)
        .merge(AgendaItem.substantive)
        .group(:meeting_id)
        .maximum("meetings.starts_at")
        .sort_by { |meeting_id, starts_at| [ starts_at || Time.at(0), meeting_id ] }
        .reverse
        .first(RAW_CONTEXT_MEETING_LIMIT)
        .map(&:first)

      recent_meetings = Meeting.where(id: recent_meeting_ids).order(starts_at: :desc, id: :desc)
      recent_contexts = recent_meetings.map do |m|
        Topics::SummaryContextBuilder.new(topic, m).build_context_json
      end
      recent_raw_context = recent_contexts.flat_map { |context| context[:agenda_items] }
      citation_references = prior_summaries.each_with_object({}) do |summary, references|
        references.merge!(Citations::TopicAnalysis.retained_references(summary))
      end
      recent_contexts.each { |context| citation_references.merge!(context[:citation_references]) }
      source_catalog = (recent_contexts.flat_map { |context| context[:source_catalog] } +
        prior_summaries.flat_map { |summary| summary.generation_data["source_catalog"] || [] }).uniq

      # Pull per-item substantive content from each recent meeting's
      # MeetingSummary. Without this, the briefing AI sees only agenda
      # structure (item titles + empty `item.summary` fields) and
      # regenerates "appeared on the agenda" factual_record entries.
      # The content already exists in generation_data["item_details"];
      # we just filter to agenda items linked to this topic.
      recent_item_details = Topics::RecentItemDetailsBuilder
        .new(topic, recent_meetings.to_a)
        .build

      formatted_kb = retrieval_service ? retrieve_knowledge(topic, retrieval_service) : []

      {
        topic_metadata: {
          id: topic.id,
          canonical_name: topic.canonical_name,
          lifecycle_status: topic.lifecycle_status,
          first_seen_at: topic.first_seen_at&.iso8601,
          last_seen_at: topic.last_seen_at&.iso8601,
          aliases: topic.topic_aliases.order(:name).pluck(:name)
        },
        prior_meeting_analyses: prior_summaries.map(&:generation_data),
        citation_references: citation_references,
        source_catalog: source_catalog,
        recent_raw_context: recent_raw_context,
        recent_item_details: recent_item_details,
        knowledgebase_context: formatted_kb,
        continuity_context: {
          status_events: topic.topic_status_events.with_current_evidence.order(occurred_at: :desc, id: :desc).limit(5).map do |e|
            { event_id: e.id, motion_reference: e.motion_reference,
              event_type: e.evidence_type, notes: e.notes, date: e.occurred_at&.iso8601 }
          end,
          total_appearances: topic.topic_appearances.joins(:agenda_item).merge(AgendaItem.substantive).count
        },
        upcoming_context: build_upcoming_context(topic)
      }
    end

    def build_upcoming_context(topic)
      upcoming_meeting_ids = topic.topic_appearances
        .joins(agenda_item: :meeting)
        .merge(AgendaItem.substantive)
        .where(meetings: { starts_at: Time.current.. })
        .group(:meeting_id)
        .minimum("meetings.starts_at")
        .sort_by { |meeting_id, starts_at| [ starts_at || Time.at(0), meeting_id ] }
        .first(3)
        .map(&:first)

      Meeting.where(id: upcoming_meeting_ids).order(starts_at: :asc, id: :asc).map do |meeting|
        agenda_items = meeting.agenda_items
          .substantive
          .joins(:agenda_item_topics)
          .where(agenda_item_topics: { topic_id: topic.id })
          .order(:order_index, :id)

        {
          meeting_body: meeting.body_name,
          meeting_date: meeting.starts_at&.to_date&.to_s,
          agenda_items: agenda_items.includes(:parent).map { |ai| { title: ai.display_context_title, summary: ai.summary } }
        }
      end
    end

    def context_meeting_for(topic, meeting)
      return meeting if topic_has_substantive_item_for_meeting?(topic, meeting)

      TopicAppearance
        .joins(:agenda_item, :meeting)
        .merge(AgendaItem.substantive)
        .where(topic_id: topic.id)
        .order("meetings.starts_at DESC", "meetings.id DESC")
        .first
        &.meeting
    end

    def topic_has_substantive_item_for_meeting?(topic, meeting)
      meeting.agenda_items.substantive
        .joins(:agenda_item_topics)
        .where(agenda_item_topics: { topic_id: topic.id })
        .exists?
    end

    def parse_json_safely(json_str, topic)
      JSON.parse(json_str)
    rescue JSON::ParserError
      Rails.logger.error("Failed to parse briefing analysis for Topic #{topic.id}")
      {}
    end

    def save_briefing(topic, meeting, analysis_json, rendered)
      briefing = topic.topic_briefing || topic.build_topic_briefing

      briefing.headline = analysis_json["headline"] || "Topic update"
      briefing.upcoming_headline = analysis_json["upcoming_headline"]
      briefing.editorial_content = rendered["editorial_content"]
      briefing.record_content = rendered["record_content"]
      briefing.generation_data = analysis_json
      briefing.generation_tier = "full"
      briefing.last_full_generation_at = Time.current
      briefing.triggering_meeting = meeting
      briefing.evidence_withdrawn_at = nil
      briefing.withdrawal_correction = nil
      briefing.save!
      enqueue_generated_image_refresh
    end

    def propagate_impact(topic, analysis_json)
      return unless analysis_json["resident_impact"].is_a?(Hash)

      score = analysis_json["resident_impact"]["score"].to_i
      topic.update_resident_impact_from_ai(score) if score.between?(1, 5)
    end

    def enqueue_generated_image_refresh
      return unless GeneratedImages::Config.enabled?

      GeneratedImages::RefreshHomepageTopicsJob.perform_later
    end
  end
end
