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
end
