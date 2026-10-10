module Topics
  # Builds a filtered list of per-item substantive content for a topic,
  # pulled from the most recent MeetingSummary on each provided meeting.
  #
  # Used by GenerateTopicBriefingJob to give the briefing AI access to
  # the actual content of agenda items linked to the topic — not just
  # agenda structure. This is the content that already lives in
  # MeetingSummary.generation_data["item_details"] and is shown on the
  # meeting page but never flowed into the topic-level briefing prompt.
  #
  # Matching uses meeting-scoped agenda IDs, with unambiguous normalized
  # titles as a fallback for summaries generated before IDs were included.
  #
  # Output shape per entry (Symbol keys — these flow into a Hash passed
  # to OpenAI, which serializes them as JSON):
  #   {
  #     meeting_date: "2025-08-04",
  #     meeting_body: "Public Utilities Committee",
  #     agenda_item_title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
  #     summary: "Staff reported fake stickers...",
  #     activity_level: "discussion",
  #     vote: nil,
  #     decision: nil,
  #     public_hearing: nil
  #   }
  class RecentItemDetailsBuilder
    def initialize(topic, meetings)
      @topic = topic
      @meetings = Array(meetings)
    end

    def build
      @meetings.flat_map { |meeting| entries_for(meeting) }
    end

    private

    def entries_for(meeting)
      summary = ResidentContent::MeetingSelection.preferred_summary(meeting)
      return [] unless summary&.generation_data.is_a?(Hash)

      details = summary.generation_data["item_details"]
      return [] unless details.is_a?(Array)

      matches = Topics::ItemDetailsMatcher.new(meeting.agenda_items.substantive.includes(:parent).to_a, details).build
      items = meeting.agenda_items.substantive
        .joins(:agenda_item_topics)
        .where(agenda_item_topics: { topic_id: @topic.id })
        .distinct
        .order(:order_index)

      items.filter_map do |item|
        entry = matches[item.id]
        next unless entry

        {
          meeting_date: meeting.starts_at&.to_date&.to_s,
          meeting_body: meeting.body_name,
          source_type: summary.generation_data["source_type"],
          source_catalog: summary.generation_data["source_catalog"] || [],
          citations: Citations::Resolver.for_summary(summary).resolve_all(entry["citations"] || entry["citation"]),
          agenda_item_id: item.id,
          agenda_item_title: item.display_context_title,
          summary: entry["summary"],
          activity_level: entry["activity_level"],
          vote: entry["vote"],
          motion: entry["motion"],
          motion_evidence: entry["motion_evidence"],
          vote_evidence: entry["vote_evidence"],
          decision: entry["decision"],
          public_hearing: entry["public_hearing"]
        }
      end
    end
  end
end
