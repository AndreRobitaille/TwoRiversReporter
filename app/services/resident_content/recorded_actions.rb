module ResidentContent
  # Exact known names/aliases or an unambiguous surname link a source speaker.
  # Never create a person or infer a Council role while reading a profile.
  class RecordedActions
    def initialize(member, period:)
      @member, @period = member, period
    end

    def call
      periods = @period.selected ? [ @period.selected ] : @period.selectable
      return [] if periods.empty?
      ranges = periods.map { |period| period.started_on..(period.ended_on || Date.current) }
      start_date = ranges.map(&:begin).min
      end_date = ranges.map(&:end).max
      stages = CouncilIssueReview.where(status: "completed").where(
        "EXISTS (SELECT 1 FROM jsonb_array_elements(council_issue_reviews.data->'actions') action " \
        "WHERE action->>'occurred_on' BETWEEN ? AND ?)", start_date.iso8601, end_date.iso8601)
      rows = stages.includes(meeting_document: :meeting).flat_map do |stage|
        actions = stage.data.fetch("actions", []).select do |action|
          date = Date.iso8601(action.fetch("occurred_on"))
          ranges.any? { |range| range.cover?(date) } && resolve_speaker(action.fetch("speaker")) == @member.id
        end
        next [] if actions.empty?
        citation = stage.current_citation
        next [] unless citation

        topics = Topic.approved.where(id: actions.flat_map { |action| action.fetch("topic_ids") }).index_by(&:id)
        actions.filter_map do |action|
          related = action.fetch("topic_ids").filter_map { |id| topics[id] }
          next if related.empty?
          { evidence: action, citation: citation, meeting: stage.meeting_document.meeting, topics: related }
        end
      end
      rows.uniq { |row| row.fetch(:evidence).except("agenda_item_id", "topic_ids") }
        .sort_by { |row| [ row.dig(:evidence, "occurred_on"), row.fetch(:meeting).id ] }.reverse
    end

    private

    def resolve_speaker(speaker)
      @people ||= Member.includes(:member_aliases).to_a
      normalized = Member.normalize_name(speaker).downcase
      exact = @people.select do |person|
        ([ person.name ] + person.member_aliases.map(&:name)).any? { |name| name.downcase == normalized }
      end
      return exact.sole.id if exact.one?
      return if exact.any? || normalized.split.size != 1

      candidates = @people.select { |person| person.name.split.last&.downcase == normalized }
      candidates.sole.id if candidates.one?
    end
  end
end
