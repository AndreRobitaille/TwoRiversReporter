class MinutesExtraction < ApplicationRecord
  MAX_ATTEMPTS = 2
  KINDS = %w[votes attendance].freeze

  belongs_to :meeting, optional: true
  belongs_to :meeting_document_text_version, optional: true
  belongs_to :council_ai_budget_run, optional: true
  has_many :council_decision_observations, dependent: :restrict_with_exception
  has_many :requests, class_name: "MinutesRequest", dependent: :restrict_with_exception
  attr_readonly :original_meeting_id, :meeting_document_text_version_id, :kind,
    :input_key, :source_key, :input_manifest, :source_text

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: %w[pending running completed failed uncertain oversized incomplete budget_paused] }
  validates :input_key, uniqueness: true, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :source_key, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :data, presence: true, if: -> { status == "completed" }
  validate :completed_output_is_immutable
  validate :retain_budget_requirement

  def retryable?
    status.in?(%w[pending failed budget_paused]) && attempts < MAX_ATTEMPTS
  end

  def claim!
    with_lock do
      return false unless retryable?
      update!(status: "running", attempts: attempts + 1, started_at: Time.current, error_code: nil)
    end
    true
  end

  private

  def retain_budget_requirement
    if persisted? && budget_required_in_database && will_save_change_to_budget_required?
      errors.add(:budget_required, "cannot bypass a required budget")
    end
  end

  def completed_output_is_immutable
    return unless persisted? && status_in_database == "completed"
    if will_save_change_to_data? || will_save_change_to_evidence_locations? || will_save_change_to_status? || will_save_change_to_completed_at?
      errors.add(:data, "cannot replace a completed extraction")
    end
  end
end
