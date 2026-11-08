class CampaignRequest < ApplicationRecord
  belongs_to :campaign_extraction
  belongs_to :council_ai_reservation
  attr_readonly :campaign_extraction_id, :attempt, :messages, :request_parameters, :started_at, :council_ai_reservation_id

  validates :attempt, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :campaign_extraction_id }
  validates :status, inclusion: { in: %w[dispatched received uncertain] }
  validates :messages, :request_parameters, :started_at, presence: true
  validate :retain_finished_receipt
  before_destroy { throw :abort }

  private

  def retain_finished_receipt
    if persisted? && status_in_database != "dispatched" && changed?
      errors.add(:base, "cannot replace a finished request receipt")
    end
  end
end
