require "test_helper"
require_relative "../support/campaign_issue_evidence_scenario"

class CampaignCityOutcomeTest < ActionDispatch::IntegrationTest
  include CampaignIssueEvidenceScenario

  setup do
    setup_campaign_actions
    @selection = Campaigns::PlatformSelection.new(CampaignStatement.current_for(@jordan))
    @platform = @selection.prepare
    @wording = @specific.data.fetch("supporting_quote")
    id = @selection.rows.index(@specific) + 1
    @group = { "primary" => id, "heading" => "Require owner occupancy for short-term rentals", "other_ids" => [],
      "undertaking" => "city_outcome", "record_test" => "An owner-occupancy rule takes effect.", "action_quote" => @wording }
    @chosen = { "groups" => [ @group ], "excluded" => (1..@selection.rows.size).to_a - [ id ] }
    @selection.publish!(@platform, @chosen.to_json)
    @quote = "On June 2 the city implemented the requirement for owners to live in their short-term rentals for part of each year."
    @document.update!(extracted_text: @quote)
    @review = CouncilProfiles::ExtractIssueUpdates.prepare(@document)
    result = { complete: true, recommendations: [], actions: [], updates: [ { agenda_item_id: @vote.motion.agenda_item_id,
      topic_ids: [ @water.id ], occurred_on: "2025-06-02", status: "completed", subject: "Owner occupancy",
      summary: "The owner-occupancy requirement took effect.", quote: @quote, conditions: nil } ] }
    with_campaign_transport(content: result.to_json) do
      ExtractCouncilIssueUpdatesJob.perform_now(@document.id, budget_run_id: campaign_budget(stage: @review).id)
    end
    candidates = Campaigns::IssueEvidenceCandidates.for_member(@jordan).select { |r| r[:review] == @review && r[:statement] == @specific }
    @match = Campaigns::IssueEvidenceInput.prepare(@review.reload, candidates: candidates).sole
    @row = { key: @match.context.fetch("pairs").sole.fetch("key"), status: "direct", reason: "The owner-occupancy rule took effect.",
      source_quote: @quote, position_words: @wording, undertaking: "city_outcome", city_outcome: "delivered", outcome_on: "2025-06-02" }
  end

  test "a checked city result reaches the score and later profile without a motion or personal attribution" do
    evidence = CouncilProfiles::TermEvidence.new(@jordan)
    pending = CouncilProfiles::PromiseFollowThrough.for_publication({ "promises" => [] }, evidence, @jordan)
    report = CouncilTermSummary.create!(member: @jordan, term_started_on: @period.started_on, generated_at: Time.current,
      sentences: evidence.sourced_overview([]), promise_assessments: pending)
    calls = @calls.size
    with_campaign_transport(content: { matches: [ @row ] }.to_json) do
      perform_enqueued_jobs(only: CouncilProfiles::ApplyCityOutcomesJob) do
        Campaigns::MatchActions.call(@match, budget_run: campaign_budget(stage: @match))
      end
    end
    findings = report.reload.promise_assessments
    assert_equal "city_result", findings.sole.fetch("status")
    assert_equal @row[:reason], findings.sole.fetch("reason")
    assert_equal @quote, findings.sole.fetch("outcome_quote")
    CouncilProfiles::ApplyCityOutcomesJob.perform_now(@jordan.id)
    assert_equal findings, report.reload.promise_assessments
    assert_equal calls + 1, @calls.size
    get member_path(@jordan)
    assert_select ".member-term-score", text: /100\/100/
    assert_select "#promise-group-city_result", text: /City delivered the outcome/
    assert_select "#promise-group-city_result a[href=?]", @document.source_url
    assert_select "#promise-group-city_result blockquote", text: @quote
    assert_select "#promise-group-met", count: 0

    @selection.publish!(@platform, @chosen.merge("groups" => [ @group.merge("undertaking" => "personal_action") ]).to_json, correction: true)
    get member_path(@jordan)
    assert_select "#promise-group-city_result", count: 0
    evidence = CouncilProfiles::TermEvidence.new(@jordan)
    findings = CouncilProfiles::PromiseFollowThrough.for_publication({ "promises" => [] }, evidence, @jordan)
    assert_equal "pending_review", findings.sole.fetch("status")
  end

  test "an older direct comparison can be assessed once and a city milestone earns partial fulfillment" do
    # Existing receipts have source passages but predate the city-outcome judgment.
    legacy_context = @match.context.except("assesses_city_outcomes")
    CampaignActionReview.where(id: @match.id).update_all(context: legacy_context)
    legacy = @row.except(:city_outcome, :outcome_on, :undertaking, :position_words)
    with_campaign_transport(content: { matches: [ legacy ] }.to_json) do
      Campaigns::MatchActions.call(@match.reload, budget_run: campaign_budget(stage: @match))
    end
    candidates = Campaigns::IssueEvidenceCandidates.for_member(@jordan).select { |r| r[:review] == @review && r[:statement] == @specific }
    revision = Campaigns::IssueEvidenceInput.prepare(@review, candidates: candidates).sole
    assert_not_equal @match, revision
    revised = @row.merge(key: revision.context.fetch("pairs").sole.fetch("key"), city_outcome: "advanced")
    with_campaign_transport(content: { matches: [ revised ] }.to_json) do
      Campaigns::MatchActions.call(revision, budget_run: campaign_budget(stage: revision))
    end
    assert_equal [ revision ], Campaigns::IssueEvidenceInput.prepare(@review, candidates: candidates)
    evidence = CouncilProfiles::TermEvidence.new(@jordan)
    finding = CouncilProfiles::PromiseFollowThrough.for_publication({ "promises" => [] }, evidence, @jordan).sole
    assert_equal "city_progress", finding.fetch("status")
    score = CouncilProfiles::PromiseFollowThrough.new([ finding ], elapsed: Rational(3, 4))
    assert_equal 0.5, score.net_points
    assert_equal 50, score.score
    assert_equal 1, score.partial_count
    assert_equal 0, score.open_count
    assert_equal 0, score.met
    report = CouncilTermSummary.create!(member: @jordan, term_started_on: @period.started_on, generated_at: Time.current,
      sentences: evidence.sourced_overview([]), promise_assessments: [ finding ])
    get member_path(@jordan)
    assert_select ".member-term-score", text: %r{50/100}
    assert_select "#promise-group-city_progress .outcome-points", "0.5 points"
    assert_select ".score-lead", text: /1 position with partial credit/

    # An earlier losing vote and a later city milestone describe one position.
    report.update!(promise_assessments: [ finding.merge("status" => "blocked") ])
    CouncilProfiles::ApplyCityOutcomesJob.perform_now(@jordan.id)
    assert_equal [ "city_progress" ], report.reload.promise_assessments.pluck("status")
    admin = User.create!(email_address: "comparison-editor@example.test", admin: true, status: "active")
    @match.reject_matches!(keys: @match.pair_keys, actor: admin, reason: "This passage refers to another rental program.")
    corrected = CouncilProfiles::TermEvidence.new(@jordan)
    assert_equal "pending_review", CouncilProfiles::PromiseFollowThrough.for_publication({ "promises" => [] }, corrected, @jordan).sole.fetch("status")
  end

  test "a proposed measure, unmatched campaign language and a different event date cannot receive a city verdict" do
    parser = Campaigns::ActionMatches.new(@match.context)
    [ { position_words: "Build a parking lot" }, { outcome_on: "2023-06-02" }, { undertaking: "personal_action" } ].each do |change|
      assert_raises(Campaigns::ActionMatches::InvalidResponse) { parser.parse({ matches: [ @row.merge(change) ] }.to_json) }
    end
    proposed = @match.context.deep_dup
    proposed.fetch("pairs").sole.fetch("evidence")["status"] = "proposed"
    assert_raises(Campaigns::ActionMatches::InvalidResponse) { Campaigns::ActionMatches.new(proposed).parse({ matches: [ @row ] }.to_json) }
  end
end
