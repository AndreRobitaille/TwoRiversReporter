require "test_helper"
require_relative "../support/campaign_activity_scenario"

class MemberCampaignActivityTest < ActionDispatch::IntegrationTest
  include CampaignActivityScenario

  setup { setup_campaign_activity }

  test "later accepted votes update the related issue record with member and Council results kept separate" do
    older = activity_vote(date: Date.new(2025, 6, 2), description: "Authorize water line funding; construction is not complete")
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Member reads must reuse existing facts" }) do
      get member_path(@jordan)
      assert_response :success
      assert_select "[data-campaign-activity]", count: 1
      assert_select "[data-campaign-vote]", count: 1
      assert_select "[data-campaign-vote='#{older.id}']", text: /Jordan Example: No.*Council: Passed.*2-1/m
      assert_select "[data-campaign-vote] a[href=?]", meeting_path(older.motion.meeting), count: 1
      assert_select "[data-campaign-activity] a[href=?]", topic_path(@water), count: 1

      later = activity_vote(date: Date.new(2026, 11, 2), description: "Defer the water contract for further review", value: "yes", peer_value: "no", outcome: "failed")
      get member_path(@jordan)
      ids = css_select("[data-campaign-vote]").map { |row| row["data-campaign-vote"].to_i }
      assert_equal [ later.id, older.id ], ids
      assert_select "[data-campaign-vote='#{later.id}']", text: /Jordan Example: Yes.*Council: Failed/m
      assert_no_difference [ "CampaignExtraction.count", "CampaignRequest.count" ] do
        get member_path(@jordan)
        assert_select "[data-campaign-vote]", count: 2
      end
    end
    assert_equal 2, @calls.size
  end

  test "service dates and known Council meetings bound the record while contested procedural votes remain" do
    activity_vote(date: Date.new(2024, 4, 15), description: "Before service canary")
    activity_vote(date: Date.current + 7.days, description: "Future canary")
    activity_vote(date: Date.new(2025, 7, 1), status: "cancelled", description: "Canceled canary")
    activity_vote(date: Date.new(2025, 7, 2), title: "City Council Hamilton Property Concept Listening Session", description: "Listening canary")
    planning = Committee.create!(name: "Planning activity fixture", slug: "planning-activity-fixture")
    activity_vote(date: Date.new(2025, 7, 3), committee: planning, title: "Plan Commission", description: "Committee canary")
    activity_vote(date: Date.new(2025, 7, 7), description: "Enter closed session", value: "yes")
    split = activity_vote(date: Date.new(2025, 7, 14), description: "Enter closed session", value: "no")
    get member_path(@jordan)
    assert_select "[data-campaign-vote]", count: 1
    assert_select "[data-campaign-vote='#{split.id}']"
    %w[Before Future Canceled Listening Committee].each do |canary|
      assert_select "[data-campaign-activity]", text: /#{canary}.*canary/, count: 0
    end
  end

  test "closed service and statement dates exclude unrelated time periods and an unknown departure is not invented" do
    older = activity_vote(date: Date.new(2024, 6, 3))
    relevant = activity_vote(date: Date.new(2025, 6, 2))
    activity_vote(date: Date.new(2026, 6, 1), description: "After departure canary")
    @period.update!(ended_on: "2025-12-31", end_source_version: @service_source, end_page: 2)
    @source.update!(published_on: "2025-01-01")
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Date metadata must reuse saved work" }) do
      ExtractCampaignSourceJob.perform_now(@source.id)
      MatchCampaignTopicsJob.perform_now(@source.id)
      get member_path(@jordan)
    end
    assert_select "[data-campaign-vote]", count: 1
    assert_select "[data-campaign-vote='#{relevant.id}']"
    assert_select "[data-campaign-vote='#{older.id}']", count: 0

    @period.update!(ended_on: nil, end_source_version: nil, end_page: nil)
    @position.update!(ended_on: "2025-12-31")
    get member_path(@jordan)
    assert_select "[data-campaign-vote]", count: 0
    assert_select "[data-campaign-activity] a[href=?]", topic_path(@water), count: 1
    assert_select ".member-campaign-empty", count: 0
  end

  test "issue corrections refresh the next request and withheld reporting is absent from the response" do
    record = activity_vote(date: Date.new(2025, 6, 2), description: "Distinct campaign action canary")
    SiteSetting.delete_all
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    sign_in_as(User.create!(email_address: "campaign-activity-reader@example.test", status: "active"))
    get member_path(@jordan)
    assert_select "[data-campaign-vote='#{record.id}']", count: 1
    assert_includes response.body, "Distinct campaign action canary"
    assert_includes response.headers["Cache-Control"], "no-store"

    target = Topic.create!(name: "water supply renewal", status: "approved")
    Topics::MergeService.new(source_topic: @water, target_topic: target).call
    get member_path(@jordan)
    assert_select "[data-campaign-activity] a[href=?]", topic_path(target), count: 1
    assert_select "[data-campaign-vote]", count: 1
    [ target, @related ].each { |topic| topic.update!(status: "blocked") }
    get member_path(@jordan)
    assert_select "[data-campaign-activity]", count: 0
    assert_select "#campaign-record .member-campaign-card", count: 2
    target.update!(status: "approved")
    get member_path(@jordan)
    assert_select "[data-campaign-vote]", count: 1

    delete public_session_path
    get member_path(@jordan)
    assert_select "#campaign-record", count: 0
    assert_not_includes response.body, "Distinct campaign action canary"
    assert_not_includes response.body, "Repair neighborhood water lines."
    assert_select ".gate-card", count: 1
  end
end
