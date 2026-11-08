class CampaignExtraction < ApplicationRecord
  MAX_ATTEMPTS = 2

  belongs_to :campaign_source_version
  belongs_to :council_ai_budget_run, optional: true
  belongs_to :reused_from, class_name: "CampaignExtraction", optional: true
  has_many :requests, class_name: "CampaignRequest", dependent: :restrict_with_exception
  attr_readonly :campaign_source_version_id, :input_key, :parameters
  validates :input_key, uniqueness: true, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :campaign_source_version_id, uniqueness: true
  validates :status, inclusion: { in: %w[pending running completed failed uncertain incomplete oversized budget_paused] }
  validate :retain_completed_output

  def budget_required?
    true
  end

  def budget_request_key
    "campaign/#{id}/#{attempts}"
  end

  def claim!(budget_run)
    with_lock do
      return false unless status.in?(%w[pending failed budget_paused])
      if reused = self.class.find_by(status: "completed", parameters: parameters)
        update!(status: "completed", data: reused.data, completed_at: reused.completed_at, reused_from: reused, error_code: nil)
        return false
      end
      return false unless attempts < MAX_ATTEMPTS
      update!(status: "running", attempts: attempts + 1, council_ai_budget_run: budget_run, error_code: nil)
    end
    true
  end

  private

  def retain_completed_output
    if persisted? && status_in_database == "completed" &&
        (will_save_change_to_data? || will_save_change_to_status? || will_save_change_to_completed_at? || will_save_change_to_reused_from_id?)
      errors.add(:data, "cannot replace a completed extraction")
    end
  end
end
