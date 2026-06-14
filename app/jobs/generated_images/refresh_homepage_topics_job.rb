module GeneratedImages
  class RefreshHomepageTopicsJob < ApplicationJob
    queue_as :default

    def perform
      return unless GeneratedImages::Config.enabled?

      GeneratedImages::HomepageTopicSelector.new.call.each do |topic|
        briefing = topic.topic_briefing
        next unless briefing&.headline.present?

        GeneratedImages::GenerateForTopicJob.perform_later(topic.id)
      end
    end
  end
end
