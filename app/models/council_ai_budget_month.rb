class CouncilAiBudgetMonth < ApplicationRecord
  include CouncilAiAuthorization

  validates :budget_month, presence: true, uniqueness: true
  validates :limit_microusd, numericality: { only_integer: true, greater_than: 0 }
  validate :first_day_of_month
  validate :live_action_policy

  def reservations
    CouncilAiReservation.joins(council_ai_budget_run: :council_ai_budget_day)
      .where(council_ai_budget_days: { budget_on: budget_month.all_month })
  end

  def reserved_microusd
    reservations.sum(:reserved_microusd)
  end

  private

  def live_action_policy
    return if live_actions == {}

    fields = %w[daily_limit_microusd request_limit_microusd max_requests_per_day max_concurrent max_input_tokens max_output_tokens]
    unless live_actions.is_a?(Hash) && (live_actions.keys - fields - %w[model starting_on estimate_method]).empty? &&
        fields.all? { |key| live_actions[key].is_a?(Integer) && live_actions[key].positive? } &&
        live_actions["model"].is_a?(String) && live_actions["model"].present? &&
        live_actions["estimate_method"] == "utf8_bytes_plus_1024"
      errors.add(:live_actions, "requires explicit limits, model and conservative estimation method")
      return
    end
    starting_on = Date.iso8601(live_actions.fetch("starting_on"))
    # A renewal may retain an already-authorized live window; it cannot expand
    # that window backwards and accidentally become a historical backfill.
    earlier_policy = self.class.where.not(id: id).where("authorized_at <= ?", authorized_at)
      .where("live_actions->>'starting_on' = ?", starting_on.iso8601).exists?
    if authorized_at && starting_on < authorized_at.to_date && !earlier_policy
      errors.add(:live_actions, "cannot authorize historical meetings")
    end
  rescue KeyError, ArgumentError, TypeError
    errors.add(:live_actions, "requires an ISO starting date")
  end

  def first_day_of_month
    errors.add(:budget_month, "must be the first day of the month") if budget_month && budget_month != budget_month.beginning_of_month
  end
end
