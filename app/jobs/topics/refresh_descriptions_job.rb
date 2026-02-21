module Topics
  class RefreshDescriptionsJob < ApplicationJob
    queue_as :default

    def perform
      stale_topics.find_each do |topic|
        Topics::GenerateDescriptionJob.perform_later(topic.id)
      end
    end

    private

    def stale_topics
      threshold = Topics::GenerateDescriptionJob::REFRESH_THRESHOLD.ago

      Topic.approved.where(
        "description_generated_at < :threshold OR ((description IS NULL OR description = '') AND description_generated_at IS NULL)",
        threshold: threshold
      )
    end
  end
end
