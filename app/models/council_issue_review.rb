class CouncilIssueReview < ApplicationRecord
  MAX_ATTEMPTS = 2
  belongs_to :meeting_document, optional: true
  belongs_to :council_ai_budget_run, optional: true
  has_many :requests, class_name: "CouncilIssueRequest", dependent: :restrict_with_exception
  attr_readonly :input_key, :context, :parameters
  validates :input_key, uniqueness: true, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :status, inclusion: { in: %w[pending running completed failed uncertain incomplete oversized budget_paused] }
  validate :retain_completed_output

  def budget_required?
    true
  end

  def budget_request_key
    "council_issue/#{id}/#{attempts}"
  end

  def claim!(budget_run)
    with_lock do
      return false unless status.in?(%w[pending failed budget_paused]) && attempts < MAX_ATTEMPTS
      update!(status: "running", attempts: attempts + 1, council_ai_budget_run: budget_run, error_code: nil)
    end
    true
  end

  private

  def retain_completed_output
    if persisted? && status_in_database == "completed" &&
        (will_save_change_to_data? || will_save_change_to_status? || will_save_change_to_completed_at?)
      errors.add(:data, "cannot replace a completed review")
    end
  end
end
