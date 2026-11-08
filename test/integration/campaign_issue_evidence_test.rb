require "test_helper"
require "minitest/mock"
require_relative "../support/campaign_issue_evidence_scenario"

class CampaignIssueEvidenceTest < ActionDispatch::IntegrationTest
  include CampaignIssueEvidenceScenario

  setup { setup_issue_matching }

  test "one shared comparison connects unsuccessful work and separate outcome without keyword matches" do
    assert_equal 1, @calls.size
    assert_equal 1, @issue_review.data.fetch("actions").size
    assert_equal 2, @issue_review.data.fetch("updates").size
    assert_equal 8, @matching.context.fetch("pairs").size # Includes three earlier broad-priority pairs.
    match_issue_evidence
    assert_equal "completed", @matching.status
    assert_equal 8, @matching.data.fetch("matches").size
    assert_equal 2, @matching.data.fetch("matches").count { |row| row["status"] == "direct" }
    assert_equal 2, @calls.size
    assert_equal 1, @matching.requests.count
    get member_path(@jordan)
    assert_select "#campaign-record [data-campaign-issue-evidence=action]", text: /request did not advance/, count: 1
    assert_select "#campaign-record [data-campaign-issue-evidence=outcome]", text: /postponed for research/, count: 1
    assert_select "#campaign-record", text: /license fee portal was completed/, count: 0
    assert_select "#campaign-record blockquote", text: @advocacy_quote
    assert_select "#campaign-record blockquote", text: @outcome_quote
    assert_no_match(/promise (?:kept|broken)|fulfilled|did nothing/i, css_select("#campaign-record").map(&:text).join)
    get member_path(@taylor)
    assert_select "#campaign-record [data-campaign-issue-evidence]", count: 0
    assert_select "#issue-updates", text: /postponed for research/
  end

  test "unchanged negative and direct pairs survive repeated nightly and page reads without extra calls" do
    match_issue_evidence
    count = CampaignActionReview.count
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Completed comparisons must be reused" }) do
      2.times do
        assert_enqueued_with(job: MatchCampaignIssueEvidenceJob) { ReconcileCampaignSourcesJob.perform_now }
        perform_enqueued_jobs(only: MatchCampaignIssueEvidenceJob)
        get member_path(@jordan)
      end
    end
    assert_equal count, CampaignActionReview.count
    assert_equal 2, @calls.size
    assert_equal 1, @matching.requests.count
  end

  test "source corrections remove stale statement links before reanalysis and retain the original evidence" do
    match_issue_evidence
    get member_path(@jordan)
    assert_select "#campaign-record [data-campaign-issue-evidence]", count: 2
    @document.update!(extracted_text: "The source needs a factual correction.")
    2.times do
      get member_path(@jordan)
      assert_select "#campaign-record [data-campaign-issue-evidence]", count: 0
      assert_not_includes response.body, @advocacy_quote
    end
    assert_equal @outcome_quote, @issue_review.reload.data.fetch("updates").first.fetch("quote")
    assert_equal 1, @matching.requests.count
  end

  test "a newer campaign statement cannot acquire prior work and an out-of-service action is excluded" do
    match_issue_evidence
    @period.update!(ended_on: "2025-05-01", end_source_version: @service_source, end_page: 5)
    get member_path(@jordan)
    assert_select "#campaign-record [data-campaign-issue-evidence]", count: 0
    @period.update!(ended_on: nil, end_source_version: nil, end_page: nil)
    @source.update!(published_on: "2025-07-01")
    get member_path(@jordan)
    assert_select "#campaign-record [data-campaign-issue-evidence]", count: 0
  end

  test "direct passages must support their own pair and every retrieved pair gets a result" do
    parser = Campaigns::ActionMatches.new(@matching.context)
    assert_equal 8, parser.parse(issue_matches.to_json).fetch("matches").size
    changed = issue_matches
    action = changed[:matches].find { |row| row[:source_quote] == @advocacy_quote }
    action[:source_quote] = @outcome_quote
    assert_raises(Campaigns::ActionMatches::InvalidResponse) { parser.parse(changed.to_json) }
    assert_raises(Campaigns::ActionMatches::InvalidResponse) { parser.parse({ matches: issue_matches[:matches].drop(1) }.to_json) }
  end

  test "missing allowance pauses and legacy action policies cannot admit this new source work" do
    Ai::OpenAiService.stub(:new, ->(*) { flunk "No source allowance" }) do
      MatchCampaignIssueEvidenceJob.perform_now(@issue_review.id)
    end
    assert_equal "budget_paused", @matching.reload.status
    assert_equal 0, @matching.attempts
    assert_equal 1, @calls.size
    month = CouncilAiBudgetMonth.new(live_actions: { "starting_on" => "2024-04-01" })
    assert_nil CouncilProfiles::LiveBudget.policy_for(@matching, month)
    month.live_actions["issue_sources"] = { "committee_ids" => [ @council.id ], "document_types" => [ "minutes_pdf" ], "starting_on" => "2026-11-08" }
    assert_equal "2026-11-08", CouncilProfiles::LiveBudget.policy_for(@matching, month).fetch("starting_on")
  end

  test "allowed reader sees paired evidence before anonymous and alternate-format exclusions" do
    match_issue_evidence
    SiteSetting.instance.update!(access_mode: "gated")
    sign_in_as(User.create!(email_address: "issue-matching-reader@example.test", status: "active"))
    get member_path(@jordan)
    assert_select "#campaign-record [data-campaign-issue-evidence]", count: 2
    delete public_session_path
    get member_path(@jordan)
    assert_select "#campaign-record", count: 0
    assert_not_includes response.body, @advocacy_quote
    get member_path(@jordan, format: :json)
    assert_response :not_acceptable
    assert_not_includes response.body, @outcome_quote
  end
end
