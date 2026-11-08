class MinutesRequest < ApplicationRecord
  belongs_to :minutes_extraction
  attr_readonly :minutes_extraction_id, :attempt, :messages, :request_parameters, :started_at

  validates :attempt, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :minutes_extraction_id }
  validates :status, inclusion: { in: %w[dispatched received uncertain] }
  validates :messages, :request_parameters, :started_at, presence: true
  validate :terminal_receipt_is_immutable
  before_destroy { throw :abort }

  private

  def terminal_receipt_is_immutable
    if persisted? && status_in_database != "dispatched" && changed?
      errors.add(:base, "cannot replace a finished request receipt")
    end
  end
end
