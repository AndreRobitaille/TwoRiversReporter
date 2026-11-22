require "test_helper"
require_relative "../support/campaign_action_scenario"

class CouncilElectionTest < ActionDispatch::IntegrationTest
  include CampaignActionScenario

  test "the Council timeline stays fixed throughout filing and keeps official information available in gated mode" do
    council = Committee.create!(name: "City Council")
    member = Member.create!(name: "Shannon Derby")
    doug = Member.create!(name: "Douglas Brandt")
    doug.member_aliases.create!(name: "Doug Brandt")
    CommitteeMembership.create!(committee: council, member: member, role: "member", source: "admin_manual")

    timeline = travel_to Date.new(2026, 12, 1) do
      get committee_path(council.slug)
      assert_select ".committee-article-header nav", count: 0
      assert_select "#current-members a[href=?]", member_path(member)
      assert_select "#recent-work h2", "Recent Council work"
      assert_select "aside#spring-election" do
        assert_select "p", text: /up to three/
        assert_equal %w[2026-12-01 2027-01-05 2027-04-06], css_select("time").map { |time| time["datetime"] }
        assert_select "details:not([open]) > summary", text: "Spring 2027 Council election"
        assert_select ".election-people details", count: 0
        assert_select "#seat-shannon-derby a[href=?]", member_path(member), text: member.name
        assert_select "#seat-doug-brandt a[href=?]", member_path(doug), text: "Doug Brandt"
        assert_select "#seat-mark-bittner", text: "Mark Bittner"
        assert_select "#seat-mark-bittner a", count: 0
      end
      css_select("#spring-election").sole.text
    end

    travel_to Date.new(2027, 2, 1) do
      get committee_path(council.slug)
      assert_equal timeline, css_select("#spring-election").sole.text
      assert_no_match(/as of|haven’t verified who is running/i, timeline)
      assert_select "#spring-election a", text: /Official ballot/
      SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
      get committee_path(council.slug)
      assert_select "#spring-election a", text: /Official ballot/
      assert_select "#current-members, #spring-election .election-people", count: 0
      assert_select "#spring-election .election-timeline time", count: 3
      assert_not_includes response.body, member.name
    end
  end

  test "the Council guide changes seats exactly one week after each spring election" do
    council = Committee.create!(name: "City Council")
    cohorts = {
      "2027-04-06" => [ "Mark Bittner", "Doug Brandt", "Shannon Derby" ],
      "2028-04-04" => [ "Bill LeClair", "Tim Petri", "Scott Stechmesser" ],
      "2029-04-03" => [ "Katherine Dahlke", "Darla LeClair", "Adam Wachowski" ]
    }
    members = cohorts.values.flatten.index_with { |name| Member.create!(name: name) }
    starts_on = Date.new(2026, 11, 22)

    cohorts.each do |election_date, names|
      election_on = Date.iso8601(election_date)
      [ starts_on.beginning_of_day, (election_on + 6).end_of_day ].each do |instant|
        travel_to instant do
          get root_path
          assert_select ".home-header a[href=?]", committee_path(council.slug, anchor: "spring-election"), text: /#{election_on.year}/
          get committee_path(council.slug)
          assert_select "#election-heading", text: /#{election_on.year}/
          links = css_select("#spring-election .election-people a")
          assert_equal names, links.map(&:text)
          assert_equal names.map { |name| member_path(members.fetch(name)) }, links.map { |a| a["href"] }
          assert_select ".election-timeline time[datetime=?]", election_date
          get links.first["href"]
          assert_select ".member-election-status", text: /term ends in spring #{election_on.year}/
        end
      end
      starts_on = election_on + 7
    end

    travel_to Date.new(2029, 4, 10) do
      get committee_path(council.slug)
      assert_select "#spring-election", count: 0
      assert_select "#recent-work"
    end
  end

  test "a spring reader can open an incumbent profile and older statement links still resolve" do
    setup_campaign_actions(multiple_issues: true)
    review_campaign_actions
    guide = ResidentContent::CouncilElection.new(ResidentContent::CouncilElection::SCHEDULE.fetch("elections").first.merge(
      "terms_ending" => { @jordan.name => "https://example.test/term" }))
    @other_issue.update!(resident_impact_score: 5)

    travel_to Time.zone.local(2026, 11, 21) do
      get root_path
      destination = css_select(".home-header a[href*='spring-election']").sole["href"]
      ResidentContent::CouncilElection.stub(:current, guide) do
        get destination
        assert_select "#spring-election h3", text: "Council terms ending in 2027"
        target = css_select("#spring-election li a").sole["href"]
        assert_equal member_path(@jordan), target
        assert_select "#spring-election", text: /Require owners to live/, count: 0
        get target
        assert_select ".member-election-status", text: /term ends in spring 2027/
        assert_select ".member-election-status a[href=?]", guide.terms_ending.fetch(@jordan.name)
        get css_select(".member-term-links a").first["href"]
        assert_select "#campaign-record", text: /Require owners to live/
        statement_path = member_path(@jordan, statement: @specific.id, anchor: "campaign-statement")
        get statement_path
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
        assert_select "#spring-election a[href=?]", target, count: 0
        get statement_path
        assert_select "#campaign-statement, .member-election-status", count: 0
        assert_not_includes response.body, @specific.data.fetch("summary")
      end
    end
  end

  test "a sourced challenger can have a current platform without a council term" do
    setup_member_campaign
    analyze_member_campaign
    council = Committee.create!(name: "City Council")
    source_url = "https://example.test/candidate-filing"
    guide = ResidentContent::CouncilElection.new(ResidentContent::CouncilElection::SCHEDULE.fetch("elections").first.merge(
      "candidates" => { @morgan.name => source_url }, "terms_ending" => {}))
    ResidentContent::CouncilElection.stub(:current, guide) do
      get committee_path(council.slug)
      target = css_select("#spring-election li a").sole
      assert_equal @morgan.name, target.text
      assert_equal member_path(@morgan), target["href"]
      get target["href"]
      assert_select ".member-election-status a[href=?]", source_url, text: /Confirmed candidate for spring 2027/
      assert_select "#campaign-record", text: /Publish clearer spending reports/
      statement = CampaignStatement.current_for(@morgan).first
      get member_path(@morgan, statement: statement.id, anchor: "campaign-statement")
      assert_select "#campaign-statement", text: /haven’t linked a later council action/
    end
  end
end
