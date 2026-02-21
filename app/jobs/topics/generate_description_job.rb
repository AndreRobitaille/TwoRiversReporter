module Topics
  class GenerateDescriptionJob < ApplicationJob
    queue_as :default

    REFRESH_THRESHOLD = 90.days

    def perform(topic_id)
      topic = Topic.find_by(id: topic_id)
      return unless topic

      # Skip admin-edited descriptions (has description but no generated_at timestamp)
      return if topic.description.present? && topic.description_generated_at.nil?

      # Skip if recently generated
      if topic.description_generated_at.present? && topic.description_generated_at > REFRESH_THRESHOLD.ago
        return
      end

      context = build_context(topic)
      description = Ai::OpenAiService.new.generate_topic_description(context)

      return if description.nil?

      topic.update!(
        description: description,
        description_generated_at: Time.current
      )
    end

    private

    def build_context(topic)
      agenda_items = topic.agenda_items
        .joins(:meeting)
        .order("meetings.starts_at DESC")
        .limit(10)
        .select("agenda_items.title, agenda_items.summary")
        .map { |ai| { title: ai.title, summary: ai.summary } }

      headlines = topic.topic_summaries
        .order(created_at: :desc)
        .limit(5)
        .filter_map { |ts| ts.generation_data&.dig("headline") }

      {
        topic_name: topic.name,
        agenda_items: agenda_items,
        headlines: headlines
      }
    end
  end
end
