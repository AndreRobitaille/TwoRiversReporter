module CouncilProfiles
  # Read-only accounting for the council ledger, not the provider's invoice or
  # the application's unrelated AI work. Uses the rates approved for each call.
  class SpendReport
    def self.call(date: Date.current)
      month = CouncilAiBudgetMonth.find_by(budget_month: date.beginning_of_month)
      reservations = (month || CouncilAiBudgetMonth.new(budget_month: date.beginning_of_month)).reservations.to_a
      ids = reservations.map(&:id)
      receipts = MinutesRequest.where(council_ai_reservation_id: ids).to_a +
        CampaignRequest.includes(:campaign_extraction).where(council_ai_reservation_id: ids).to_a +
        CampaignActionRequest.where(council_ai_reservation_id: ids).to_a +
        CouncilIssueRequest.where(council_ai_reservation_id: ids).to_a +
        CouncilFormalRequest.where(council_ai_reservation_id: ids).to_a
      by_reservation = receipts.index_by(&:council_ai_reservation_id)
      groups = reservations.group_by { |reservation| stage_name(by_reservation[reservation.id]) }
      reserved = reservations.sum(&:reserved_microusd)
      authorization = if month.nil?
        "missing"
      elsif month.revoked_at
        "revoked"
      else
        "authorized"
      end

      { budget_month: date.beginning_of_month, authorization: authorization,
        live_action_policy: month&.live_actions.presence,
        limit_microusd: month&.limit_microusd, reserved_microusd: reserved,
        remaining_microusd: month ? [ month.limit_microusd - reserved, 0 ].max : 0,
        stages: groups.transform_values { |rows| summarize(rows, by_reservation) } }
    end

    def self.stage_name(receipt)
      case receipt
      when MinutesRequest then "minutes"
      when CampaignRequest then "campaign_#{receipt.campaign_extraction.purpose}"
      when CampaignActionRequest then "campaign_actions"
      when CouncilIssueRequest then "issue_updates"
      when CouncilFormalRequest then "formal_records"
      else "unknown"
      end
    end
    private_class_method :stage_name

    def self.summarize(reservations, receipts)
      costs = reservations.filter_map do |reservation|
        usage = receipts[reservation.id]&.usage
        next unless usage && %w[input_tokens output_tokens].all? { |key| usage[key].is_a?(Integer) && usage[key] >= 0 }

        RequestEstimate.ceiling_microusd(reservation.request_estimate.merge(
          "input_tokens" => usage.fetch("input_tokens"), "max_output_tokens" => usage.fetch("output_tokens")))
      end
      { requests: reservations.size, reserved_microusd: reservations.sum(&:reserved_microusd),
        unfinished_requests: reservations.count { |reservation| reservation.finished_at.nil? },
        requests_without_usage: reservations.size - costs.size,
        usage_at_reserved_rates_microusd: costs.sum }
    end
    private_class_method :summarize
  end
end
