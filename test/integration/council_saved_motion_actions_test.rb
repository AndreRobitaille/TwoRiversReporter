require "test_helper"
require "minitest/mock"
require_relative "../support/campaign_action_scenario"

class CouncilSavedMotionActionsTest < ActionDispatch::IntegrationTest
  include CampaignActionScenario

  setup do
    setup_campaign_actions
    @water.update!(name: "short-term rentals")
    @meeting = @council.meetings.create!(body_name: "City Council", starts_at: Time.zone.parse("2025-06-16 18:00"),
      detail_page_url: "https://example.test/saved-motion-meeting")
    @proposal = "Motion made by Jordan Example to require short-term rental owners to live on site for part of the year. The motion received no second."
    @portal = "Motion made by Taylor Example to create an online portal for paying rental license fees."
    @procedural = "Motion made by Jordan Example to convene in closed session."
    @second = "The motion was seconded by Taylor Example."
    @saved_document = @meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: "https://example.test/saved-motion-minutes.pdf",
      extracted_text: [ @proposal, @portal, @procedural, @second ].join("\n"))
    second = saved_item("Rental discussion", @taylor, @second)
    second["motion"] = { "seconder" => @taylor.name }
    second["motion_evidence"] = { "seconder" => @second }
    @saved_summary = @meeting.meeting_summaries.create!(summary_type: "minutes_recap", generation_data: {
      "headline" => "Council considered rental changes", "source_type" => "minutes", "source_catalog" => [ Citations::SourceCatalog.snapshot(@saved_document) ],
      "item_details" => [ saved_item("Owner-occupancy proposal", @jordan, @proposal),
        saved_item("License fee portal", @taylor, @portal), saved_item("Convene in closed session", @jordan, @procedural), second ] })
    @calls.clear
    clear_enqueued_jobs
  end

  test "saved substantive motions reach the right profiles without another extraction or inferred campaign match" do
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Saved motion reads must not call AI" }) do
      assert_no_difference [ "CouncilIssueReview.count", "CouncilIssueRequest.count", "Vote.count", "CampaignActionRequest.count" ] do
        [ [ @jordan, @proposal ], [ @taylor, @portal ] ].each do |member, quote|
          get member_path(member)
          assert_response :success
          assert_select "#recorded-actions [data-recorded-action]", count: 1
          title = member == @jordan ? "Owner-occupancy proposal" : "License fee portal"
          assert_select "#recorded-actions [data-recorded-action] > p", text: "Made a motion on: #{title}"
          assert_select "#recorded-actions blockquote", text: quote
          assert_select "#recorded-actions a[href=?]", @saved_document.source_url
          assert_select "#campaign-record [data-campaign-issue-evidence]", count: 0
          assert_select "#recorded-actions", text: /convene in closed session/, count: 0
          assert_select "#recorded-actions", text: /seconded by Taylor Example/, count: 0
        end
      end
    end
  end

  test "one shared comparison batch caches direct and negative results across people and prose changes" do
    stage = prepare_matches
    assert_includes stage.context.fetch("pairs").map { |pair| pair.fetch("statement_id") }, @specific.id
    assert_includes stage.context.fetch("pairs").map { |pair| pair.fetch("statement_id") }, @broad.id
    assert_equal @saved_summary.id, stage.context.fetch("meeting_summary_id")
    match_saved(stage)
    assert_equal 1, @calls.size
    assert_equal 1, stage.reload.requests.count
    get member_path(@jordan)
    assert_select "[data-campaign-actions-for=?] [data-campaign-issue-evidence=action]", @specific.id, count: 1
    assert_select "#campaign-record blockquote", text: @proposal
    get member_path(@taylor)
    assert_select "#campaign-record [data-campaign-issue-evidence]", count: 0
    @saved_summary.update!(generation_data: @saved_summary.generation_data.deep_merge("headline" => "A different recap headline"))
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Unchanged action evidence must reuse its comparison" }) do
      assert_no_difference [ "CampaignActionReview.count", "CampaignActionRequest.count", "CouncilAiReservation.count", "Vote.count" ] do
        2.times { MatchCampaignIssueEvidenceJob.perform_now }
        get member_path(@jordan)
        assert_select "[data-campaign-actions-for=?] [data-campaign-issue-evidence=action]", @specific.id, count: 1
        data = @saved_summary.generation_data.deep_dup
        data.fetch("item_details").first.fetch("motion")["mover"] = nil
        @saved_summary.update!(generation_data: data)
        get member_path(@jordan)
        assert_select "#campaign-record [data-campaign-issue-evidence]", count: 0
        assert_equal "completed", stage.reload.status
      end
    end
  end

  test "removed saved attribution cannot dispatch an old prepared comparison or remain on the profile" do
    stage = prepare_matches
    get member_path(@jordan)
    assert_select "#recorded-actions blockquote", text: @proposal
    data = @saved_summary.generation_data.deep_dup
    data.fetch("item_details").first.fetch("motion")["mover"] = nil
    @saved_summary.update!(generation_data: data)
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Removed evidence cannot dispatch" }) do
      assert_no_difference [ "CampaignActionRequest.count", "CouncilAiReservation.count" ] do
        Campaigns::MatchActions.call(stage, budget_run: campaign_budget(stage: stage))
        assert_equal 0, stage.reload.attempts
        get member_path(@jordan)
        assert_select "#recorded-actions", count: 0
      end
    end
  end

  test "service dates and generated-content access apply after proving the saved action" do
    get member_path(@jordan)
    assert_select "#recorded-actions blockquote", text: @proposal
    @period.update!(ended_on: "2025-06-15", end_source_version: @service_source, end_page: 5)
    get member_path(@jordan)
    assert_select "#recorded-actions", count: 0
    @period.update!(ended_on: nil, end_source_version: nil, end_page: nil)
    get member_path(@jordan)
    assert_select "#recorded-actions", count: 1
    SiteSetting.instance.update!(access_mode: "gated")
    get member_path(@jordan)
    assert_select "#recorded-actions", count: 0
    assert_not_includes response.body, @proposal
  end

  test "missing budgets hold and live matching still needs an explicit minutes source scope" do
    stage = prepare_matches
    Ai::OpenAiService.stub(:new, ->(*) { flunk "No allowance" }) { Campaigns::MatchActions.call(stage) }
    assert_equal "budget_paused", stage.reload.status
    assert_equal 0, stage.attempts
    assert_empty stage.requests
    month = CouncilAiBudgetMonth.new(live_actions: { "starting_on" => "2024-04-01" })
    assert_nil CouncilProfiles::LiveBudget.policy_for(stage, month)
    month.live_actions["issue_sources"] = { "committee_ids" => [ @council.id ], "document_types" => [ "minutes_pdf" ], "starting_on" => "2025-06-01" }
    assert_equal "2025-06-01", CouncilProfiles::LiveBudget.policy_for(stage, month).fetch("starting_on")
    clear_enqueued_jobs
    assert_enqueued_with(job: MatchCampaignIssueEvidenceJob) { ReconcileCampaignSourcesJob.perform_now }
  end

  private

  def saved_item(title, member, quote)
    item = @meeting.agenda_items.create!(title: title, kind: "item")
    item.topics << @water
    { "agenda_item_id" => item.id, "agenda_item_title" => title, "summary" => "The council considered #{title.downcase}.",
      "activity_level" => "decision", "motion" => { "mover" => member.name }, "motion_evidence" => { "mover" => quote },
      "citations" => [ { "source_id" => "doc-#{@saved_document.id}", "location" => { "kind" => "whole_source" } } ] }
  end

  def prepare_matches
    groups = Campaigns::IssueEvidenceCandidates.all.group_by { |candidate| candidate.fetch(:review) }
    assert_equal 1, groups.size
    source, candidates = groups.first
    assert_instance_of CouncilProfiles::SavedMotionEvidence, source
    Campaigns::IssueEvidenceInput.prepare(source, candidates: candidates).sole
  end

  def match_saved(stage)
    result = { matches: stage.context.fetch("pairs").map do |pair|
      direct = pair.fetch("statement_id") == @specific.id && pair.dig("evidence", "quote") == @proposal
      { key: pair.fetch("key"), status: direct ? "direct" : "not_direct",
        reason: direct ? "The motion concerns the promised owner-occupancy rule; it did not receive a second." : "This is not evidence of the specific promise.",
        source_quote: direct ? @proposal : nil }
    end }
    with_campaign_transport(content: result.to_json) do
      MatchCampaignIssueEvidenceJob.perform_now(budget_run_id: campaign_budget(stage: stage).id)
    end
  end
end
