require_relative "council_attendance_setup"

module CouncilPeriodSetup
  include CouncilAttendanceSetup

  def setup_council_periods
    setup_council_attendance
    @old_period = @member.council_service_periods.create!(period_key: "2021-election", started_on: "2021-04-20",
      ended_on: "2024-04-15", start_source_version: @source, start_page: 1, end_source_version: @source, end_page: 2)
    @old_meeting = council_meeting("2023-06-05", attendance: "absent")
    @current_meeting = council_meeting("2024-04-16", attendance: "present")
    topic = Topic.create!(name: "Neighborhood infrastructure", status: "approved", resident_impact_score: 4)
    [ [ @old_meeting, "Earlier" ], [ @current_meeting, "Current" ] ].each do |meeting, label|
      item = meeting.agenda_items.create!(title: "#{label} improvements")
      item.agenda_item_topics.create!(topic: topic)
      26.times do |index|
        meeting.motions.create!(description: "#{label} road project #{index}", outcome: "passed", agenda_item: item)
          .votes.create!(member: @member, value: "yes")
      end
    end
  end
end
