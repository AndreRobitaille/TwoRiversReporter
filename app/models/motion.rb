class Motion < ApplicationRecord
  belongs_to :meeting
  belongs_to :agenda_item, optional: true
  belongs_to :decision_observation, class_name: "CouncilDecisionObservation", optional: true
  has_one :identity_assignment, through: :decision_observation
  has_one :council_decision, through: :identity_assignment
  has_many :votes, dependent: :destroy

  validate :decision_observation_matches_meeting

  after_create :update_topic_activity

  private

  def decision_observation_matches_meeting
    if decision_observation && decision_observation.minutes_extraction.original_meeting_id != meeting_id
      errors.add(:decision_observation, "must belong to this meeting")
    end
  end

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
