class CouncilAiBudgetRun < ApplicationRecord
  include CouncilAiAuthorization

  belongs_to :council_ai_budget_day
  belongs_to :live_budget_month, class_name: "CouncilAiBudgetMonth", optional: true
  has_many :reservations, class_name: "CouncilAiReservation", dependent: :restrict_with_exception
  validates :limit_microusd, :request_limit_microusd, :max_requests, :max_concurrent, :max_input_tokens, :max_output_tokens,
    numericality: { only_integer: true, greater_than: 0 }
  validates :expires_at, presence: true
  validate :prepared_request_estimates

  private

  def prepared_request_estimates
    unless request_estimates.is_a?(Array) && request_estimates.any? &&
        request_estimates.all? { |estimate| CouncilProfiles::RequestEstimate.valid?(estimate) } &&
        request_estimates.map { |estimate| estimate.values_at("stage_key", "request_digest") }.uniq.size == request_estimates.size
      errors.add(:request_estimates, "must contain exact prepared request estimates")
    end
  end
end
