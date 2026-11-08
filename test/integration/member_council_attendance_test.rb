require "test_helper"
require_relative "../support/council_attendance_setup"

class MemberCouncilAttendanceTest < ActionDispatch::IntegrationTest
  include CouncilAttendanceSetup

  setup do
    travel_to Time.zone.local(2026, 11, 8, 12)
    setup_council_attendance
  end

  teardown { travel_back }

  test "known Council inventory distinguishes absence from missing roll calls and excludes ineligible meetings" do
    included = [
      council_meeting("2024-04-16", attendance: "present"),
      council_meeting("2024-05-01", title: "City Council Special Meeting", attendance: "absent"),
      council_meeting("2024-05-02", title: "City Council Work Session", attendance: "excused"),
      council_meeting("2024-05-03", title: "City Council Organizational Meeting"),
      council_meeting("2024-05-04", attendance: "present", attendee_type: "guest"),
      council_meeting("2024-05-05", attendance: "present", attendee_type: "non_voting_staff")
    ]
    excluded = [
      council_meeting("2024-04-15", attendance: "present"),
      council_meeting("2026-11-09", attendance: "present"),
      council_meeting("2024-05-10", status: "cancelled"),
      council_meeting("2024-05-11", title: "City Council Work Session- CANCELED"),
      council_meeting("2024-05-12", title: "City Council - No quorum"),
      council_meeting("2024-05-13", title: "City Council Listening Session")
    ]
    other = Committee.create!(name: "Public Works", slug: "public-works")
    council_meeting("2024-05-14", committee: other, attendance: "present")

    Ai::OpenAiService.stub(:new, ->(*) { flunk "Attendance uses recorded data, not AI" }) do
      get member_path(@member)
      assert_response :success
      assert_counts(present: 1, absent: 1, excused: 1, unknown: 3)
      assert_select "#council-attendance summary", text: "View 6 Council meetings"
      assert_select "#council-attendance", text: /Available records: Apr 16, 2024 – May 5, 2024/
      assert_select "#council-attendance", text: /%|avg/, count: 0
      assert_equal included.map(&:id).sort, meeting_ids.sort
      excluded.each { |meeting| assert_select "#council-attendance a[href=?]", meeting_path(meeting), count: 0 }
      assert_select ".member-attendance-committee", text: "Public Works"
      assert_select ".member-attendance-stat", text: "1 present"
      assert_select ".member-attendance-committee", text: "City Council", count: 0
    end
  end

  test "later roll calls cancellations and service corrections change subsequent reads without changing votes" do
    first = council_meeting("2024-04-16", attendance: "present")
    missing = council_meeting("2024-04-17")
    excused = council_meeting("2024-04-18", attendance: "excused")
    vote = first.motions.create!(description: "Approve engineering contract", outcome: "passed")
      .votes.create!(member: @member, value: "yes")

    Ai::OpenAiService.stub(:new, ->(*) { flunk "Attendance updates do not generate analysis" }) do
      get member_path(@member)
      assert_counts(present: 1, absent: 0, excused: 1, unknown: 1)
      missing.meeting_attendances.create!(member: @member, status: "present", attendee_type: "voting_member")
      get member_path(@member)
      assert_counts(present: 2, absent: 0, excused: 1, unknown: 0)

      excused.update!(body_name: "City Council - CANCELED")
      @period.update!(started_on: "2024-04-17")
      get member_path(@member)
      assert_counts(present: 1, absent: 0, excused: 0, unknown: 0)
      assert_equal [ missing.id ], meeting_ids
      assert_equal "yes", vote.reload.value
      assert_equal first.id, vote.motion.meeting_id
    end
  end

  test "duplicate inventory counts once and conflicting attendance remains unresolved" do
    original = council_meeting("2024-04-16", attendance: "present")
    copy = council_meeting("2024-04-16", attendance: "present")
    get member_path(@member)
    assert_counts(present: 1, absent: 0, excused: 0, unknown: 0)
    assert_equal [ original.id ], meeting_ids

    copy.meeting_attendances.sole.update!(status: "absent")
    get member_path(@member)
    assert_counts(present: 0, absent: 0, excused: 0, unknown: 1)
  end

  test "a documented departure bounds the window while an unknown former end only shows recorded rows" do
    @position.update!(ended_on: "2024-05-01")
    council_meeting("2024-04-30", attendance: "present")
    departure = council_meeting("2024-05-01")
    council_meeting("2024-05-02")
    get member_path(@member)
    assert_select "#council-attendance", count: 0
    assert_select ".member-attendance-stat", text: "1 present"

    @period.update!(ended_on: "2024-05-01", end_source_version: @source, end_page: 6)
    get member_path(@member)
    assert_counts(present: 1, absent: 0, excused: 0, unknown: 1)
    assert_includes meeting_ids, departure.id
    assert_select "#council-attendance", text: /Ended May 1, 2024/
  end

  test "current role alone does not establish a service window and an empty inventory makes no counts" do
    get member_path(@member)
    assert_select "#council-attendance", text: /No Council meeting records/
    assert_select ".member-attendance-counts", count: 0

    @period.destroy!
    council_meeting("2024-05-01", attendance: "present")
    get member_path(@member)
    assert_select "#council-attendance", count: 0
    assert_select ".member-attendance-stat", text: "1 present"
  end

  test "attendance stays public in gated mode while the existing voting record is withheld" do
    meeting = council_meeting("2024-04-16", attendance: "present")
    meeting.motions.create!(description: "Approve distinctive engineering contract", outcome: "passed")
      .votes.create!(member: @member, value: "yes")
    get member_path(@member)
    assert_counts(present: 1, absent: 0, excused: 0, unknown: 0)
    assert_select ".member-vote-motion", text: /distinctive engineering contract/

    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    get member_path(@member)
    assert_counts(present: 1, absent: 0, excused: 0, unknown: 0)
    assert_equal [ meeting.id ], meeting_ids
    assert_select ".member-vote-motion", count: 0
    refute_includes response.body, "distinctive engineering contract"
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end

  private

  def assert_counts(**counts)
    counts.each do |status, count|
      assert_select "#council-attendance [data-attendance-status='#{status}'] dd", text: count.to_s, count: 1
    end
  end

  def meeting_ids
    css_select("#council-attendance li a").map { |link| link["href"].split("/").last.to_i }
  end
end
