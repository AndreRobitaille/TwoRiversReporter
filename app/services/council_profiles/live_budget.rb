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
        unless in_window?(stage, policy)
          raise ReserveAiSpend::Paused, "outside_live_meeting_window"
        end
        quote = Campaigns::CostPreflight.for_stage(stage)
        check_quote!(quote, policy)
        day = budget_day(month, policy)
        day.with_lock do
          stage.with_lock do
            return unless stage.status.in?(%w[pending failed budget_paused]) && stage.attempts < stage.class::MAX_ATTEMPTS
            run = stage.council_ai_budget_run
            raise ReserveAiSpend::Paused, "live_run_revoked" if run&.live_budget_month_id && run.revoked_at
            if run&.live_budget_month_id == month.id && run.council_ai_budget_day_id == day.id && !run.revoked_at && run.expires_at > Time.current
              return run
            end
            remaining = stage.class::MAX_ATTEMPTS - stage.attempts
            run = create_run!(month, day, policy, quote, stage.input_key, remaining)
            stage.update!(council_ai_budget_run: run)
            run
          end
        end
      end
    end

    def self.check_quote!(quote, policy)
      raise ReserveAiSpend::Paused, "live_estimate_unavailable" unless quote[:state] == "estimate"
      unless quote[:model] == policy.fetch("model") && quote[:input_allowance] <= policy.fetch("max_input_tokens") &&
          quote[:output_allowance] <= policy.fetch("max_output_tokens") && quote[:cost_microusd] <= policy.fetch("request_limit_microusd")
        raise ReserveAiSpend::Paused, "live_request_limit"
      end
    end

    def self.budget_day(month, policy)
      CouncilAiBudgetDay.find_or_create_by!(budget_on: Date.current) do |row|
        row.assign_attributes(authorization(month).merge(limit_microusd: policy.fetch("daily_limit_microusd")))
      end
    end

    def self.create_run!(month, day, policy, quote, key, remaining)
      estimate = {
        "stage_key" => key, "request_digest" => quote.fetch(:request_digest),
        "input_tokens" => quote.fetch(:input_allowance), "max_output_tokens" => quote.fetch(:output_allowance),
        "input_rate_microusd" => quote.fetch(:input_rate_microusd), "output_rate_microusd" => quote.fetch(:output_rate_microusd),
        "estimate_basis" => { "model" => quote.fetch(:model), "token_count_method" => "UTF-8 bytes plus 1024 framing allowance; conservative estimate, not measured usage",
          "pricing_source" => quote.fetch(:pricing_source), "checked_at" => quote.fetch(:pricing_checked_on).iso8601 }
      }
      CouncilAiBudgetRun.create!(authorization(month).merge(council_ai_budget_day: day, live_budget_month: month,
        expires_at: Date.current.end_of_day, request_estimates: [ estimate ],
        limit_microusd: quote.fetch(:cost_microusd) * remaining, request_limit_microusd: policy.fetch("request_limit_microusd"),
        max_requests: remaining, max_concurrent: 1, max_input_tokens: policy.fetch("max_input_tokens"), max_output_tokens: policy.fetch("max_output_tokens")))
    end

    def self.in_window?(stage, policy)
      date = stage.is_a?(TermSummaryRequest) ? stage.cycle : meeting_for(stage)&.reload&.starts_at&.to_date
      date && date.between?(Date.iso8601(policy.fetch("starting_on")), Date.current)
    end

    def self.policy_for(stage, month)
      policy = month.live_actions
      return if policy.blank?
      if stage.is_a?(TermSummaryRequest)
        return policy.merge("model" => Ai::OpenAiService::LIGHTWEIGHT_MODEL) if month.auto_renew? && !month.revoked_at && month.actor&.admin? && month.actor.active_for_authentication?
        return
      end
      return policy if stage.is_a?(CampaignActionReview) && !stage.issue_evidence?
      source = stage.is_a?(CampaignActionReview) ? stage.issue_review : stage
      return unless source.is_a?(CouncilIssueReview) || source.is_a?(SavedMeetingEvidence)
      scope = policy["issue_sources"]
      document = source.meeting_document
      return if stage.is_a?(CouncilIssueReview) && !LiveSources.extraction_types(scope).include?(document&.document_type)
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
