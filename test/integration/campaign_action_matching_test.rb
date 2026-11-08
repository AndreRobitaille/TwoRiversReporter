require "test_helper"
require_relative "../support/campaign_action_scenario"

class CampaignActionMatchingTest < ActionDispatch::IntegrationTest
  include CampaignActionScenario

  test "shared matching publishes a specific action without turning a losing vote into a broken promise" do
    setup_campaign_actions
    stage = review_campaign_actions
    assert_equal "completed", stage.status
    assert_equal 6, stage.context.fetch("pairs").size
    assert_equal 6, stage.data.fetch("matches").size
    assert_equal 1, @calls.size
    assert_equal "received", stage.requests.sole.status
    assert_equal 1, stage.requests.sole.council_ai_reservation.council_ai_budget_run.reservations.count
    assert_equal [ @specific.id, @broad.id ].sort, (stage.context.fetch("pairs").map { |pair| pair["statement_id"] }.uniq & [ @specific.id, @broad.id ]).sort

    Ai::OpenAiService.stub(:new, ->(*) { flunk "Saved comparisons must not generate on reads or replay" }) do
      get member_path(@jordan)
      assert_response :success
      assert_select "[data-campaign-actions-for=?]", @specific.id do
        assert_select "[data-campaign-action=?]", @vote.id
        assert_select ".member-campaign-vote-results", text: /Voted yes.*Council: Failed/m
        assert_select "blockquote", text: @quote
        assert_select "a[href=?]", meeting_path(@vote.motion.meeting)
      end
      assert_select "#campaign-record [data-campaign-action]", count: 1
      assert_select "#campaign-record", text: /#{Regexp.escape(@fee.description)}/, count: 0
      get member_path(@taylor)
      assert_select "#campaign-record", text: /Be proactive about Airbnb concerns/
      assert_select "#campaign-record [data-campaign-action]", count: 0
      assert_no_difference [ "CampaignActionReview.count", "CampaignActionRequest.count", "CouncilAiReservation.count" ] do
        MatchCampaignActionsJob.perform_now
        ReconcileCampaignSourcesJob.perform_now
        perform_enqueued_jobs(only: MatchCampaignActionsJob)
        get member_path(@jordan)
        assert_select "#campaign-record [data-campaign-action]", count: 1
      end
    end
  end

  test "only new pairs are prepared and no provider runs before an explicit allowance" do
    setup_campaign_actions
    first = review_campaign_actions
    motion = @vote.motion.meeting.motions.create!(agenda_item: @vote.motion.agenda_item,
      description: "Table a proposed rental lottery", outcome: "passed")
    [ @jordan, @taylor ].each { |member| motion.votes.create!(member: member, value: "yes") }
    Ai::OpenAiService.stub(:new, ->(*) { flunk "New evidence is not authorization to spend" }) do
      MatchCampaignActionsJob.perform_now(@vote.motion.meeting_id)
    end
    added = CampaignActionReview.where.not(id: first.id).sole
    assert_equal "budget_paused", added.status
    assert_equal 0, added.attempts
    assert_empty added.requests
    assert_equal [ motion.id ], added.context.fetch("pairs").map { |pair| pair.fetch("motion_id") }.uniq
    assert_empty added.context.fetch("pairs").map { |pair| pair.fetch("key") } & first.context.fetch("pairs").map { |pair| pair.fetch("key") }
    budget = campaign_budget(stage: added)
    with_campaign_transport(content: action_response(added).to_json) do
      MatchCampaignActionsJob.perform_now(@vote.motion.meeting_id, budget_run_id: budget.id)
    end
    assert_equal "completed", added.reload.status
    assert_equal 2, @calls.size
  end

  test "incomplete and invented evidence cannot publish and retries are bounded" do
    setup_campaign_actions
    stage = Campaigns::MatchActions.prepare(@vote.motion.meeting).sole
    budget = campaign_budget(stage: stage)
    response = action_response(stage)
    response.fetch("matches").find { |match| match["status"] == "direct" }["minutes_quote"] = "The Council adopted an invented owner-occupancy policy."
    with_campaign_transport(content: response.to_json) { Campaigns::MatchActions.call(stage, budget_run: budget) }
    assert_equal "failed", stage.reload.status
    get member_path(@jordan)
    assert_select "[data-campaign-action]", count: 0
    response = action_response(stage)
    response.fetch("matches").pop
    with_campaign_transport(content: response.to_json) { Campaigns::MatchActions.call(stage, budget_run: budget) }
    assert_equal "failed", stage.reload.status
    assert_equal 2, stage.attempts
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Retry ceiling must hold" }) do
      Campaigns::MatchActions.call(stage, budget_run: budget)
    end
    assert_equal 2, stage.requests.count
    assert_equal 2, @calls.size
  end

  test "current source eligibility and access checks remove stale matches on the next request" do
    setup_campaign_actions
    review_campaign_actions
    get member_path(@jordan)
    assert_select "#campaign-record [data-campaign-action]", count: 1
    @document.update!(extracted_text: @document.extracted_text + "\nCorrection: the recorded motion wording was incorrect.")
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Source edits must not generate on reads" }) do
      get member_path(@jordan)
      assert_select "#campaign-record [data-campaign-action]", count: 0
    end
    @document.update!(extracted_text: @quote + "\nThe license fee increase passed unanimously.")
    get member_path(@jordan)
    assert_select "#campaign-record [data-campaign-action]", count: 1
    @specific.update!(status: "unresolved", exception: "unresolved_source_passage")
    get member_path(@jordan)
    assert_select "#campaign-record [data-campaign-action]", count: 0
    @specific.update!(status: "accepted", exception: nil)
    SiteSetting.delete_all
    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    sign_in_as(User.create!(email_address: "campaign-actions-reader@example.test", status: "active"))
    get member_path(@jordan)
    assert_select "#campaign-record [data-campaign-action]", count: 1
    delete public_session_path
    get member_path(@jordan)
    assert_select "#campaign-record", count: 0
    assert_not_includes response.body, @quote
    assert_not_includes response.body, "This motion proposed the same owner-occupancy requirement"
  end

  test "metadata corrections reuse comparisons for the newly published statement identities" do
    setup_campaign_actions
    review_campaign_actions
    previous_id = @specific.id
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Metadata-only corrections must not repeat semantic analysis" }) do
      @source.update!(publisher: "Corrected newspaper name")
      ExtractCampaignSourceJob.perform_now(@source.id)
      MatchCampaignTopicsJob.perform_now(@source.id)
      current = @source.reload.current_version.extraction.campaign_statements.find_by!(member: @jordan)
      assert_not_equal previous_id, current.id
      assert_no_difference [ "CampaignActionReview.count", "CampaignActionRequest.count" ] do
        MatchCampaignActionsJob.perform_now
        get member_path(@jordan)
        assert_select "[data-campaign-actions-for=?] [data-campaign-action]", current.id, count: 1
      end
    end
    assert_equal 1, @calls.size
  end

  test "rebuilding vote projections preserves semantic matches and shows the current recorded vote" do
    setup_campaign_actions
    stage = review_campaign_actions
    raw = stage.attributes.slice("context", "data", "parameters")
    motion = @vote.motion
    attributes = motion.attributes.except("id", "created_at", "updated_at")
    ballots = motion.votes.map { |vote| vote.attributes.except("id", "motion_id", "created_at", "updated_at") }
    old_id = motion.id
    motion.destroy!
    replacement = Motion.create!(attributes)
    ballots.each { |ballot| replacement.votes.create!(ballot) }
    assert_not_equal old_id, replacement.id
    current_vote = replacement.votes.find_by!(member: @jordan)
    current_vote.update!(value: "recused")
    Ai::OpenAiService.stub(:new, ->(*) { flunk "A projection rebuild must reuse completed semantic evidence" }) do
      assert_no_difference [ "CampaignActionReview.count", "CampaignActionRequest.count" ] do
        MatchCampaignActionsJob.perform_now
        get member_path(@jordan)
        assert_select "[data-campaign-actions-for=?] [data-campaign-action=?]", @specific.id, current_vote.id
        assert_select "#campaign-record .member-campaign-vote-results", text: /Recused/
      end
    end
    assert_equal raw, stage.reload.attributes.slice("context", "data", "parameters")
  end

  test "a contrary decision can be comparable without an automatic promise grade" do
    setup_campaign_actions
    @vote.motion.update!(description: "Remove the requirement that rental owners reside at the property")
    @quote = "Motion to remove the requirement that rental owners reside at the property passed. Jordan voted yes; Taylor voted no."
    @document.update!(extracted_text: @quote)
    @vote.motion.update!(outcome: "passed")
    stage = Campaigns::MatchActions.prepare(@vote.motion.meeting).sole
    response = action_response(stage)
    response.fetch("matches").find { |match| match["status"] == "direct" }["reason"] =
      "The motion removes the residency condition that the campaign statement supported."
    budget = campaign_budget(stage: stage)
    with_campaign_transport(content: response.to_json) { Campaigns::MatchActions.call(stage, budget_run: budget) }
    get member_path(@jordan)
    assert_select "[data-campaign-actions-for=?]", @specific.id do
      assert_select "p", text: "The motion removes the residency condition that the campaign statement supported."
      assert_select ".member-campaign-vote-results", text: /Voted yes.*Council: Passed/m
    end
  end

  test "a multi-issue statement displays a decision only under its relevant issue including merged topic rows" do
    setup_campaign_actions(multiple_issues: true)
    @vote.motion.agenda_item.topics = [ @related ]
    review_campaign_actions
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Issue placement must not generate" }) do
      get member_path(@jordan)
      assert_select "[data-campaign-topic=?] [data-campaign-action=?]", @water.id, @vote.id
      assert_select "[data-campaign-topic=?]", @other_issue.id do
        assert_select "[data-campaign-action]", count: 0
      end
      assert_select "#campaign-record [data-campaign-action]", count: 1
    end
  end
end
