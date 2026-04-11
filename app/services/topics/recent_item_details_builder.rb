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
  # Matching is fuzzy on normalized titles via Topics::TitleNormalizer:
  # an item_details entry is included only if its agenda_item_title,
  # normalized, equals the normalized title of an AgendaItem on the
  # meeting that is linked to the target topic via AgendaItemTopic.
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
      summary = meeting.meeting_summaries.order(created_at: :desc).first
      return [] unless summary&.generation_data.is_a?(Hash)

      details = summary.generation_data["item_details"]
      return [] unless details.is_a?(Array)

      linked_normalized_titles = linked_title_set(meeting)
      return [] if linked_normalized_titles.empty?

      details.filter_map do |entry|
        next nil unless entry.is_a?(Hash)
        title = entry["agenda_item_title"]
        next nil unless title.is_a?(String)
        next nil unless linked_normalized_titles.include?(Topics::TitleNormalizer.normalize(title))

        {
          meeting_date: meeting.starts_at&.to_date&.to_s,
          meeting_body: meeting.body_name,
          agenda_item_title: title,
          summary: entry["summary"],
          activity_level: entry["activity_level"],
          vote: entry["vote"],
          decision: entry["decision"],
          public_hearing: entry["public_hearing"]
        }
      end
    end

    def linked_title_set(meeting)
      meeting.agenda_items
        .joins(:agenda_item_topics)
        .where(agenda_item_topics: { topic_id: @topic.id })
        .pluck(:title)
        .map { |t| Topics::TitleNormalizer.normalize(t) }
        .to_set
    end
  end
end
