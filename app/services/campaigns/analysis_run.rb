module Campaigns
  # A campaign source can use an existing one-time run only when the exact
  # prepared request was authorized. The reservation service still admits
  # each dispatch under the ledger locks.
  class AnalysisRun
    RETRYABLE = %w[pending failed budget_paused].freeze

    def self.for(stage)
      return unless stage && RETRYABLE.include?(stage.status) && stage.attempts < CampaignExtraction::MAX_ATTEMPTS
      return if stage.parameters.blank?

      day = CouncilAiBudgetDay.find_by(budget_on: Date.current)
      month = CouncilAiBudgetMonth.find_by(budget_month: Date.current.beginning_of_month, revoked_at: nil)
      return unless day && month

      parameters = stage.parameters.deep_symbolize_keys
      identity = { "stage_key" => stage.input_key, "request_digest" => CouncilProfiles::ReserveAiSpend.request_digest(parameters) }
      runs = day.runs.where(revoked_at: nil, live_budget_month_id: nil).where("expires_at > ?", Time.current)
        .where("request_estimates @> CAST(? AS jsonb)", [ identity ].to_json).order(:expires_at)
      runs.find do |run|
        estimate = run.request_estimates.find { |entry| entry.slice(*identity.keys) == identity }
        request_fits?(run, estimate, parameters, day, month)
      end
    end

    def self.request_fits?(run, estimate, parameters, day, month)
      amount = CouncilProfiles::RequestEstimate.ceiling_microusd(estimate)
      estimate.dig("estimate_basis", "model") == parameters[:model] &&
        estimate.fetch("input_tokens") <= run.max_input_tokens &&
        estimate.fetch("max_output_tokens") == parameters[:max_completion_tokens] &&
        estimate.fetch("max_output_tokens") <= run.max_output_tokens &&
        amount <= run.request_limit_microusd &&
        amount + run.reservations.sum(:reserved_microusd) <= run.limit_microusd &&
        amount + day.reserved_microusd <= day.effective_limit_microusd &&
        amount + month.reserved_microusd <= month.effective_limit_microusd &&
        run.reservations.count < run.max_requests &&
        run.reservations.where(finished_at: nil).count < run.max_concurrent
    end
    private_class_method :request_fits?
  end
end
