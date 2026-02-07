class AgendaItemTopic < ApplicationRecord
  belongs_to :agenda_item
  belongs_to :topic

  after_create :update_topic_stats

  private

  def update_topic_stats
    meeting_date = agenda_item.meeting&.starts_at || Time.current

    updates = {}

    if topic.last_seen_at.nil? || meeting_date > topic.last_seen_at
      updates[:last_seen_at] = meeting_date
    end

    if agenda_item.motions.any?
      if topic.last_activity_at.nil? || meeting_date > topic.last_activity_at
        updates[:last_activity_at] = meeting_date
      end
    end

    topic.update(updates) if updates.any?
  end
end
