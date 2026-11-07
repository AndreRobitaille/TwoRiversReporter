class CouncilDecisionCorrection < ApplicationRecord
  belongs_to :observation, class_name: "CouncilDecisionObservation"
  belongs_to :basis_observation, class_name: "CouncilDecisionObservation", optional: true
  belongs_to :before_decision, class_name: "CouncilDecision", optional: true
  belongs_to :after_decision, class_name: "CouncilDecision", optional: true
  belongs_to :previous_correction, class_name: "CouncilDecisionCorrection", optional: true
  belongs_to :actor, class_name: "User", optional: true

  attr_readonly :observation_id, :basis_observation_id, :before_decision_id, :after_decision_id, :previous_correction_id,
    :actor_id, :original_actor_id, :actor_email, :action, :reason, :request_id, :request_manifest, :evidence_manifest
  validates :action, inclusion: { in: %w[assign introduce unassign] }
  validates :reason, :original_actor_id, :actor_email, presence: true
  validates :request_id, uniqueness: true, format: { with: /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/ }
  validate :retained_identity_basis
  validate :immutable_payload
  before_destroy -> { throw :abort }

  def applies_to?(candidate)
    candidate.minutes_extraction.source_key == evidence_manifest["source_key"] && candidate.data == evidence_manifest["data"] &&
      candidate.sequence == observation.sequence && candidate.agenda_context == observation.agenda_context
  end

  def records_assignment_change?(assignment)
    change = Array(evidence_manifest["assignment_changes"]).find { |entry| entry["assignment_id"] == assignment.id }
    before = %w[council_decision_id correction_id conflicting_correction_ids].to_h { |field| [ field, assignment.attribute_in_database(field) ] }
    return false unless change && change["before"] == before

    if change["result"] == "applied"
      assignment.council_decision_id == change["after_decision_id"] && assignment.correction_id == id && assignment.conflicting_correction_ids.empty?
    elsif change["result"] == "conflict"
      assignment.council_decision_id.nil? && assignment.correction_id.nil? &&
        assignment.conflicting_correction_ids == (before["conflicting_correction_ids"] + [ id ]).uniq.sort
    else
      false
    end
  end

  private

  def retained_identity_basis
    stage = observation&.minutes_extraction
    valid = stage && evidence_manifest.is_a?(Hash) && evidence_manifest["source_key"] == stage.source_key &&
      evidence_manifest["data"] == observation.data && evidence_manifest["review_scope"] == "decision_identity_only"
    valid &&= [ before_decision, after_decision ].compact.all? { |decision| decision.original_meeting_id == stage.original_meeting_id }
    valid &&= action == "unassign" ? after_decision.nil? : after_decision.present?
    valid &&= basis_observation.present? if action == "assign"
    errors.add(:base, "must retain the source and scope of this identity review") unless valid
  end

  def immutable_payload
    errors.add(:base, "cannot replace retained review history") if persisted? && (changed - [ "updated_at" ]).any?
  end
end
