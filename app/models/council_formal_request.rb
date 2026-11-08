class CouncilFormalRequest < ApplicationRecord
  belongs_to :council_formal_review
  belongs_to :council_ai_reservation
  attr_readonly :council_formal_review_id, :attempt, :messages, :request_parameters, :started_at, :council_ai_reservation_id
  validates :attempt, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :council_formal_review_id }
  validates :status, inclusion: { in: %w[dispatched received uncertain] }
  validates :messages, :request_parameters, :started_at, presence: true
  validate :retain_finished_receipt
  before_destroy { throw :abort }

  private

  def retain_finished_receipt
    errors.add(:base, "cannot replace a finished request receipt") if persisted? && status_in_database != "dispatched" && changed?
  end
end
