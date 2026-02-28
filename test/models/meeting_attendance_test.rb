require "test_helper"

class MeetingAttendanceTest < ActiveSupport::TestCase
  setup do
    @meeting = Meeting.create!(
      body_name: "City Council",
      starts_at: Time.current,
      detail_page_url: "http://example.com/attendance-test"
    )
    @member = Member.create!(name: "Jane Doe")
  end

  test "valid attendance saves" do
    attendance = MeetingAttendance.new(
      meeting: @meeting, member: @member,
      status: "present", attendee_type: "voting_member"
    )
    assert attendance.save
  end

  test "status is required" do
    attendance = MeetingAttendance.new(
      meeting: @meeting, member: @member, attendee_type: "voting_member"
    )
    assert_not attendance.valid?
  end

  test "status validates inclusion" do
    attendance = MeetingAttendance.new(
      meeting: @meeting, member: @member,
      status: "unknown", attendee_type: "voting_member"
    )
    assert_not attendance.valid?
  end

  test "attendee_type is required" do
    attendance = MeetingAttendance.new(
      meeting: @meeting, member: @member, status: "present"
    )
    assert_not attendance.valid?
  end

  test "attendee_type validates inclusion" do
    attendance = MeetingAttendance.new(
      meeting: @meeting, member: @member,
      status: "present", attendee_type: "spectator"
    )
    assert_not attendance.valid?
  end

  test "capacity is optional" do
    attendance = MeetingAttendance.new(
      meeting: @meeting, member: @member,
      status: "present", attendee_type: "non_voting_staff",
      capacity: "City Manager"
    )
    assert attendance.valid?
  end

  test "unique constraint on meeting and member" do
    MeetingAttendance.create!(
      meeting: @meeting, member: @member,
      status: "present", attendee_type: "voting_member"
    )
    duplicate = MeetingAttendance.new(
      meeting: @meeting, member: @member,
      status: "absent", attendee_type: "voting_member"
    )
    assert_not duplicate.save
  end

  test "present scope" do
    present = MeetingAttendance.create!(
      meeting: @meeting, member: @member,
      status: "present", attendee_type: "voting_member"
    )
    absent = MeetingAttendance.create!(
      meeting: @meeting, member: Member.create!(name: "Other"),
      status: "absent", attendee_type: "voting_member"
    )

    assert_includes MeetingAttendance.present, present
    assert_not_includes MeetingAttendance.present, absent
  end

  test "voting_members scope" do
    voting = MeetingAttendance.create!(
      meeting: @meeting, member: @member,
      status: "present", attendee_type: "voting_member"
    )
    staff = MeetingAttendance.create!(
      meeting: @meeting, member: Member.create!(name: "Staff Person"),
      status: "present", attendee_type: "non_voting_staff"
    )

    assert_includes MeetingAttendance.voting_members, voting
    assert_not_includes MeetingAttendance.voting_members, staff
  end

  test "for_committee scope filters by committee" do
    committee = Committee.create!(name: "Plan Commission")
    @meeting.update!(committee: committee)

    attendance = MeetingAttendance.create!(
      meeting: @meeting, member: @member,
      status: "present", attendee_type: "voting_member"
    )

    other_meeting = Meeting.create!(
      body_name: "Other",
      starts_at: Time.current,
      detail_page_url: "http://example.com/attendance-test-other"
    )
    other = MeetingAttendance.create!(
      meeting: other_meeting, member: Member.create!(name: "Other"),
      status: "present", attendee_type: "voting_member"
    )

    results = MeetingAttendance.for_committee(committee.id)
    assert_includes results, attendance
    assert_not_includes results, other
  end

  test "meeting has_many meeting_attendances" do
    assert_respond_to @meeting, :meeting_attendances
  end

  test "member has_many meeting_attendances" do
    assert_respond_to @member, :meeting_attendances
  end

  test "destroying meeting destroys attendances" do
    MeetingAttendance.create!(
      meeting: @meeting, member: @member,
      status: "present", attendee_type: "voting_member"
    )
    assert_difference("MeetingAttendance.count", -1) do
      @meeting.destroy!
    end
  end

  test "destroying member destroys attendances" do
    MeetingAttendance.create!(
      meeting: @meeting, member: @member,
      status: "present", attendee_type: "voting_member"
    )
    assert_difference("MeetingAttendance.count", -1) do
      @member.destroy!
    end
  end
end
