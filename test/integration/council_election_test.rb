require "test_helper"
require_relative "../support/campaign_action_scenario"

class CouncilElectionTest < ActionDispatch::IntegrationTest
  include CampaignActionScenario

  test "a spring reader can find the expiring seats and follow the exact earlier statement to its record" do
    setup_campaign_actions(multiple_issues: true)
    review_campaign_actions
    guide = ResidentContent::CouncilElection.new(ResidentContent::CouncilElection::GUIDE.merge(
      "terms_ending" => { @jordan.name => "https://example.test/term" }))
    @other_issue.update!(resident_impact_score: 5)

    travel_to Time.zone.local(2026, 11, 21) do
      get root_path
      destination = css_select(".home-header a[href*='spring-election']").sole["href"]
      ResidentContent::CouncilElection.stub(:current, guide) do
        get destination
        assert_select "#spring-election", text: /Whose terms end this spring/
        assert_select "#spring-election", text: /haven’t verified who is running/
        assert_select "#spring-election", text: /Candidacy source/, count: 0
        assert_select ".election-person", text: /From the 2024 campaign/
        assert_select ".election-person", text: /Require owners to live/
        target = css_select(".election-person a").find { |link| link.text.include?("this statement") }["href"]
        get target
        assert_select ".member-election-status", text: /term ends in spring 2027.*Reelection plans unconfirmed/m
        assert_select "#campaign-statement" do
          assert_select ".member-campaign-position", text: /Require owners to live/
          assert_select ".member-campaign-vote-results", text: /Voted yes.*Council: Failed/m
          assert_select ".member-campaign-position > p", text: /same owner-occupancy requirement/
          assert_select "blockquote", text: @quote
          assert_select "a[href=?]", meeting_path(@vote.motion.meeting)
          assert_select ".member-campaign-vote", text: /license fee/, count: 0
        end
        get member_path(@taylor, statement: @specific.id)
        assert_select "#campaign-statement", text: /statement is unavailable/

        SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
        get destination
        assert_not_includes response.body, guide.terms_ending.fetch(@jordan.name)
        assert_not_includes response.body, @specific.data.fetch("summary")
        get target
        assert_select "#campaign-statement, .member-election-status", count: 0
        assert_not_includes response.body, @specific.data.fetch("summary")
      end
    end
    travel_to Time.zone.local(2027, 4, 7) do
      get root_path
      assert_select "a[href*='spring-election']", count: 0
      get committee_path(@council.slug)
      assert_select "#spring-election", count: 0
    end
  end

  test "a sourced challenger can have a current platform without a council term" do
    setup_member_campaign
    analyze_member_campaign
    council = Committee.create!(name: "City Council")
    source_url = "https://example.test/candidate-filing"
    guide = ResidentContent::CouncilElection.new(ResidentContent::CouncilElection::GUIDE.merge(
      "candidates" => { @morgan.name => source_url }, "terms_ending" => {}))
    ResidentContent::CouncilElection.stub(:current, guide) do
      get committee_path(council.slug)
      assert_select ".election-person" do
        assert_select "a[href=?]", source_url
        assert_select "p", text: /From the 2027 campaign.*Publish clearer spending reports/m
        assert_select "a", text: "Full council record", count: 0
      end
      get css_select(".election-person a").find { |link| link.text.include?("this statement") }["href"]
      assert_select ".member-election-status", text: /Confirmed candidate for spring 2027/
      assert_select "#campaign-statement", text: /haven’t linked a later council action/
    end
  end
end
