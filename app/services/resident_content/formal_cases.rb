module ResidentContent
  class FormalCases
    def initialize(member, period:)
      @member, @period = member, period
    end

    def call
      periods = @period.selected ? [ @period.selected ] : @period.selectable
      keys = periods.map(&:period_key)
      return [] if keys.empty?
      rows = CouncilFormalReview.where(status: "completed").includes(:council_formal_source).flat_map do |stage|
        source = stage.council_formal_source
        next [] unless (source.service_period_keys & keys).any? && stage.current?
        stage.data.fetch("events").filter_map do |event|
          next unless event.fetch("subjects").any? { |name| resolve_subject(name) == @member.id }
          { event: event, source: source }
        end
      end
      rows.group_by { |row| row.fetch(:source).case_key }.map do |_key, case_rows|
        timeline = case_rows.sort_by { |row| [ row.dig(:event, "occurred_on"), row[:source].published_on, row[:source].id ] }
          .uniq { |row| row.fetch(:event).except("subjects") }
        { title: timeline.first.fetch(:source).title, reference: timeline.first.fetch(:source).case_reference,
          reviewing_body: timeline.first.fetch(:source).reviewing_body, rows: timeline }
      end.sort_by { |record| record.fetch(:rows).last.dig(:event, "occurred_on") }.reverse
    end

    private

    def resolve_subject(name)
      @resolved ||= {}
      @resolved[name] ||= begin
        normalized = Member.normalize_name(name)
        ids = Member.where("LOWER(name) = LOWER(?)", normalized).pluck(:id) +
          MemberAlias.where("LOWER(name) = LOWER(?)", normalized).pluck(:member_id)
        ids.uniq.one? ? ids.first : nil
      end
    end
  end
end
