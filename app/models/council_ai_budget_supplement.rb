# A new explicit approval adds headroom without replacing prior authorizations.
class CouncilAiBudgetSupplement < ApplicationRecord
  include CouncilAiAuthorization

  belongs_to :council_ai_budget_month
  belongs_to :council_ai_budget_day
  validates :authorization_key, presence: true, uniqueness: true
  validates :amount_microusd, numericality: { only_integer: true, greater_than: 0 }
  validate :authorized_period

  def self.authorize!(day:, actor:, amount_microusd:, authorization_key:, authorization_basis:)
    month = CouncilAiBudgetMonth.find_by!(budget_month: day.budget_on.beginning_of_month)
    month.with_lock do
      day.with_lock do
        attributes = { council_ai_budget_month: month, council_ai_budget_day: day, actor: actor,
          amount_microusd: amount_microusd, authorization_basis: authorization_basis }
        if existing = find_by(authorization_key: authorization_key)
          unless attributes.all? { |key, value| existing.public_send(key) == value }
            raise ArgumentError, "Authorization key already identifies a different approval"
          end
          return existing
        end
        create!(**attributes, authorization_key: authorization_key, authorized_at: Time.current)
      end
    end
  end

  private

  def authorized_period
    return unless council_ai_budget_day && council_ai_budget_month && authorized_at

    unless council_ai_budget_day.budget_on == authorized_at.to_date &&
        council_ai_budget_month.budget_month == council_ai_budget_day.budget_on.beginning_of_month
      errors.add(:base, "requires approval for this budget day and month")
    end
    errors.add(:base, "cannot restore a revoked monthly authorization") if council_ai_budget_month.revoked_at
  end
end
