require_relative "council_service_sources"

module CouncilAttendanceSetup
  include CouncilServiceSources

  def setup_council_attendance
    @member = Member.create!(name: "Jordan Attendance")
    @council = Committee.create!(name: "City Council", slug: "city-council")
    @source = service_source
    @period = CouncilServicePeriod.record_starts!(period_key: "2024-election", source_version: @source, page: 5,
      entries: [ { member_id: @member.id, started_on: "2024-04-16" } ]).sole
    @position = @member.member_positions.create!(kind: "city_council", title: "City Council Member",
      source: "official_website", source_url: "https://example.test/roster", verified_at: Time.current)
  end

  def council_meeting(date, title: "City Council", attendance: nil, attendee_type: "voting_member", **attributes)
    meeting = Meeting.create!(body_name: title, committee: @council, meeting_type: "regular",
      starts_at: date.in_time_zone.change(hour: 18), detail_page_url: "https://example.test/#{SecureRandom.hex(4)}",
      **attributes)
    meeting.meeting_attendances.create!(member: @member, status: attendance, attendee_type: attendee_type) if attendance
    meeting
  end
end
