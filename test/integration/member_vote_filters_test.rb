require "test_helper"
require "minitest/mock"
require_relative "../support/vote_filter_scenario"

class MemberVoteFiltersTest < ActionDispatch::IntegrationTest
  include VoteFilterScenario

  setup { setup_vote_filters }

  test "search and topic filters apply before pagination without multiplying multi-topic decisions" do
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Searching saved votes must not call AI" }) do
      get member_path(@member, votes: "all", q: "Hamilton GRANT agreement", topic: @topic.id, kind: "substantive")
      assert_response :success
      assert_select ".member-vote-filter-result", text: /26 matching votes/
      assert_select ".member-recorded-votes .member-vote-row", count: 25
      ids = css_select(".member-recorded-votes .member-vote-row").map { |row| row["id"] }
      assert_equal ids.uniq, ids
      assert_not_includes response.body, @blocked.name
      page_two = css_select(".member-vote-pages a").find { |link| link.text == "2" }
      query = Rack::Utils.parse_nested_query(URI.parse(page_two["href"]).query)
      assert_equal "all", query["votes"]
      assert_equal @topic.id.to_s, query["topic"]
      assert_equal "Hamilton GRANT agreement", query["q"]
      get page_two["href"]
      assert_select ".member-recorded-votes .member-vote-row", count: 1
      assert_select "#recorded-vote-#{@grant_votes.first.id}"
      assert_select ".member-vote-pages [aria-current=page]", text: "2"
    end
  end

  test "view switches and period selection preserve filters while resetting the page" do
    get member_path(@member, votes: "all", q: "grant", topic: @topic.id, split: "divided", term: @period.period_key)
    featured = css_select(".member-vote-views a").find { |link| link.text == "Featured votes" }
    query = Rack::Utils.parse_nested_query(URI.parse(featured["href"]).query)
    assert_equal({ "q" => "grant", "topic" => @topic.id.to_s, "split" => "divided", "term" => @period.period_key }, query)
    assert_select ".member-record-period input[name=q][value=grant]"
    assert_select ".member-record-period input[name=split][value=divided]"
    assert_select ".member-vote-filters input[name=term][value='2024-election']"
    assert_select ".member-vote-filters input[name=page]", count: 0
    %w[q topic body kind split term].each { |id| assert_select "[id='#{id}']", count: 1 }
    get featured["href"]
    assert_select ".member-vote-row", count: 1
    assert_select ".member-vote-motion a", text: @grant_votes.first.motion.description
    clear = css_select(".member-vote-filter-result a").sole
    assert_equal({ "term" => @period.period_key }, Rack::Utils.parse_nested_query(URI.parse(clear["href"]).query))
  end

  test "divided means actual yes and no and changes on the next read" do
    get member_path(@member, votes: "all", split: "divided")
    assert_select ".member-recorded-votes .member-vote-row", count: 2
    assert_select "#recorded-vote-#{@grant_votes.first.id}"
    assert_select "#recorded-vote-#{@procedural_dissent.id}"
    assert_select "#recorded-vote-#{@abstention.id}", count: 0
    @grant_votes.first.motion.votes.find_by!(member: @peer).update!(value: "recused")
    get member_path(@member, votes: "all", split: "divided")
    assert_select ".member-recorded-votes .member-vote-row", count: 1
    assert_select "#recorded-vote-#{@procedural_dissent.id}"
  end

  test "procedural filter preserves the difference between featured and complete views" do
    get member_path(@member, votes: "all", kind: "procedural")
    assert_select ".member-recorded-votes .member-vote-row", count: 2
    get member_path(@member, kind: "procedural")
    assert_select ".member-vote-row", count: 1
    assert_select ".member-vote-motion a", text: @procedural_dissent.motion.description
    assert_select ".member-vote-motion a", text: @routine.motion.description, count: 0
  end

  test "body filter selects special Council records and other bodies only in all-records mode" do
    get member_path(@member, votes: "all", body: @special.body_name)
    assert_select ".member-recorded-votes .member-vote-row", count: 1
    assert_select "#recorded-vote-#{@grant_votes.last.id}"
    assert_select "select[name=body] option[value='Planning Commission']", count: 0
    get member_path(@member, votes: "all", term: "all", body: @other_body.body_name)
    assert_select ".member-recorded-votes .member-vote-row", count: 1
    assert_select "#recorded-vote-#{@planning_vote.id}"
  end

  test "empty matches and literal punctuation are handled without SQL wildcard behavior" do
    percent = filter_vote("Approve 100% local funding")
    get member_path(@member, votes: "all", q: "%")
    assert_select ".member-recorded-votes .member-vote-row", count: 1
    assert_select "#recorded-vote-#{percent.id}"
    get member_path(@member, votes: "all", q: "missing record xyz")
    assert_select ".member-recorded-empty", text: "No votes match these filters."
    assert_select ".member-vote-filter-result", text: /0 matching votes/
    assert_select ".member-vote-pages", count: 0
    get member_path(@member, votes: "all", q: [ "not a scalar" ], kind: "invalid", topic: @blocked.id)
    assert_response :success
    assert_select ".member-vote-filter-result", count: 0
    assert_select "select[name=topic] option[value=?]", @blocked.id, count: 0
  end

  test "filter options and searched records obey the existing access boundary" do
    SiteSetting.instance.update!(access_mode: "gated")
    sign_in_as(User.create!(email_address: "vote-search-reader@example.test", status: "active"))
    get member_path(@member, votes: "all", q: "agreement")
    assert_select ".member-vote-filters", count: 1
    assert_select ".member-recorded-votes .member-vote-row", count: 25
    assert_select "select[name=topic] option[value=?]", @topic.id
    delete public_session_path
    get member_path(@member, votes: "all", q: "agreement")
    assert_select ".member-vote-filters", count: 0
    assert_select ".member-recorded-votes", count: 0
    assert_not_includes response.body, @topic.name
    assert_not_includes response.body, @grant_votes.first.motion.description
  end
end
