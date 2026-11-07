class CouncilDecisionObservation < ApplicationRecord
  belongs_to :minutes_extraction
  belongs_to :council_decision, optional: true
  has_one :motion, foreign_key: :decision_observation_id, dependent: :restrict_with_exception
  has_one :identity_assignment, class_name: "CouncilDecisionAssignment", foreign_key: :observation_id, dependent: :restrict_with_exception
  has_many :identity_corrections, class_name: "CouncilDecisionCorrection", foreign_key: :observation_id, dependent: :restrict_with_exception
  attr_readonly :minutes_extraction_id, :council_decision_id, :sequence, :data, :location_check,
    :agenda_context, :identity_status, :reason, :candidate_decision_ids, :rule_version, :evidence_status

  validates :sequence, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :minutes_extraction_id }
  validates :identity_status, inclusion: { in: %w[introduced matched unresolved] }
  validates :evidence_status, inclusion: { in: [ "extracted" ] }
  validates :rule_version, presence: true
  validate :matches_retained_extraction
  validate :immutable_payload

  private

  def matches_retained_extraction
    stage = minutes_extraction
    motions = stage.data["motions"] if stage&.data.is_a?(Hash)
    valid = stage&.kind == "votes" && stage.status == "completed" && sequence.is_a?(Integer) && sequence.positive? &&
      motions.is_a?(Array) && data.is_a?(Hash) && motions[sequence - 1] == data && location_check.is_a?(Hash) &&
      location_check["source_key"] == stage.source_key && location_check["text_version_id"] == stage.meeting_document_text_version_id
    valid &&= if identity_status == "unresolved"
      council_decision.nil? && reason.present?
    else
      council_decision&.original_meeting_id == stage.original_meeting_id && location_check["status"] == "located"
    end
    errors.add(:base, "must preserve one retained motion and its identity basis") unless valid
  end

  def immutable_payload
    errors.add(:base, "cannot replace a retained observation") if persisted? && (changed - [ "updated_at" ]).any?
  end
end
