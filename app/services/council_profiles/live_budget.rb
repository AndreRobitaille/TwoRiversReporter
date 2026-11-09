module CouncilProfiles
  # A monthly opt-in admits new action comparisons and explicitly registered
  # official source types, never implicit historical work or campaign intake. Every request pins a conservative estimate to its exact
  # prepared parameters before reserving funds.
  class LiveBudget
    def self.call(stage)
      return unless stage.status.in?(%w[pending failed budget_paused]) && stage.attempts < stage.class::MAX_ATTEMPTS
      month = CouncilAiBudgetMonth.find_by(budget_month: Date.current.beginning_of_month)
      return unless month && month.live_actions.present?

      month.with_lock do
        raise ReserveAiSpend::Paused, "monthly_budget_revoked" if month.revoked_at
        unless month.actor&.admin? && month.actor.active_for_authentication?
          raise ReserveAiSpend::Paused, "live_budget_actor_unavailable"
        end
        policy = policy_for(stage, month)
        raise ReserveAiSpend::Paused, "outside_live_source_scope" unless policy
        meeting = meeting_for(stage)
        unless meeting && meeting.starts_at.to_date.between?(Date.iso8601(policy.fetch("starting_on")), Date.current)
          raise ReserveAiSpend::Paused, "outside_live_meeting_window"
        end
        quote = Campaigns::CostPreflight.for_stage(stage)
        raise ReserveAiSpend::Paused, "live_estimate_unavailable" unless quote[:state] == "estimate"
        unless quote[:model] == policy.fetch("model") && quote[:input_allowance] <= policy.fetch("max_input_tokens") &&
            quote[:output_allowance] <= policy.fetch("max_output_tokens") && quote[:cost_microusd] <= policy.fetch("request_limit_microusd")
          raise ReserveAiSpend::Paused, "live_request_limit"
        end

        day = CouncilAiBudgetDay.find_or_create_by!(budget_on: Date.current) do |row|
          row.assign_attributes(authorization(month).merge(limit_microusd: policy.fetch("daily_limit_microusd")))
        end
        day.with_lock do
          stage.with_lock do
            return unless stage.status.in?(%w[pending failed budget_paused]) && stage.attempts < stage.class::MAX_ATTEMPTS
            run = stage.council_ai_budget_run
            raise ReserveAiSpend::Paused, "live_run_revoked" if run&.live_budget_month_id && run.revoked_at
            if run&.live_budget_month_id == month.id && run.council_ai_budget_day_id == day.id && !run.revoked_at && run.expires_at > Time.current
              return run
            end
            estimate = {
              "stage_key" => stage.input_key, "request_digest" => quote.fetch(:request_digest),
              "input_tokens" => quote.fetch(:input_allowance), "max_output_tokens" => quote.fetch(:output_allowance),
              "input_rate_microusd" => quote.fetch(:input_rate_microusd), "output_rate_microusd" => quote.fetch(:output_rate_microusd),
              "estimate_basis" => { "model" => quote.fetch(:model), "token_count_method" => "UTF-8 bytes plus 1024 framing allowance; conservative estimate, not measured usage",
                "pricing_source" => quote.fetch(:pricing_source), "checked_at" => quote.fetch(:pricing_checked_on).iso8601 }
            }
            remaining = stage.class::MAX_ATTEMPTS - stage.attempts
            run = CouncilAiBudgetRun.create!(authorization(month).merge(council_ai_budget_day: day, live_budget_month: month,
              expires_at: Date.current.end_of_day, request_estimates: [ estimate ],
              limit_microusd: quote.fetch(:cost_microusd) * remaining, request_limit_microusd: policy.fetch("request_limit_microusd"),
              max_requests: remaining, max_concurrent: 1, max_input_tokens: policy.fetch("max_input_tokens"), max_output_tokens: policy.fetch("max_output_tokens")))
            stage.update!(council_ai_budget_run: run)
            run
          end
        end
      end
    end

    def self.policy_for(stage, month)
      policy = month.live_actions
      return if policy.blank?
      return policy if stage.is_a?(CampaignActionReview) && !stage.issue_evidence?
      source = stage.is_a?(CampaignActionReview) ? stage.issue_review : stage
      return unless source.is_a?(CouncilIssueReview) || source.is_a?(SavedMotionEvidence)
      scope = policy["issue_sources"]
      document = source.meeting_document
      return if stage.is_a?(CouncilIssueReview) && !document&.document_type.in?(LiveSources::EXTRACTION_TYPES)
      return unless scope && document && scope.fetch("document_types").include?(document.document_type) &&
        scope.fetch("committee_ids").include?(document.meeting.committee_id)
      policy.merge("starting_on" => scope.fetch("starting_on"))
    end

    def self.meeting_for(stage)
      stage.is_a?(CouncilIssueReview) ? stage.meeting_document&.meeting : stage.meeting
    end

    def self.authorization(month)
      { actor: month.actor, authorized_at: month.authorized_at,
        authorization_basis: "Derived live council evidence allowance from monthly authorization #{month.id}" }
    end
    private_class_method :authorization
  end
end
