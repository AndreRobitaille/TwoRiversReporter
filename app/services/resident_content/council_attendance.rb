module ResidentContent
  class CouncilAttendance
    LABELS = { "present" => "Present", "absent" => "Absent", "excused" => "Excused", "unknown" => "Not recorded" }.freeze
    TYPES = { "" => "Regular", "regular" => "Regular", "special" => "Special",
      "organizational" => "Organizational", "reorganizational" => "Organizational", "work session" => "Work session" }.freeze

    def initialize(member, period: member.council_service_periods.newest_first.first, now: Time.current)
      @member = member
      @period = period
      @now = now
    end

    def call
      council = eligible_council
      return unless council

      groups = meeting_groups(council)
      statuses_by_meeting = @member.meeting_attendances.voting_members.where(meeting_id: groups.flatten.map(&:id))
        .pluck(:meeting_id, :status).group_by(&:first)
      rows = groups.map do |duplicates|
        meeting = duplicates.one? ? duplicates.first : Meeting.preferred_duplicate(duplicates)
        type = meeting_type(meeting)
        statuses = duplicates.flat_map { |copy| statuses_by_meeting.fetch(copy.id, []).map(&:last) }.uniq
        { meeting: meeting, meeting_ids: duplicates.map(&:id), type: type, status: statuses.one? ? statuses.sole : "unknown" }
      end.sort_by { |row| [ row[:meeting].starts_at, row[:meeting].id ] }.reverse

      { committee_id: council.id, period: @period, rows: rows, meeting_ids: rows.flat_map { |row| row.fetch(:meeting_ids) },
        counts: LABELS.keys.to_h { |status| [ status, rows.count { |row| row[:status] == status } ] } }
    end

    # A vote lookup only needs the eligible meeting IDs, including older copies.
    def meeting_ids
      council = eligible_council
      council ? meeting_groups(council).flatten.map(&:id) : []
    end

    private

    def eligible_council
      return unless @period && @period.started_on <= @now.to_date
      return unless @period.ended_on || @member.member_positions.current.exists?(kind: "city_council")
      Committee.find_by(name: "City Council")
    end

    def meeting_groups(council)
      through = @period.ended_on ? [ @period.ended_on.end_of_day, @now ].min : @now
      meetings = Meeting.where(committee_id: [ council.id, nil ], starts_at: @period.started_on.beginning_of_day..through)
      # An explicit cancellation wins for the whole set of duplicate notices.
      meetings.select { |meeting| meeting_type(meeting) }.group_by(&:starts_at).values.reject { |copies| copies.any?(&:cancelled?) }
    end

    def meeting_type(meeting)
      # The imported meeting_type currently says "regular" even for listening
      # sessions. Use the explicit Council title for the supported meeting types.
      title = Meeting.normalized_body_name(meeting.body_name)
      title = "city council special" if title == "special city council"
      return unless title.match?(/\Acity council(?: |\z)/)
      TYPES[title.delete_prefix("city council").strip]
    end
  end
end
