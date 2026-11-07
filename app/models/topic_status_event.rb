class TopicStatusEvent < ApplicationRecord
  belongs_to :topic
  belongs_to :decision_observation, class_name: "CouncilDecisionObservation", optional: true
  has_one :identity_assignment, through: :decision_observation
  has_one :council_decision, through: :identity_assignment

  validates :lifecycle_status, presence: true, inclusion: { in: %w[active dormant resolved recurring] }
  validates :occurred_at, presence: true
  validates :evidence_type, presence: true
  validate :retained_motion_basis

  # Historical events remain inspectable. New context must use only supported
  # motion outcomes from the current publication and the current topic link.
  scope :with_current_evidence, -> {
    where.not(evidence_type: "motion_outcome").or(where(id: current_motion_event_ids))
  }

  def self.current_motion_event_ids
    where(evidence_type: "motion_outcome")
      .joins(<<~SQL)
        INNER JOIN motions ON (
          motions.decision_observation_id = topic_status_events.decision_observation_id OR
          (topic_status_events.decision_observation_id IS NULL AND
           CAST(motions.id AS text) = topic_status_events.source_ref->>'motion_id'))
        INNER JOIN agenda_item_topics ON agenda_item_topics.agenda_item_id = motions.agenda_item_id
          AND agenda_item_topics.topic_id = topic_status_events.topic_id
        INNER JOIN meetings ON meetings.id = motions.meeting_id
        LEFT JOIN council_decision_observations ON council_decision_observations.id = motions.decision_observation_id
        LEFT JOIN minutes_publications ON minutes_publications.id = meetings.minutes_publication_id
      SQL
      .where("topic_status_events.source_ref->>'outcome' = motions.outcome")
      .where("topic_status_events.occurred_at = meetings.starts_at")
      .where(<<~SQL)
        (motions.decision_observation_id IS NULL AND meetings.minutes_publication_id IS NULL) OR
        council_decision_observations.minutes_extraction_id = minutes_publications.votes_extraction_id
      SQL
      .unscope(:order, :limit, :offset)
      # Topic merges preserve both histories; current context needs each motion once.
      .group("topic_status_events.topic_id", "motions.id")
      .reselect("MIN(topic_status_events.id)")
  end

  private

  def retained_motion_basis
    if decision_observation
      unless evidence_type == "motion_outcome" && source_ref.is_a?(Hash) && source_ref["outcome"] == decision_observation.data["outcome"]
        errors.add(:base, "must retain the extracted motion outcome")
      end
    end
    if persisted? && decision_observation_id_in_database && (will_save_change_to_decision_observation_id? || will_save_change_to_source_ref?)
      errors.add(:base, "cannot replace retained motion evidence")
    end
  end
end
