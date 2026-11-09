class CouncilAiBudgetDay < ApplicationRecord
  include CouncilAiAuthorization

  has_many :runs, class_name: "CouncilAiBudgetRun", dependent: :restrict_with_exception
  has_many :supplements, class_name: "CouncilAiBudgetSupplement", dependent: :restrict_with_exception
  validates :budget_on, presence: true, uniqueness: true
  validates :limit_microusd, numericality: { only_integer: true, greater_than: 0 }

  def reserved_microusd
    CouncilAiReservation.joins(:council_ai_budget_run)
      .where(council_ai_budget_runs: { council_ai_budget_day_id: id }).sum(:reserved_microusd)
  end

  def effective_limit_microusd
    limit_microusd + supplements.sum(:amount_microusd)
  end
end
