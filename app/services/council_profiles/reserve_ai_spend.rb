module CouncilProfiles
  class ReserveAiSpend
    class Paused < StandardError; end

    def self.request_digest(parameters)
      Digest::SHA256.hexdigest(JSON.generate(canonical(parameters.deep_stringify_keys)))
    end

    def self.canonical(value)
      case value
      when Hash then value.sort.to_h.transform_values { |item| canonical(item) }
      when Array then value.map { |item| canonical(item) }
      else value
      end
    end
    private_class_method :canonical

    def self.with_reservation(stage, parameters)
      run = CouncilAiBudgetRun.find_by(id: stage.council_ai_budget_run_id)
      raise Paused, "missing_budget" unless run

      # All admission paths use day -> run -> stage locks. Reservations and the
      # dispatch receipt commit together before provider transport can start.
      run.council_ai_budget_day.with_lock do
        run.with_lock do
          day = run.council_ai_budget_day
          raise Paused, "budget_expired" unless day.budget_on == Date.current && run.expires_at > Time.current
          raise Paused, "budget_revoked" if run.revoked_at
          digest = request_digest(parameters)
          estimate = run.request_estimates.find { |row| row["stage_key"] == stage.input_key && row["request_digest"] == digest }
          raise Paused, "missing_request_estimate" unless estimate
          raise Paused, "estimate_model_mismatch" unless estimate.fetch("estimate_basis").fetch("model") == parameters[:model]
          raise Paused, "input_token_limit" if estimate.fetch("input_tokens") > run.max_input_tokens
          if parameters[:max_completion_tokens] != estimate.fetch("max_output_tokens") || estimate.fetch("max_output_tokens") > run.max_output_tokens
            raise Paused, "output_token_limit"
          end
          amount = RequestEstimate.ceiling_microusd(estimate)
          raise Paused, "request_budget_limit" if amount > run.request_limit_microusd
          raise Paused, "run_budget_limit" if run.reservations.sum(:reserved_microusd) + amount > run.limit_microusd
          raise Paused, "daily_budget_limit" if day.reserved_microusd + amount > day.limit_microusd
          raise Paused, "request_count_limit" if run.reservations.count >= run.max_requests
          raise Paused, "concurrency_limit" if run.reservations.where(finished_at: nil).count >= run.max_concurrent

          reservation = run.reservations.create!(request_key: "minutes/#{stage.id}/#{stage.attempts}", reserved_microusd: amount,
            request_estimate: estimate)
          yield reservation
        end
      end
    end
  end
end
