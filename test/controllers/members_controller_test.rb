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

  test "show displays per-committee attendance" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 3.days.ago, status: "minutes_posted",
      detail_page_url: "http://example.com/att-test",
      committee: @council
    )
    MeetingAttendance.create!(
      meeting: meeting, member: @member,
      status: "present", attendee_type: "voting_member"
    )

    get member_url(@member)
    assert_response :success

    assert_select ".member-attendance-row", minimum: 1
    assert_select ".member-attendance-committee", text: /City Council/
    assert_select ".member-attendance-stat", text: /100%/
  end

  test "show omits attendance section when no data" do
    get member_url(@member)
    assert_response :success

    assert_select ".member-attendance-list", count: 0
  end

  test "show groups votes by topic for high-impact topics" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 3.days.ago, status: "minutes_posted",
      detail_page_url: "http://example.com/vote-group-test"
    )
    topic = Topic.create!(
      name: "important topic", status: "approved",
      lifecycle_status: "active", resident_impact_score: 4,
      last_activity_at: 2.days.ago
    )
    item = AgendaItem.create!(meeting: meeting, title: "Important Item")
    AgendaItemTopic.create!(topic: topic, agenda_item: item)
    motion = Motion.create!(
      meeting: meeting, agenda_item: item,
      description: "Motion to approve important thing",
      outcome: "passed"
    )
    Vote.create!(motion: motion, member: @member, value: "yes")

    get member_url(@member)
    assert_response :success

    assert_select ".member-topic-group", minimum: 1
    assert_select ".member-topic-name", text: /important topic/
  end

  test "show includes topics where member dissented" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 3.days.ago, status: "minutes_posted",
      detail_page_url: "http://example.com/dissent-test"
    )
    topic = Topic.create!(
      name: "low impact but dissent", status: "approved",
      lifecycle_status: "active", resident_impact_score: 1,
      last_activity_at: 2.days.ago
    )
    item = AgendaItem.create!(meeting: meeting, title: "Dissent Item")
    AgendaItemTopic.create!(topic: topic, agenda_item: item)
    motion = Motion.create!(
      meeting: meeting, agenda_item: item,
      description: "Motion that was controversial",
      outcome: "passed"
    )
    # Member voted no (minority)
    Vote.create!(motion: motion, member: @member, value: "no")
    # Others voted yes (majority)
    other1 = Member.create!(name: "Voter One")
    other2 = Member.create!(name: "Voter Two")
    Vote.create!(motion: motion, member: other1, value: "yes")
    Vote.create!(motion: motion, member: other2, value: "yes")

    get member_url(@member)
    assert_response :success

    assert_select ".member-topic-name", text: /low impact but dissent/
  end

  test "show puts unlinked votes in other votes section" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 3.days.ago, status: "minutes_posted",
      detail_page_url: "http://example.com/other-test"
    )
    motion = Motion.create!(
      meeting: meeting,
      description: "Motion to approve the contract with Strand Associates for engineering services",
      outcome: "passed"
    )
    Vote.create!(motion: motion, member: @member, value: "yes")

    get member_url(@member)
    assert_response :success

    assert_select ".member-other-votes summary", text: /Other Votes/
  end

  test "show filters procedural votes from other votes" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 3.days.ago, status: "minutes_posted",
      detail_page_url: "http://example.com/procedural-test"
    )
    procedural = Motion.create!(
      meeting: meeting, description: "Motion to adjourn", outcome: "passed"
    )
    Vote.create!(motion: procedural, member: @member, value: "yes")
    substantive = Motion.create!(
      meeting: meeting, description: "Motion to approve engineering contract", outcome: "passed"
    )
    Vote.create!(motion: substantive, member: @member, value: "yes")

    get member_url(@member)
    assert_response :success

    # Substantive vote should appear, procedural should not
    assert_select ".member-other-votes .member-vote-motion", text: /engineering contract/
    assert_select ".member-other-votes .member-vote-motion", text: /adjourn/, count: 0
  end

  test "show displays vote split" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 3.days.ago, status: "minutes_posted",
      detail_page_url: "http://example.com/split-test"
    )
    topic = Topic.create!(
      name: "split vote topic", status: "approved",
      lifecycle_status: "active", resident_impact_score: 4,
      last_activity_at: 2.days.ago
    )
    item = AgendaItem.create!(meeting: meeting, title: "Split Item")
    AgendaItemTopic.create!(topic: topic, agenda_item: item)
    motion = Motion.create!(
      meeting: meeting, agenda_item: item,
      description: "Motion with split vote",
      outcome: "passed"
    )
    Vote.create!(motion: motion, member: @member, value: "yes")
    other = Member.create!(name: "Dissenter")
    Vote.create!(motion: motion, member: other, value: "no")

    get member_url(@member)
    assert_response :success

    assert_select ".member-vote-split", text: /1-1/
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
