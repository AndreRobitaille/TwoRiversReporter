require "test_helper"

class CanonicalRosters::KnownCorrectionsTest < ActiveSupport::TestCase
  setup do
    @plan = Committee.create!(name: "Plan Commission")
    @utilities = Committee.create!(name: "Public Utilities Committee")
    @tracey = Member.create!(name: "Tracey Koach")
  end

  test "corrects Tracey Koach without inventing a staff membership" do
    plan_staff = CommitteeMembership.create!(
      committee: @plan, member: @tracey, role: "staff", source: "ai_extracted"
    )
    utilities_staff = CommitteeMembership.create!(
      committee: @utilities, member: @tracey, role: "staff", source: "ai_extracted",
      started_on: Date.new(2026, 7, 6)
    )
    mistaken = attendance(@plan, Date.new(2026, 4, 13), "non_voting_staff", "Also Present")
    attendance(@plan, Date.new(2026, 8, 10), "voting_member")

    CanonicalRosters::KnownCorrections.new(dry_run: false).call

    assert_equal "guest", mistaken.reload.attendee_type
    assert_nil mistaken.capacity
    assert_equal "member", plan_staff.reload.role
    assert_nil utilities_staff.reload.role
    assert_equal utilities_staff.started_on, utilities_staff.ended_on
  end

  test "corrects the known council attendee misclassification" do
    mark = Member.create!(name: "Mark Bittner")
    meeting = Meeting.create!(
      body_name: @plan.name,
      committee: @plan,
      starts_at: Time.zone.parse("2026-04-13 18:00"),
      detail_page_url: "https://example.com/plan-2026-04-13"
    )
    mistaken = MeetingAttendance.create!(
      meeting: meeting, member: mark, status: "present",
      attendee_type: "non_voting_staff", capacity: "Also Present"
    )

    CanonicalRosters::KnownCorrections.new(dry_run: false).call

    assert_equal "guest", mistaken.reload.attendee_type
  end

  test "dry run rolls corrections back" do
    mistaken = attendance(@plan, Date.new(2026, 4, 13), "non_voting_staff", "Also Present")

    result = CanonicalRosters::KnownCorrections.new(dry_run: true).call

    assert result.changed?
    assert_equal "non_voting_staff", mistaken.reload.attendee_type
  end

  private

  def attendance(committee, date, attendee_type, capacity = nil)
    meeting = Meeting.create!(
      body_name: committee.name,
      committee: committee,
      starts_at: date.in_time_zone.change(hour: 18),
      detail_page_url: "https://example.com/#{committee.id}-#{date}"
    )
    MeetingAttendance.create!(
      meeting: meeting, member: @tracey, status: "present",
      attendee_type: attendee_type, capacity: capacity
    )
  end
end
