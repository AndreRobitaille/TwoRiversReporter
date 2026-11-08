require "test_helper"
require_relative "../support/campaign_activity_scenario"

class MemberProfileLayoutTest < ActionDispatch::IntegrationTest
  include CampaignActivityScenario

  setup do
    setup_campaign_activity
    @other = activity_vote(date: Date.new(2025, 6, 2), description: "Keep the public pier accessible")
    @other.motion.agenda_item.topics.clear
  end

  test "main record precedes complementary campaign context and other votes remain in closed server-rendered disclosure" do
    get member_path(@jordan)
    assert_response :success
    assert_select ".member-profile-primary #voting-record", count: 1
    assert_select "aside.member-profile-sidebar #campaign-record .member-campaign-card", count: 2
    assert_select "details.member-campaign-card > summary", count: 2
    assert_select ".member-campaign-card[open]", count: 0
    assert_select ".member-profile-primary + aside.member-profile-sidebar", count: 1
    assert_select ".member-other-votes[open]", count: 0
    assert_select ".member-other-votes a[href=?]", meeting_path(@other.motion.meeting), text: @other.motion.description
    assert_select "a[href='#campaign-record']", text: "Campaign priorities", count: 1
  end

  test "verified Google receives the same sourced campaign and closed vote content while a spoof stays gated" do
    get member_path(@jordan)
    assert_response :success
    expected = css_select("#campaign-record").sole.text
    SiteSetting.delete_all
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.write(Crawlers::IpRanges.new.cache_key(:google), {
      prefixes: [ "66.249.66.0/27" ], fetched_at: Time.current.to_i
    })
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Crawlers must read saved evidence without generation" }) do
      get member_path(@jordan), headers: { "User-Agent" => "Googlebot/2.1", "REMOTE_ADDR" => "66.249.66.1" }
      assert_response :success
      assert_equal expected, css_select("#campaign-record").sole.text
      assert_select "#campaign-record .member-campaign-card a[href=?]", @source.source_url, count: 2
      assert_select ".member-other-votes[open]", count: 0
      assert_select ".member-other-votes a[href=?]", meeting_path(@other.motion.meeting), text: @other.motion.description
      assert_equal "private, no-store", response.headers["Cache-Control"]
      get member_path(@jordan), headers: { "User-Agent" => "Googlebot/2.1", "REMOTE_ADDR" => "198.51.100.42" }
      assert_response :success
      assert_select ".member-profile-sidebar, #campaign-record, .member-other-votes", count: 0
      assert_not_includes response.body, @other.motion.description
      assert_not_includes response.body, "Repair neighborhood water lines."
      assert_select ".gate-card", count: 1
    end
  ensure
    Rails.cache = original_cache if original_cache
  end

  test "additional statements remain in the full evidence disclosure instead of multiplying priority rows" do
    original = @jordan.campaign_statements.first
    3.times do |index|
      extra = original.dup
      extra.sequence = 20 + index
      extra.data = original.data.merge("summary" => "Additional campaign priority #{index + 1}.")
      extra.save!
    end
    get member_path(@jordan)
    assert_response :success
    assert_select "#campaign-record > .member-campaign-list > .member-campaign-issue", count: 1
    assert_select "#campaign-record > .member-campaign-evidence[open]", count: 0
    assert_select "#campaign-record > .member-campaign-evidence > summary", text: "Campaign statements and sources (5)"
    assert_select "#campaign-record > .member-campaign-evidence .member-campaign-card", count: 5
    assert_select ".member-campaign-card[open]", count: 0
    assert_select ".member-campaign-card a[href=?]", @source.source_url, count: 5
    assert_includes response.body, "Additional campaign priority 3."
  end

  test "the visible action is the actual postponement and not approval of the agenda subject" do
    vote = activity_vote(date: Date.new(2025, 7, 7), value: "yes", outcome: "passed",
      agenda_title: "Water service fee ordinance", description: "Motion to table the ordinance until the next meeting")
    get member_path(@jordan)
    assert_response :success
    assert_select ".member-campaign-issue[open] .member-campaign-actions", text: /Voted yes.*Table the ordinance until the next meeting/m
    assert_select ".member-campaign-issue[open] .member-campaign-steps", text: /Council result.*The motion passed/m
    assert_select ".member-campaign-evidence [data-campaign-vote='#{vote.id}']", count: 1
    assert_select ".member-campaign-evidence[open]", count: 0
  end

  test "a generic adoption includes its subject without claiming campaign follow-through" do
    record = activity_vote(date: Date.new(2025, 9, 15), value: "yes", outcome: "passed",
      agenda_title: '25-187 Ordinance to Amend Section 5-2-5 of the Municipal Code, "Amount of Sewer Service Charges"',
      description: "Motion to waive reading and adopt the ordinance, as recommended by the Public Works Committee")
    get member_path(@jordan)
    assert_response :success
    assert_select ".member-campaign-steps h4", text: "Related Council votes"
    assert_select ".member-campaign-actions", text: /Voted yes.*Adopt.*Amount of Sewer Service Charges/m
    assert_select ".member-campaign-actions", text: /"Amount of Sewer Service Charges"/
    assert_select "[data-campaign-vote='#{record.id}']", text: /#{Regexp.escape(record.motion.description)}/
  end

  test "repeated statements share issue navigation without losing qualifications or source evidence" do
    data = campaign_response_data
    answer = data.fetch("participants").first.fetch("answers").first
    old_passage = answer.fetch("passage")
    answer["passage"] = "#{old_passage} Only when grants cover the cost."
    duplicate = answer.fetch("statements").first.deep_dup
    duplicate.merge!("summary" => "Repair water lines only when grants cover the cost.",
      "supporting_quote" => answer.fetch("passage"), "conditions" => "Only when grants cover the cost.")
    answer.fetch("statements") << duplicate
    @source.update!(body: @source.body.sub(old_passage, answer.fetch("passage")))
    analyze_member_campaign(content: data.to_json)
    stage = Campaigns::MatchTopics.prepare(@source.current_version)
    matches = { "matches" => stage.context.fetch("statements").map do |statement|
      ids = statement.fetch("sequence") < 2 ? [ @water.id, @related.id ] : []
      { "sequence" => statement.fetch("sequence"), "status" => ids.any? ? "matched" : "no_match",
        "topic_ids" => ids, "reason" => "Repeated water position in the deterministic source." }
    end }
    with_campaign_transport(content: matches.to_json) do
      MatchCampaignTopicsJob.perform_now(@source.id, budget_run_id: campaign_budget(stage: stage).id)
    end
    repeated = @source.current_version.extraction.campaign_statements.find_by!(sequence: 1)
    record = activity_vote(date: Date.new(2025, 7, 7))
    before = [ CampaignRequest.count, CampaignExtraction.count ]
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Grouping saved evidence must not generate prose" }) do
      2.times { get member_path(@jordan) }
    end
    assert_select ".member-campaign-issue", count: 1
    assert_select "[data-campaign-vote='#{record.id}']", count: 1
    assert_select "[data-campaign-source-statement='#{repeated.id}']", text: /Only when grants cover the cost/
    assert_select "#campaign-record > .member-campaign-evidence .member-campaign-card", count: 3
    assert_equal before, [ CampaignRequest.count, CampaignExtraction.count ]
  end
end
