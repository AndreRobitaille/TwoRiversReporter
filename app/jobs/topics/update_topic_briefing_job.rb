module Topics
  class UpdateTopicBriefingJob < ApplicationJob
    queue_as :default

    def perform(topic_id:, meeting_id:, tier:)
      topic = Topic.find(topic_id)
      meeting = Meeting.find(meeting_id)

      return unless topic.approved?
      return unless topic_has_substantive_item_for_meeting?(topic, meeting)

      case tier
      when "headline_only"
        update_headline_only(topic, meeting)
      when "interim"
        update_interim(topic, meeting)
      else
        Rails.logger.error("Unknown tier '#{tier}' for UpdateTopicBriefingJob")
      end
    end

    private

    def update_headline_only(topic, meeting)
      briefing = topic.topic_briefing || topic.build_topic_briefing

      date_str = meeting.starts_at.strftime("%b %-d")
      briefing.upcoming_headline = "Coming up at #{meeting.body_name}, #{date_str}"
      briefing.headline ||= "Topic update"

      unless briefing.persisted? && briefing.generation_tier.in?(%w[interim full])
        briefing.generation_tier = "headline_only"
      end
      briefing.triggering_meeting = meeting
      briefing.save!
    end

    def update_interim(topic, meeting)
      briefing = topic.topic_briefing || topic.build_topic_briefing

      agenda_items = meeting.agenda_items
        .substantive
        .includes(:parent)
        .joins(:agenda_item_topics)
        .where(agenda_item_topics: { topic_id: topic.id })

      context = {
        topic_name: topic.canonical_name,
        current_headline: briefing.upcoming_headline || briefing.headline,
        meeting_body: meeting.body_name,
        meeting_date: meeting.starts_at&.to_date&.to_s,
        agenda_items: agenda_items.map { |ai| { title: ai.display_context_title, summary: ai.summary } }
      }

      result = Ai::OpenAiService.new.generate_briefing_interim(context)

      briefing.upcoming_headline = result["headline"] if result["headline"].present?
      briefing.headline ||= "Topic update"
      if result["upcoming_note"].present?
        briefing.editorial_content = [
          briefing.editorial_content,
          result["upcoming_note"]
        ].compact.join("\n\n")
      end

      unless briefing.persisted? && briefing.generation_tier == "full"
        briefing.generation_tier = "interim"
      end
      briefing.triggering_meeting = meeting
      briefing.save!
    end

    def topic_has_substantive_item_for_meeting?(topic, meeting)
      meeting.agenda_items.substantive
        .joins(:agenda_item_topics)
        .where(agenda_item_topics: { topic_id: topic.id })
        .exists?
    end
  end
end
