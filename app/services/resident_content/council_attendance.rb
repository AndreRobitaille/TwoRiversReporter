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
      period = @period
      return unless period && period.started_on <= @now.to_date
      # A sourced start plus an explicitly current Council position supports an
      # ongoing window. A former member's unknown departure is not invented.
      return unless period.ended_on || @member.member_positions.current.exists?(kind: "city_council")
      council = Committee.find_by(name: "City Council")
      return unless council

      through = period.ended_on ? [ period.ended_on.end_of_day, @now ].min : @now
      meetings = Meeting.where(committee_id: [ council.id, nil ], starts_at: period.started_on.beginning_of_day..through)
        .includes(:meeting_documents, :meeting_summaries, :meeting_attendances).to_a
        .select { |meeting| meeting_type(meeting) }
      # Explicit Council titles can establish the body even when an older import
      # lacks its committee link. Group those aliases with the linked inventory.
      rows = meetings.group_by(&:starts_at).values.filter_map do |duplicates|
        meeting = Meeting.preferred_duplicate(duplicates)
        next if meeting.cancelled?
        type = meeting_type(meeting)
        next unless type

        records = duplicates.flat_map(&:meeting_attendances)
          .select { |record| record.member_id == @member.id && record.attendee_type == "voting_member" }
        statuses = records.map(&:status).uniq
        notes = records.select { |record| record.meeting_id == meeting.id }.flat_map(&:participation_notes).uniq
        { meeting: meeting, meeting_ids: duplicates.map(&:id), type: type,
          status: statuses.one? ? statuses.sole : "unknown", participation_notes: notes }
      end.sort_by { |row| [ row[:meeting].starts_at, row[:meeting].id ] }.reverse

      { committee_id: council.id, period: period, rows: rows, meeting_ids: rows.flat_map { |row| row.fetch(:meeting_ids) },
        counts: LABELS.keys.to_h { |status| [ status, rows.count { |row| row[:status] == status } ] } }
    end

    private

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
