module Topics
  class UpdateContinuityJob < ApplicationJob
    queue_as :default

    def perform(topic_id: nil, meeting_id: nil)
      if topic_id
        update_topic(Topic.find_by(id: topic_id))
      elsif meeting_id
        meeting = Meeting.find_by(id: meeting_id)
        return unless meeting

        # Find all topics linked to this meeting's agenda items
        topic_ids = AgendaItemTopic.joins(:agenda_item)
                                   .where(agenda_items: { meeting_id: meeting.id })
                                   .pluck(:topic_id)
                                   .uniq

        topic_ids.each do |tid|
          update_topic(Topic.find_by(id: tid))
        end
      end
    end

    private

    def update_topic(topic)
      return unless topic

      Rails.logger.info "Updating continuity for Topic #{topic.id} (#{topic.canonical_name})"
      Topics::ContinuityService.call(topic)
    rescue => e
      Rails.logger.error "Failed to update continuity for Topic #{topic.id}: #{e.message}"
      # Don't raise, just log, so other topics in batch can proceed
    end
  end
end
