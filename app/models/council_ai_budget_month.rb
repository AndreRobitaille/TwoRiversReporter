class CouncilAiBudgetMonth < ApplicationRecord
  include CouncilAiAuthorization

  validates :budget_month, presence: true, uniqueness: true
  validates :limit_microusd, numericality: { only_integer: true, greater_than: 0 }
  validate :first_day_of_month

  def reservations
    CouncilAiReservation.joins(council_ai_budget_run: :council_ai_budget_day)
      .where(council_ai_budget_days: { budget_on: budget_month.all_month })
  end

  def reserved_microusd
    reservations.sum(:reserved_microusd)
  end

  private

  def first_day_of_month
    errors.add(:budget_month, "must be the first day of the month") if budget_month && budget_month != budget_month.beginning_of_month
  end
end
