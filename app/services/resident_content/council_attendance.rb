module ResidentContent
  class CouncilAttendance
    LABELS = { "present" => "Present", "absent" => "Absent", "excused" => "Excused", "unknown" => "Not recorded" }.freeze
    TYPES = { "" => "Regular", "regular" => "Regular", "special" => "Special",
      "organizational" => "Organizational", "work session" => "Work session" }.freeze

    def initialize(member, now: Time.current)
      @member = member
      @now = now
    end

    def call
      period = @member.council_service_periods.newest_first.first
      return unless period && period.started_on <= @now.to_date
      # A sourced start plus an explicitly current Council position supports an
      # ongoing window. A former member's unknown departure is not invented.
      return unless period.ended_on || @member.member_positions.current.exists?(kind: "city_council")
      council = Committee.find_by(name: "City Council")
      return unless council

      through = period.ended_on ? [ period.ended_on.end_of_day, @now ].min : @now
      meetings = council.meetings.where(starts_at: period.started_on.beginning_of_day..through)
        .includes(:meeting_documents, :meeting_summaries, :meeting_attendances).to_a
      rows = meetings.group_by(&:duplicate_identity_key).values.filter_map do |duplicates|
        meeting = Meeting.preferred_duplicate(duplicates)
        next if meeting.cancelled?
        type = meeting_type(meeting)
        next unless type

        statuses = duplicates.flat_map(&:meeting_attendances)
          .select { |record| record.member_id == @member.id && record.attendee_type == "voting_member" }
          .map(&:status).uniq
        { meeting: meeting, type: type, status: statuses.one? ? statuses.sole : "unknown" }
      end.sort_by { |row| [ row[:meeting].starts_at, row[:meeting].id ] }.reverse

      { committee_id: council.id, period: period, rows: rows,
        counts: LABELS.keys.to_h { |status| [ status, rows.count { |row| row[:status] == status } ] } }
    end

    private

    def meeting_type(meeting)
      # The imported meeting_type currently says "regular" even for listening
      # sessions. Use the explicit Council title for the supported meeting types.
      title = Meeting.normalized_body_name(meeting.body_name)
      return unless title.match?(/\Acity council(?: |\z)/)
      TYPES[title.delete_prefix("city council").strip]
    end
  end
end
