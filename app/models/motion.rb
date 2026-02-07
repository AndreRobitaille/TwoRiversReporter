class Motion < ApplicationRecord
  belongs_to :meeting
  belongs_to :agenda_item, optional: true
  has_many :votes, dependent: :destroy

  after_create :update_topic_activity

  private

  def update_topic_activity
    return unless agenda_item

    agenda_item.topics.each do |topic|
      meeting_date = meeting.starts_at
      if topic.last_activity_at.nil? || meeting_date > topic.last_activity_at
        topic.update(last_activity_at: meeting_date)
      end
    end
  end
end
