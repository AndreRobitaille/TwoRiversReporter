require "test_helper"
require_relative "../support/council_period_setup"

class MemberCouncilPeriodTest < ActionDispatch::IntegrationTest
  include CouncilPeriodSetup

  setup { setup_council_periods }

  test "selected service period scopes attendance votes and subsequent paginated reads without AI" do
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Selecting a period must use saved records" }) do
      get member_path(@member, votes: "all")
      assert_response :success
      assert_select "select[name=term] option[selected][value=?]", @period.period_key
      assert_select "#council-attendance [data-attendance-status=present] dd", text: "1"
      assert_select ".member-recorded-motion", count: 25, text: /Current road/
      refute_includes response.body, "Earlier road project"

      get member_path(@member, term: @old_period.period_key, votes: "all")
      assert_select "#council-attendance [data-attendance-status=absent] dd", text: "1"
      assert_select ".member-recorded-motion", count: 25, text: /Earlier road/
      refute_includes response.body, "Current road project"
      assert_select ".member-article-header .badge", text: "Current: City Council Member"
      assert_select ".member-vote-pages a[href*='term=2021-election'][href*='page=2']"
      assert_select ".member-vote-views a[href*='term=2021-election']", count: 2

      get member_path(@member, term: @old_period.period_key, votes: "all", page: 2)
      assert_select ".member-recorded-motion", count: 1, text: "Earlier road project 0"
      @old_period.update!(ended_on: "2023-06-04")
      get member_path(@member, term: @old_period.period_key, votes: "all")
      assert_select ".member-recorded-motion", count: 0
      assert_select "#council-attendance", text: /No Council meeting records/
      assert_select ".member-recorded-empty", text: /No recorded Council votes for this service period/
    end
  end

  test "all records remains available while a selected period excludes other committees and cancellations" do
    other = Committee.create!(name: "Public Works", slug: "period-public-works")
    outside = council_meeting("2024-04-17", committee: other, attendance: "present")
    cancelled = council_meeting("2024-04-18", status: "cancelled")
    [ outside, cancelled ].each do |meeting|
      meeting.motions.create!(description: "Outside selected Council inventory", outcome: "passed")
        .votes.create!(member: @member, value: "yes")
    end
    get member_path(@member, term: @period.period_key, votes: "all")
    refute_includes response.body, "Outside selected Council inventory"
    assert_select ".member-attendance-committee", text: "Public Works"
    get member_path(@member, term: @old_period.period_key, votes: "all")
    assert_select ".member-attendance-committee", text: "Public Works", count: 0

    get member_path(@member, term: "all", votes: "all")
    assert_select "select[name=term] option[selected][value=all]"
    assert_select ".member-recorded-motion", text: "Outside selected Council inventory", count: 2
    assert_select ".member-vote-views a[href*='term=all']", count: 2
    assert_select ".member-attendance-committee", text: "City Council"
    assert_select "#council-attendance", count: 0
  end

  test "unknown or another members period cannot silently broaden the selected record" do
    get member_path(@member, term: "not-this-members-term")
    assert_response :not_found
    @old_period.update!(ended_on: nil, end_source_version: nil, end_page: nil)
    get member_path(@member, term: @old_period.period_key)
    assert_response :not_found
    get member_path(@member)
    assert_select "select[name=term] option[value=?]", @old_period.period_key, count: 0
  end

  test "explicit special and reorganizational titles include unlinked Council imports once" do
    special = council_meeting("2024-05-01", title: "Special City Council Meeting", committee: nil, attendance: "present")
    organizational = council_meeting("2024-05-02", title: "City Council Reorganizational Meeting", committee: nil, attendance: "present")
    council_meeting("2024-05-01", title: "City Council Special Meeting", attendance: "present")
    [ special, organizational ].each do |meeting|
      meeting.motions.create!(description: "Actual Council title variant", outcome: "passed")
        .votes.create!(member: @member, value: "yes")
    end
    get member_path(@member, votes: "all")
    assert_select "#council-attendance [data-attendance-status=present] dd", text: "3"
    assert_select "#council-attendance li", count: 3
    assert_select "#council-attendance li", text: /May 1, 2024 · Special/, count: 1
    assert_select "#council-attendance li", text: /May 2, 2024 · Organizational/, count: 1
    assert_select ".member-recorded-motion", text: "Actual Council title variant", count: 2
  end

  test "selected public attendance does not expose the gated vote record" do
    get member_path(@member, term: @old_period.period_key, votes: "all")
    assert_select ".member-recorded-motion", text: /Earlier road/, count: 25
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    get member_path(@member, term: @old_period.period_key, votes: "all")
    assert_select "#council-attendance [data-attendance-status=absent] dd", text: "1"
    refute_includes response.body, "Earlier road project"
    assert_select ".member-vote-pages, .member-recorded-motion", count: 0
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end
end
