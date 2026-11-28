module CouncilProfiles
  # A weekly narrative reuses accepted evidence. Its single dispatch shares
  # the standing Council spending ledger, without opening historical extraction.
  class TermSummaryRequest
    attr_reader :input_key, :budget_request_key, :council_ai_budget_run_id, :cycle

    def initialize(summary, cycle, evidence, authorized_run: nil, draft_id: nil)
      @summary, @cycle = summary, cycle
      @input_key = evidence.digest
      @council_ai_budget_run_id = authorized_run&.id
      @draft_id = draft_id
      @budget_request_key = [ "term-summary", summary.id, cycle.iso8601, draft_id ].compact.join("/")
    end

    def start!(parameters)
      # A separately authorized first publication can use its exact, single-use
      # run. The Tuesday scheduler only uses the standing allowance below.
      return reserve!(parameters) if council_ai_budget_run_id

      month = CouncilAiBudgetMonth.find_by!(budget_month: Date.current.beginning_of_month)
      raise ReserveAiSpend::Paused, "missing_standing_budget" unless LiveBudget.policy_for(self, month)
      Campaigns::LivePricing.refresh_model(parameters.fetch(:model)) unless Campaigns::LivePricing.checked_on(parameters.fetch(:model))
      quote = Campaigns::CostPreflight.for_parameters(parameters)
      month.with_lock do
        policy = LiveBudget.policy_for(self, month)
        raise ReserveAiSpend::Paused, "missing_standing_budget" unless policy
        LiveBudget.check_quote!(quote, policy)
        day = LiveBudget.budget_day(month, policy)
        day.with_lock do
          check_pending!(@summary.reload)
          @council_ai_budget_run_id = LiveBudget.create_run!(month, day, policy, quote, input_key, 1).id
          reserve!(parameters)
        end
      end
    rescue ActiveRecord::RecordNotFound
      raise ReserveAiSpend::Paused, "missing_standing_budget"
    end

    def reserve!(parameters)
      ReserveAiSpend.with_reservation(self, parameters) do |reservation|
        @summary.with_lock do
          check_pending!(@summary)
          @summary.update!(attempted_cycle: cycle)
          @reservation = reservation
        end
      end
    end
    def check_pending!(summary)
      if @draft_id
        return if council_ai_budget_run_id && summary.attempted_cycle == cycle && !summary.complete_for?(input_key)
        raise ReserveAiSpend::Paused, "draft_already_processed"
      end
      if (summary.attempted_cycle && summary.attempted_cycle >= cycle) || summary.evidence_digest == input_key
        raise ReserveAiSpend::Paused, "summary_already_processed"
      end
    end
    private :reserve!, :check_pending!

    def received!(response, duration_ms:)
      @reservation.update!(finished_at: Time.current, provider_usage: Ai::OpenAiService.usage_from(response))
    end

    def uncertain!(_error)
      # Retain the full reservation even when the provider outcome is unknown.
      @reservation&.update!(finished_at: Time.current) unless @reservation&.finished_at
    end
  end
end
