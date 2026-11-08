module Campaigns
  # Offline planning only. This neither authorizes work nor supplies a verified
  # token count to spending admission. Actual Chat Completions framing is unknown.
  class CostPreflight
    PRICING_CHECKED_ON = Date.new(2026, 11, 8)
    PRICING_VALID_THROUGH = Date.new(2026, 11, 21)
    PRICING_SOURCE = "https://developers.openai.com/api/docs/models/".freeze
    # Micro-USD per million tokens, Standard direct API, including 1.25x cache
    # writes on every input token; no assumed cache discount. See evidence doc.
    RATES = {
      "gpt-5.6-luna" => [ 250_000, 1_200_000 ],
      "gpt-5.6-terra" => [ 2_500_000, 12_000_000 ],
      "gpt-5.6-sol" => [ 5_000_000, 20_000_000 ]
    }.freeze
    FORMATTING_ALLOWANCE = 1_024

    def self.call(version)
      stage = version.extraction
      parameters = stage ? stage.parameters.deep_symbolize_keys : Ai::OpenAiService.campaign_request_parameters(version)
      estimate(stage, parameters)
    rescue Ai::OpenAiService::InputTooLargeError
      { state: "held", reason: "Source needs partitioning" }
    rescue ActiveRecord::RecordNotFound
      { state: "unavailable", reason: "Campaign extraction prompt is missing" }
    end

    def self.for_stage(stage)
      estimate(stage, stage.parameters.deep_symbolize_keys)
    end

    def self.estimate(stage, parameters)
      return { state: "reuse", cost_microusd: 0 } if stage&.status == "completed"
      if stage && !stage.status.in?(%w[pending failed budget_paused])
        return { state: "held", reason: stage.status.humanize }
      end

      if CampaignExtraction.exists?(purpose: stage&.purpose || "statements", status: "completed", parameters: parameters)
        return { state: "reuse", cost_microusd: 0 }
      end
      attempts = CampaignExtraction::MAX_ATTEMPTS - (stage&.attempts || 0)
      return { state: "held", reason: "Attempt limit reached" } unless attempts.positive?
      return { state: "unavailable", reason: "Pricing needs to be checked again" } unless Date.current.between?(PRICING_CHECKED_ON, PRICING_VALID_THROUGH)

      model = parameters.fetch(:model)
      rates = RATES[model]
      return { state: "unavailable", reason: "No checked pricing for this model" } unless rates
      return { state: "unavailable", reason: "Request format needs a separate estimate" } unless supported_request?(parameters)

      # One token per UTF-8 byte plus a generous formatting allowance is an
      # intentionally conservative planning assumption, not measured API usage.
      input_allowance = parameters.fetch(:messages).sum { |message| message.fetch(:content).bytesize } + FORMATTING_ALLOWANCE
      output_allowance = parameters.fetch(:max_completion_tokens)
      input_rate, output_rate = rates
      if input_allowance > 272_000
        input_rate *= 2
        output_rate = output_rate * 3 / 2
      end
      amount = CouncilProfiles::RequestEstimate.ceiling_microusd(
        "input_tokens" => input_allowance, "max_output_tokens" => output_allowance,
        "input_rate_microusd" => input_rate, "output_rate_microusd" => output_rate)
      { state: "estimate", model: model, input_allowance: input_allowance,
        output_allowance: output_allowance, cost_microusd: amount,
        attempts_remaining: attempts, remaining_cost_microusd: amount * attempts,
        request_digest: CouncilProfiles::ReserveAiSpend.request_digest(parameters),
        pricing_source: PRICING_SOURCE + model, pricing_checked_on: PRICING_CHECKED_ON,
        pricing_valid_through: PRICING_VALID_THROUGH }
    end
    private_class_method :estimate

    def self.supported_request?(parameters)
      allowed = %i[model messages reasoning_effort temperature response_format max_completion_tokens]
      (parameters.keys - allowed).empty? && parameters[:response_format] == { type: "json_object" } &&
        parameters[:max_completion_tokens].is_a?(Integer) && parameters[:max_completion_tokens].positive? &&
        parameters[:messages].is_a?(Array) && parameters[:messages].size.in?(1..2) &&
        parameters[:messages].all? do |message|
          message.is_a?(Hash) && (message.keys - %i[role content]).empty? &&
            message[:role].in?(%w[system user]) && message[:content].is_a?(String)
        end
    end
    private_class_method :supported_request?
  end
end
