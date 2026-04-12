require "test_helper"

class MembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @council = Committee.create!(
      name: "City Council", slug: "city-council",
      committee_type: "city", status: "active"
    )
    @public_works = Committee.create!(
      name: "Public Works Committee", slug: "public-works",
      committee_type: "city", status: "active"
    )
    @member = Member.create!(name: "Doug Brandt")
    CommitteeMembership.create!(committee: @council, member: @member, source: "admin_manual")
    CommitteeMembership.create!(committee: @public_works, member: @member, source: "admin_manual")
  end

  test "show returns success" do
    get member_url(@member)
    assert_response :success
  end

  test "show displays committee memberships" do
    get member_url(@member)
    assert_response :success

    assert_select "a[href=?]", committee_path(@council.slug), text: /City Council/
    assert_select "a[href=?]", committee_path(@public_works.slug), text: /Public Works/
  end

  test "show lists City Council first in committees" do
    get member_url(@member)
    assert_response :success

    committee_names = css_select(".member-committee-name").map { |n| n.text.strip }
    assert_equal "City Council", committee_names.first
  end

  test "show displays attendance when data exists" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 3.days.ago, status: "minutes_posted",
      detail_page_url: "http://example.com/att-test"
    )
    MeetingAttendance.create!(
      meeting: meeting, member: @member,
      status: "present", attendee_type: "voting_member"
    )

    get member_url(@member)
    assert_response :success

    assert_select ".member-attendance", text: /Present at 1 of 1/
  end

  test "show omits attendance section when no data" do
    get member_url(@member)
    assert_response :success

    assert_select ".member-attendance", count: 0
  end

  test "show excludes ended memberships" do
    old_committee = Committee.create!(
      name: "Old Committee", slug: "old-committee",
      committee_type: "city", status: "active"
    )
    CommitteeMembership.create!(
      committee: old_committee, member: @member,
      source: "admin_manual", ended_on: 1.month.ago
    )

    get member_url(@member)
    assert_response :success

    committee_names = css_select(".member-committee-name").map { |n| n.text.strip }
    refute_includes committee_names, "Old Committee"
  end
end
