module ResidentContent
  # The same agenda-level analysis already feeds meeting and topic pages.
  # Read it here without another extraction, milestone classification or claim
  # that the member caused the reported development.
  class MeetingIssueHistory
    def self.call(topics:, during:)
      meeting_ids = AgendaItemTopic.where(topic_id: topics.keys).joins(:agenda_item).select("agenda_items.meeting_id")
      summaries = MeetingSummary.published.where(summary_type: "minutes_recap", meeting_id: meeting_ids)
        .joins(:meeting).where(meetings: { starts_at: during })
        .includes(meeting: [ :meeting_summaries, { agenda_items: [ :parent, :topics ] } ])
      summaries.flat_map do |summary|
        meeting = summary.meeting
        next [] if meeting.cancelled? || ResidentContent::MeetingSelection.preferred_summary(meeting)&.id != summary.id

        items = meeting.agenda_items.select(&:substantive?)
        details = Topics::ItemDetailsMatcher.new(items, summary.generation_data["item_details"]).build
        resolver = Citations::Resolver.for_summary(summary)
        items.filter_map do |item|
          related = item.topics.filter_map { |topic| topics[topic.id] }
          detail = details[item.id]
          next if related.empty? || detail&.fetch("summary", nil).blank?
          citations = resolver.resolve_all(detail["citations"] || detail["citation"])
            .select { |citation| citation[:status] == "resolved" }
          # Older published recaps predate the citation catalog. Keep their
          # meeting link without turning a legacy "Page 3" into a verified URL.
          next unless summary.generation_data["source_catalog"].blank? ||
            citations.any? { |citation| citation[:source_type].in?(%w[minutes_pdf minutes_html]) }

          { meeting: meeting, topics: related, reported_on: meeting.starts_at.to_date, citations: citations,
            evidence: { "agenda_item_id" => item.id, "status" => detail["activity_level"],
              "subject" => related.map(&:canonical_name).join(" / "), "summary" => detail.fetch("summary") } }
        end
      end
    end
  end
end
