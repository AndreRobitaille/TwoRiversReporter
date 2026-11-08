module CouncilProfiles
  class RequestEstimate
    INTEGER_FIELDS = %w[input_tokens max_output_tokens input_rate_microusd output_rate_microusd].freeze

    def self.valid?(estimate)
      estimate.is_a?(Hash) &&
        %w[stage_key request_digest].all? { |key| estimate[key].is_a?(String) && estimate[key].match?(/\A[0-9a-f]{64}\z/) } &&
        INTEGER_FIELDS.all? { |key| estimate[key].is_a?(Integer) && estimate[key].positive? } &&
        estimate["estimate_basis"].is_a?(Hash) &&
        %w[model token_count_method pricing_source checked_at].all? { |key| estimate["estimate_basis"][key].is_a?(String) && estimate["estimate_basis"][key].present? }
    end

    # Rates are micro-USD per million tokens. Prepared estimates must include
    # applicable pricing uplifts; no speculative cache discount or float math.
    def self.ceiling_microusd(estimate)
      (estimate.fetch("input_tokens") * estimate.fetch("input_rate_microusd") +
        estimate.fetch("max_output_tokens") * estimate.fetch("output_rate_microusd") + 999_999) / 1_000_000
    end
  end
end
