module Topics
  class GenerateTopicBriefingJob < ApplicationJob
    queue_as :default

    RAW_CONTEXT_MEETING_LIMIT = 3

    def perform(topic_id:, meeting_id:)
      topic = Topic.find(topic_id)
      meeting = Meeting.find(meeting_id)

      return unless topic.approved?

      ai_service = Ai::OpenAiService.new
      retrieval_service = RetrievalService.new

      context = build_briefing_context(topic, meeting, retrieval_service)
      analysis_json_str = ai_service.analyze_topic_briefing(context)
      analysis_json = parse_json_safely(analysis_json_str, topic)
      return if analysis_json.empty?

      rendered = ai_service.render_topic_briefing(analysis_json.to_json)

      save_briefing(topic, meeting, analysis_json, rendered)
      propagate_impact(topic, analysis_json)
    end

    private

    def build_briefing_context(topic, meeting, retrieval_service)
      prior_summaries = topic.topic_summaries
        .joins(:meeting)
        .order("meetings.starts_at ASC")
        .pluck(:generation_data)

      recent_meeting_ids = topic.topic_appearances
        .joins(:meeting)
        .order("meetings.starts_at DESC")
        .limit(RAW_CONTEXT_MEETING_LIMIT)
        .pluck(:meeting_id)

      recent_meetings = Meeting.where(id: recent_meeting_ids)
      recent_raw_context = recent_meetings.flat_map do |meeting|
        builder = Topics::SummaryContextBuilder.new(topic, meeting)
        builder.build_context_json[:agenda_items]
      end

      query = "#{topic.canonical_name} #{topic.topic_aliases.pluck(:name).join(' ')}"
      kb_chunks = retrieval_service.retrieve_topic_context(
        topic: topic, query_text: query, limit: 5, max_chars: 6000
      )
      formatted_kb = retrieval_service.format_topic_context(kb_chunks)

      {
        topic_metadata: {
          id: topic.id,
          canonical_name: topic.canonical_name,
          lifecycle_status: topic.lifecycle_status,
          first_seen_at: topic.first_seen_at&.iso8601,
          last_seen_at: topic.last_seen_at&.iso8601,
          aliases: topic.topic_aliases.pluck(:name)
        },
        prior_meeting_analyses: prior_summaries,
        recent_raw_context: recent_raw_context,
        knowledgebase_context: formatted_kb,
        continuity_context: {
          status_events: topic.topic_status_events.order(occurred_at: :desc).limit(5).map do |e|
            { event_type: e.evidence_type, details: e.details, date: e.occurred_at&.iso8601 }
          end,
          total_appearances: topic.topic_appearances.count
        }
      }
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
      briefing.editorial_content = rendered["editorial_content"]
      briefing.record_content = rendered["record_content"]
      briefing.generation_data = analysis_json
      briefing.generation_tier = "full"
      briefing.last_full_generation_at = Time.current
      briefing.triggering_meeting = meeting
      briefing.save!
    end

    def propagate_impact(topic, analysis_json)
      return unless analysis_json["resident_impact"].is_a?(Hash)

      score = analysis_json["resident_impact"]["score"].to_i
      topic.update_resident_impact_from_ai(score) if score.between?(1, 5)
    end
  end
end
