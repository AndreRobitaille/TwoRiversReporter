class CouncilAiReservation < ApplicationRecord
  belongs_to :council_ai_budget_run
  has_one :minutes_request, dependent: :restrict_with_exception
  attr_readonly :council_ai_budget_run_id, :request_key, :request_estimate, :reserved_microusd
  validates :request_key, presence: true, uniqueness: true
  validates :reserved_microusd, numericality: { only_integer: true, greater_than: 0 }
  validate :retain_completion
  before_destroy { throw :abort }

  private

  def retain_completion
    if persisted? && finished_at_in_database && will_save_change_to_finished_at?
      errors.add(:finished_at, "cannot reopen a completed reservation")
    end
  end
end
