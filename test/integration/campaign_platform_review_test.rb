require "test_helper"
require_relative "../support/campaign_issue_evidence_scenario"

require_relative "../support/council_service_sources"

class CampaignPlatformReviewTest < ActionDispatch::IntegrationTest
  include CampaignIssueEvidenceScenario
  include CouncilServiceSources

  setup do
    setup_member_campaign
    data = campaign_response_data
    statements = data.fetch("participants").first.fetch("answers").flat_map { |a| a.fetch("statements") }
    statements.first["comparison_heading"] = "Repair neighborhood water lines"
    statements.last["comparison_heading"] = "Keep services affordable"
    analyze_member_campaign(content: data.to_json)
    @selection = Campaigns::PlatformSelection.new(CampaignStatement.current_for(@jordan))
    @stage = @selection.prepare
    @kept, @excluded = @selection.rows
    @group = { "heading" => "Repair neighborhood water lines", "primary" => 1, "other_ids" => [],
      "undertaking" => "city_outcome", "action_quote" => "Repair neighborhood water lines", "record_test" => "The city authorizes repairs to neighborhood water lines." }
    @output = { "groups" => [ @group ], "excluded" => [ 2 ] }
  end

  test "source-level headings do not enter the term assessment before a platform review is queued" do
    @stage.destroy!
    election = @source.current_version.election_on
    @jordan.member_positions.create!(kind: "city_council", title: "Council Member", source: "official_website",
      source_url: "https://example.test/council", verified_at: Time.current)
    CouncilServicePeriod.record_starts!(period_key: "#{election.year}-election", source_version: service_source, page: 5,
      entries: [ { member_id: @jordan.id, started_on: election + 14 } ])
    travel_to (election + 20).noon
    assert_equal 2, @selection.rows.count { |row| row.data["comparison_heading"].present? }
    assert_not CouncilProfiles::TermEvidence.new(@jordan.reload).tracked?
  end

  test "the exact funded job publishes the same selection to pages, deep links and term evidence without charging twice" do
    get member_path(@jordan)
    assert_select "[data-campaign-proposal]", count: 0
    campaign_budget(stage: @stage)
    calls = @calls.size
    with_campaign_transport(content: @output.to_json) do
      2.times { ReviewCampaignPlatformsJob.perform_now(@jordan.id) }
    end
    assert_equal calls + 1, @calls.size
    assert_equal "completed", @stage.reload.status
    assert_equal @kept.id, @stage.groups.sole.fetch("primary")
    assert_equal 1, @stage.council_ai_budget_run.reservations.count
    assert_equal @output, JSON.parse(@stage.response_body)
    assert_not_includes @stage.parameters.fetch("messages").last.fetch("content"), "Keep services affordable"

    get member_path(@jordan)
    assert_select "[data-campaign-proposal]", count: 1
    assert_select "[data-campaign-proposal]", text: /Repair neighborhood water lines/
    get campaign_member_path(@jordan, statement: @excluded.id)
    assert_select "#campaign-statement", text: /unavailable/
    assert_not_includes response.body, @excluded.data.fetch("supporting_quote")
    @jordan.member_positions.create!(kind: "city_council", title: "Council Member", source: "official_website",
      source_url: "https://example.test/council", verified_at: Time.current)
    election = @source.current_version.election_on
    CouncilServicePeriod.record_starts!(period_key: "#{election.year}-election", source_version: service_source, page: 5,
      entries: [ { member_id: @jordan.id, started_on: election + 14 } ])
    travel_to (election + 20).noon
    facts = CouncilProfiles::TermEvidence.new(@jordan.reload).facts.select { |f| f[:promise_words] }
    assert_equal [ @group["heading"] ], facts.pluck(:position)
    assert CampaignStatement.exists?(@excluded.id)
    other = CampaignStatement.current_for(@taylor)
    assert_empty other.pluck(:id) & @stage.groups.pluck("primary")
    @kept.update!(excluded_at: Time.current)
    get campaign_member_path(@jordan, statement: @kept.id)
    assert_select "#campaign-statement", text: /unavailable/
    assert_not_includes response.body, @kept.data.fetch("supporting_quote")
  end

  test "the profile recomputes a saved report against the retained promises without reusing a judgment for a narrower undertaking" do
    election = @source.current_version.election_on
    travel_to (election + 40).noon
    @jordan.member_positions.create!(kind: "city_council", title: "Council Member", source: "official_website",
      source_url: "https://example.test/council", verified_at: Time.current)
    CouncilServicePeriod.record_starts!(period_key: "#{election.year}-election", source_version: service_source, page: 5,
      entries: [ { member_id: @jordan.id, started_on: election + 14 } ])
    sources = [ { "url" => @source.source_url, "label" => "Candidate questionnaire" } ]
    findings = [ @kept, @excluded ].map do |row|
      { "heading" => row.data.fetch("comparison_heading"), "status" => "met", "reason" => "The city approved funding.",
        "quote" => row.data.fetch("supporting_quote"), "label" => row.data.fetch("summary"), "facts" => [], "sources" => sources }
    end
    report = CouncilTermSummary.create!(member: @jordan, term_started_on: election + 14, promise_assessments: findings,
      sentences: [ { "text" => @excluded.data.fetch("summary"), "sources" => sources, "facts" => [] } ], generated_at: Time.current)
    @selection.publish!(@stage, @output.to_json)
    get member_path(@jordan)
    assert_select ".promise-title", count: 1, text: @group.fetch("heading")
    assert_select ".member-term-score", text: /100\/100/
    assert_not_includes response.body, @excluded.data.fetch("summary")
    @selection.publish!(@stage, @output.merge("groups" => [ @group.merge("heading" => "Replace pipes on one block") ]).to_json, correction: true)
    get member_path(@jordan)
    assert_select "#promise-group-pending_review .promise-title", "Replace pipes on one block"
    assert_select ".member-term-score", count: 0
    assert_equal 2, report.reload.promise_assessments.size

    # An intake cycle can change the campaign inventory while the next term
    # assessment has no standing budget. The profile still has a sourced record.
    report.promise_assessments.first.fetch("facts") << "superseded-campaign-fact"
    report.save!
    assert_raises(CouncilProfiles::ReserveAiSpend::Paused) do
      report.refresh!(Date.current, CouncilProfiles::TermEvidence.new(@jordan.reload))
    end
    assert_equal [ "pending_review" ], report.reload.promise_assessments.pluck("status")
    get member_path(@jordan)
    assert_select "#promise-group-pending_review .promise-title", "Replace pipes on one block"
    assert_not_includes response.body, @excluded.data.fetch("summary")
  end

  test "an invalid batch is kept for a source correction without an automatic paid retry" do
    campaign_budget(stage: @stage)
    calls = @calls.size
    bad = @output.merge("excluded" => [ 3 ]).to_json
    with_campaign_transport(content: bad) { 2.times { ReviewCampaignPlatformsJob.perform_now(@jordan.id) } }
    assert_equal calls + 1, @calls.size
    assert_equal "needs_review", @stage.reload.status
    assert_equal bad, @stage.response_body
    get campaign_member_path(@jordan, statement: @excluded.id)
    assert_select "#campaign-statement", text: /unavailable/
    @selection.publish!(@stage, @output.to_json, correction: true)
    assert_equal bad, @stage.reload.response_body
    get campaign_member_path(@jordan, statement: @kept.id)
    assert_select "#campaign-statement", text: /Repair neighborhood water lines/
  end

  test "the request schema bounds references to this candidate and its cost is included in the exact estimate" do
    params = @stage.parameters.deep_symbolize_keys
    choice = params.dig(:response_format, :json_schema, :schema, :properties, :groups, :items)
    assert_equal @selection.rows.size, choice.dig(:properties, :primary, :maximum)
    assert_includes choice.fetch(:required), "action_quote"
    travel_to Campaigns::CostPreflight::PRICING_CHECKED_ON.noon do
      quote = Campaigns::CostPreflight.for_stage(@stage)
      assert_equal "estimate", quote[:state]
      assert_equal CouncilProfiles::ReserveAiSpend.request_digest(params), quote[:request_digest]
      assert_operator quote[:input_allowance], :>=, params[:messages].sum { |m| m[:content].bytesize } + params[:response_format].to_json.bytesize
    end
  end

  test "missing or foreign evidence and an invented action clause cannot publish" do
    [ @output.merge("excluded" => []), @output.merge("excluded" => [ 3 ]),
      @output.merge("groups" => [ @group.merge("action_quote" => "Double the budget") ]) ].each do |response|
      assert_raises(ArgumentError) { @selection.publish!(@stage, response.to_json) }
      assert_nil @stage.reload.groups
    end
  end
end
