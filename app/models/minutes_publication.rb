class MinutesPublication < ApplicationRecord
  belongs_to :meeting, optional: true
  belongs_to :votes_extraction, class_name: "MinutesExtraction"
  belongs_to :attendance_extraction, class_name: "MinutesExtraction"
  attr_readonly :original_meeting_id, :votes_extraction_id, :attendance_extraction_id, :fingerprint, :projection_context

  validates :fingerprint, uniqueness: true, format: { with: /\A[0-9a-f]{64}\z/ }
  validate :compatible_completed_extractions

  private

  def compatible_completed_extractions
    stages = [ votes_extraction, attendance_extraction ]
    valid = stages.all? { |stage| stage&.status == "completed" && stage.original_meeting_id == original_meeting_id } &&
      votes_extraction.kind == "votes" && attendance_extraction.kind == "attendance" &&
      votes_extraction.source_key == attendance_extraction.source_key
    errors.add(:base, "requires completed votes and attendance from the same source") unless valid
  end
end
