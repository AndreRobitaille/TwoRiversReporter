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

      month = CouncilAiBudgetMonth.find_by(budget_month: run.council_ai_budget_day.budget_on.beginning_of_month)
      raise Paused, "missing_monthly_budget" unless month

      # All admission paths use month -> day -> run -> stage locks. Reservations and the
      # dispatch receipt commit together before provider transport can start.
      month.with_lock do
        run.council_ai_budget_day.with_lock do
          run.with_lock do
            raise Paused, "monthly_budget_revoked" if month.revoked_at
            day = run.council_ai_budget_day
            raise Paused, "budget_expired" unless day.budget_on == Date.current && run.expires_at > Time.current
            raise Paused, "budget_revoked" if run.revoked_at
            if run.live_budget_month_id
              policy = LiveBudget.policy_for(stage, month)
              raise Paused, "live_policy_mismatch" unless run.live_budget_month_id == month.id && policy.present?
              unless LiveBudget.meeting_for(stage)&.reload&.starts_at&.to_date&.between?(Date.iso8601(policy.fetch("starting_on")), Date.current)
                raise Paused, "outside_live_meeting_window"
              end
              daily_requests = CouncilAiReservation.joins(:council_ai_budget_run).where(council_ai_budget_runs: { council_ai_budget_day_id: day.id })
              raise Paused, "live_daily_request_limit" if daily_requests.count >= policy.fetch("max_requests_per_day")
              raise Paused, "live_concurrency_limit" if month.reservations.where(finished_at: nil).count >= policy.fetch("max_concurrent")
            end
            digest = request_digest(parameters)
            estimate = run.request_estimates.find { |row| row["stage_key"] == stage.input_key && row["request_digest"] == digest }
            raise Paused, "missing_request_estimate" unless estimate
            raise Paused, "estimate_model_mismatch" unless estimate.fetch("estimate_basis").fetch("model") == parameters[:model]
            raise Paused, "input_token_limit" if estimate.fetch("input_tokens") > run.max_input_tokens
            if parameters[:max_completion_tokens] != estimate.fetch("max_output_tokens") || estimate.fetch("max_output_tokens") > run.max_output_tokens
              raise Paused, "output_token_limit"
            end
            amount = RequestEstimate.ceiling_microusd(estimate)
            if run.live_budget_month_id && day.reserved_microusd + amount > month.live_actions.fetch("daily_limit_microusd")
              raise Paused, "live_daily_budget_limit"
            end
            raise Paused, "request_budget_limit" if amount > run.request_limit_microusd
            raise Paused, "run_budget_limit" if run.reservations.sum(:reserved_microusd) + amount > run.limit_microusd
            raise Paused, "monthly_budget_limit" if month.reserved_microusd + amount > month.effective_limit_microusd
            raise Paused, "daily_budget_limit" if day.reserved_microusd + amount > day.effective_limit_microusd
            raise Paused, "request_count_limit" if run.reservations.count >= run.max_requests
            raise Paused, "concurrency_limit" if run.reservations.where(finished_at: nil).count >= run.max_concurrent

            reservation = run.reservations.create!(request_key: stage.budget_request_key, reserved_microusd: amount,
              request_estimate: estimate)
            yield reservation
          end
        end
      end
    end
  end
end
