class CouncilDecisionAssignment < ApplicationRecord
  belongs_to :observation, class_name: "CouncilDecisionObservation"
  belongs_to :minutes_extraction
  belongs_to :council_decision, optional: true
  belongs_to :correction, class_name: "CouncilDecisionCorrection", optional: true
  attr_readonly :observation_id, :minutes_extraction_id
  validates :observation_id, uniqueness: true
  validate :consistent_identity

  private

  def consistent_identity
    valid = observation && minutes_extraction_id == observation.minutes_extraction_id &&
      (!council_decision || council_decision.original_meeting_id == minutes_extraction.original_meeting_id)
    valid &&= if correction
      correction.after_decision_id == council_decision_id && correction.applies_to?(observation)
    else
      council_decision_id == observation.council_decision_id
    end
    valid &&= conflicting_correction_ids.is_a?(Array) && conflicting_correction_ids.all? { |id| id.is_a?(Integer) }
    if valid && conflicting_correction_ids.any?
      valid &&= correction.nil? && council_decision.nil? && observation.identity_status == "unresolved" &&
        CouncilDecisionCorrection.joins(observation: :minutes_extraction)
          .where(id: conflicting_correction_ids, minutes_extractions: { original_meeting_id: minutes_extraction.original_meeting_id }).count == conflicting_correction_ids.size
    end
    if persisted? && (will_save_change_to_council_decision_id? || will_save_change_to_correction_id? || will_save_change_to_conflicting_correction_ids?)
      valid &&= correction && correction.observation_id == observation_id &&
        correction.previous_correction_id == correction_id_in_database &&
        correction.before_decision_id == council_decision_id_in_database &&
        correction.evidence_manifest["resolved_conflict_ids"] == conflicting_correction_ids_in_database
    end
    errors.add(:base, "requires a compatible extraction or append-only correction") unless valid
  end
end
