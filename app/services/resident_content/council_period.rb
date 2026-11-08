module ResidentContent
  class CouncilPeriod
    attr_reader :periods, :selectable, :selected

    def initialize(member, key: nil, now: Time.current)
      @now = now
      @periods = member.council_service_periods.newest_first
        .includes(start_source_version: { file_attachment: :blob }, end_source_version: { file_attachment: :blob }).to_a
      current = member.member_positions.current.exists?(kind: "city_council")
      @selectable = periods.select do |period|
        period.started_on <= now.to_date && (period.ended_on || (period == periods.first && current))
      end
      @selected = if key == "all"
        nil
      elsif key.present?
        selectable.find { |period| period.period_key == key } || raise(ActiveRecord::RecordNotFound)
      else
        selectable.first
      end
    end

    def key
      selected&.period_key || "all"
    end

    def range
      return unless selected

      through = selected.ended_on ? [ selected.ended_on.end_of_day, @now ].min : @now
      selected.started_on.beginning_of_day..through
    end
  end
end
