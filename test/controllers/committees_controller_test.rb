require "test_helper"

class CommitteesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @council = Committee.create!(
      name: "City Council",
      slug: "city-council",
      committee_type: "city",
      status: "active",
      description: "The legislative body of the city."
    )
    @plan_commission = Committee.create!(
      name: "Plan Commission",
      slug: "plan-commission",
      committee_type: "city",
      status: "active",
      description: "Reviews zoning changes."
    )
    @nonprofit = Committee.create!(
      name: "Explore Two Rivers",
      slug: "explore-two-rivers",
      committee_type: "tax_funded_nonprofit",
      status: "active"
    )
    @dormant_empty = Committee.create!(
      name: "Old Board",
      slug: "old-board",
      committee_type: "city",
      status: "dormant"
    )

    @council_member = Member.create!(name: "Jane Smith")
    CommitteeMembership.create!(
      committee: @council,
      member: @council_member,
      role: "chair",
      source: "admin_manual"
    )
    @plan_member = Member.create!(name: "Bob Jones")
    CommitteeMembership.create!(
      committee: @plan_commission,
      member: @plan_member,
      source: "admin_manual"
    )
  end

  test "index returns success" do
    get committees_url
    assert_response :success
  end

  test "index shows committees grouped by type" do
    get committees_url
    assert_response :success
    assert_select ".committees-type-label", text: /City Government/
  end

  test "index shows committee names linking to show pages" do
    get committees_url
    assert_response :success
    assert_select "a[href=?]", committee_path(@council.slug), text: /City Council/
  end

  test "index shows member counts" do
    get committees_url
    assert_response :success
    assert_select ".committees-member-count", minimum: 2
  end

  test "index excludes dissolved committees" do
    dissolved = Committee.create!(
      name: "Dissolved Board", slug: "dissolved-board",
      committee_type: "city", status: "dissolved"
    )
    get committees_url
    assert_response :success
    assert_select "a[href=?]", committee_path(dissolved.slug), count: 0
  end

  test "members index redirects to committees" do
    get "/members"
    assert_response :redirect
    assert_redirected_to committees_path
  end

  test "show returns success" do
    get committee_url(@council.slug)
    assert_response :success
  end

  test "show displays committee name" do
    get committee_url(@council.slug)
    assert_response :success
    assert_select ".committee-name", text: /City Council/
  end

  test "show displays current members sorted by role" do
    vice_chair = Member.create!(name: "Alice Vice")
    CommitteeMembership.create!(
      committee: @council, member: vice_chair,
      role: "vice_chair", source: "admin_manual"
    )
    regular = Member.create!(name: "Charlie Regular")
    CommitteeMembership.create!(
      committee: @council, member: regular,
      source: "admin_manual"
    )

    get committee_url(@council.slug)
    assert_response :success

    # Chair should appear first (Jane Smith), then vice chair (Alice Vice), then regular (Charlie Regular)
    names = css_select(".committee-member-name").map { |n| n.text.strip }
    assert_equal "Jane Smith", names.first
    assert_equal "Alice Vice", names.second
  end

  test "show excludes ended memberships" do
    former = Member.create!(name: "Former Member")
    CommitteeMembership.create!(
      committee: @council, member: former,
      source: "admin_manual", ended_on: 1.month.ago
    )

    get committee_url(@council.slug)
    assert_response :success

    names = css_select(".committee-member-name").map { |n| n.text.strip }
    refute_includes names, "Former Member"
  end

  test "show displays recent topic activity" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 3.days.ago, status: "minutes_posted",
      detail_page_url: "http://example.com/show-test",
      committee: @council
    )
    topic = Topic.create!(
      name: "test topic for show", status: "approved",
      lifecycle_status: "active", last_activity_at: 2.days.ago
    )
    item = AgendaItem.create!(meeting: meeting, title: "Test Item")
    AgendaItemTopic.create!(topic: topic, agenda_item: item)

    get committee_url(@council.slug)
    assert_response :success

    assert_select ".committee-activity a", text: /Test Topic For Show/
  end

  test "show renders description with links" do
    @council.update!(description: 'Established under [WI Stats](https://example.com).')
    get committee_url(@council.slug)
    assert_response :success

    assert_select ".committee-description a[href='https://example.com']", text: "WI Stats"
  end
end
