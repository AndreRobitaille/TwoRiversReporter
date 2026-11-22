# One shared historical allowance across calendar boundaries. In-flight and
# unknown requests retain their entire reservation.
class CouncilHistoryRequest < ApplicationRecord
  TOTAL_LIMIT = 75_000_000
  PILOT_LIMIT = 5_000_000

  def self.reserve!(meeting_id:, stage:, pilot:, parameters:)
    raise "Historical reservation must commit before transport" if connection.transaction_open?
    estimate = Campaigns::CostPreflight.for_parameters(parameters)
    raise CouncilProfiles::ReserveAiSpend::Paused, "historical_pricing_unavailable" unless estimate[:state] == "estimate"
    amount = estimate.fetch(:cost_microusd)
    transaction do
      connection.execute("SELECT pg_advisory_xact_lock(234, 245)")
      previous = where(meeting_id: meeting_id, stage: stage, request_digest: estimate.fetch(:request_digest))
      raise CouncilProfiles::ReserveAiSpend::Paused, "historical_request_uncertain" if previous.where(finished_at: nil).exists?
      raise CouncilProfiles::ReserveAiSpend::Paused, "historical_retry_limit" if previous.count >= 2
      raise CouncilProfiles::ReserveAiSpend::Paused, "historical_total_limit" if sum(:charged_microusd) + amount > TOTAL_LIMIT
      if pilot && where(pilot: true).sum(:charged_microusd) + amount > PILOT_LIMIT
        raise CouncilProfiles::ReserveAiSpend::Paused, "historical_pilot_limit"
      end
      create!(meeting_id: meeting_id, stage: stage, pilot: pilot, model: parameters.fetch(:model),
        request_digest: estimate.fetch(:request_digest), reserved_microusd: amount, charged_microusd: amount)
    end.then { |row| [ row, estimate ] }
  end

  def finish!(response, estimate)
    counts = Ai::OpenAiService.usage_from(response).stringify_keys
    amount = reserved_microusd
    if counts.values_at("input_tokens", "output_tokens").all? { |value| value.is_a?(Integer) && value >= 0 }
      amount = CouncilProfiles::RequestEstimate.ceiling_microusd(
        "input_tokens" => counts.fetch("input_tokens"), "max_output_tokens" => counts.fetch("output_tokens"),
        "input_rate_microusd" => estimate.fetch(:input_rate_microusd), "output_rate_microusd" => estimate.fetch(:output_rate_microusd))
    end
    update!(finished_at: Time.current, provider_response_id: response["id"], usage: counts, charged_microusd: amount)
  end
end
