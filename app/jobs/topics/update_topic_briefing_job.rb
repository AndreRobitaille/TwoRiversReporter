module Topics
  class UpdateTopicBriefingJob < ApplicationJob
    queue_as :default

    def perform(topic_id:, meeting_id:, tier:)
      topic = Topic.find(topic_id)
      meeting = Meeting.find(meeting_id)

      return unless topic.approved?
      return unless topic_has_substantive_item_for_meeting?(topic, meeting)
      return if topic.topic_briefing&.evidence_withdrawn_at?

      case tier
      when "headline_only"
        update_headline_only(topic, meeting)
      when "interim"
        update_interim(topic, meeting)
      else
        Rails.logger.error("Unknown tier '#{tier}' for UpdateTopicBriefingJob")
        return
      end

      topic.refresh_resident_impact_priority
    end

    private

    def update_headline_only(topic, meeting)
      topic.with_lock do
        briefing = topic.topic_briefing || topic.build_topic_briefing
        return if briefing.evidence_withdrawn_at?

        date_str = meeting.starts_at.strftime("%b %-d")
        briefing.upcoming_headline = "Coming up at #{meeting.body_name}, #{date_str}"
        briefing.headline ||= "Topic update"

        unless briefing.persisted? && briefing.generation_tier.in?(%w[interim full])
          briefing.generation_tier = "headline_only"
        end
        briefing.triggering_meeting = meeting
        briefing.save!
      end
    end

    def update_interim(topic, meeting)
      briefing = topic.topic_briefing || topic.build_topic_briefing
      original = briefing.persisted? ? briefing.attributes.slice("id", "updated_at") : nil

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

      topic.with_lock do
        current = TopicBriefing.find_by(topic: topic)
        return unless current&.attributes&.slice("id", "updated_at") == original && !current&.evidence_withdrawn_at?
        briefing = current || topic.build_topic_briefing

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
    end

    def topic_has_substantive_item_for_meeting?(topic, meeting)
      meeting.agenda_items.substantive
        .joins(:agenda_item_topics)
        .where(agenda_item_topics: { topic_id: topic.id })
        .exists?
    end
  end
end
