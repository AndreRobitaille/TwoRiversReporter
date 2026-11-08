require "test_helper"
require_relative "../support/campaign_action_scenario"

class CouncilLiveActionBudgetTest < ActionDispatch::IntegrationTest
  include CampaignActionScenario

  setup do
    travel_to(Time.zone.local(2026, 10, 15, 20)) { setup_campaign_actions }
    travel_to Time.zone.local(2026, 11, 8, 20)
    @vote.motion.meeting.update!(starts_at: Time.zone.local(2026, 11, 8, 18))
    @stage = Campaigns::MatchActions.prepare(@vote.motion.meeting).sole
    @actor = User.find_by!(email_address: "synthetic-campaign-budget@example.test")
    @estimate = Campaigns::CostPreflight.for_stage(@stage)
  end

  test "one explicit monthly policy admits new shared comparisons and unchanged nightly replay is free" do
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Missing live policy cannot authorize generation" }) do
      MatchCampaignActionsJob.perform_now(@vote.motion.meeting_id)
    end
    assert_equal "budget_paused", @stage.reload.status
    assert_equal 0, @stage.attempts
    assert_nil CouncilAiBudgetDay.find_by(budget_on: Date.current)
    month = authorize_live
    with_live_transport { MatchCampaignActionsJob.perform_now(@vote.motion.meeting_id) }
    assert_equal "completed", @stage.reload.status
    assert_equal 1, @calls.size
    assert_equal 6, @stage.data.fetch("matches").size
    assert_equal month.id, @stage.council_ai_budget_run.live_budget_month_id
    assert_equal @estimate.fetch(:cost_microusd), month.reserved_microusd
    assert_equal @estimate.fetch(:request_digest), @stage.council_ai_budget_run.request_estimates.sole.fetch("request_digest")
    get member_path(@jordan)
    assert_select "[data-campaign-action=?]", @vote.id
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Unchanged replay and rendering must reuse the shared comparison" }) do
      assert_no_difference [ "CouncilAiBudgetRun.count", "CouncilAiReservation.count", "CampaignActionRequest.count" ] do
        2.times do
          MatchCampaignActionsJob.perform_now
          ReconcileCampaignSourcesJob.perform_now
          perform_enqueued_jobs(only: MatchCampaignActionsJob)
          get member_path(@jordan)
          assert_select "[data-campaign-action=?]", @vote.id
          get member_path(@taylor)
          assert_response :success
        end
      end
    end
  end

  test "automatic daily runs cannot replenish a month or authorize the historical backfill" do
    month = authorize_live(limit: @estimate.fetch(:cost_microusd))
    with_live_transport { MatchCampaignActionsJob.perform_now(@vote.motion.meeting_id) }
    assert_equal 1, @calls.size
    old = new_action_meeting(Date.new(2025, 7, 7))
    with_live_transport { MatchCampaignActionsJob.perform_now(old.id) }
    old_stage = CampaignActionReview.where(meeting: old).sole
    assert_equal "outside_live_meeting_window", old_stage.error_code
    assert_equal 0, old_stage.attempts
    assert_nil old_stage.council_ai_budget_run_id
    travel_to Time.zone.local(2026, 11, 9, 20)
    meeting = new_action_meeting(Date.current)
    with_live_transport { MatchCampaignActionsJob.perform_now(meeting.id) }
    stage = CampaignActionReview.where(meeting: meeting).sole
    assert_equal 1, @calls.size
    assert_equal "monthly_budget_limit", stage.error_code
    assert_equal 0, stage.attempts
    assert_empty stage.requests
    assert_equal @estimate.fetch(:cost_microusd), month.reserved_microusd
    travel_to Time.zone.local(2026, 12, 1, 20)
    meeting = new_action_meeting(Date.current)
    with_live_transport { MatchCampaignActionsJob.perform_now(meeting.id) }
    assert_equal "missing_budget", CampaignActionReview.where(meeting: meeting).sole.error_code
    assert_nil CouncilAiBudgetMonth.find_by(budget_month: Date.current)
    assert_equal 1, @calls.size
  end

  test "daily counts retry limits uncertain transport and revoked runs stay bounded" do
    month = authorize_live(policy: { "max_requests_per_day" => 1 })
    with_live_transport(content: "not JSON") { MatchCampaignActionsJob.perform_now(@vote.motion.meeting_id) }
    assert_equal "failed", @stage.reload.status
    assert_equal 1, @stage.attempts
    with_live_transport { MatchCampaignActionsJob.perform_now(@vote.motion.meeting_id) }
    assert_equal "live_daily_request_limit", @stage.reload.error_code
    assert_equal 1, @stage.attempts
    assert_equal 1, @calls.size
    travel_to Time.zone.local(2026, 11, 9, 20)
    with_live_transport(content: "still invalid") { MatchCampaignActionsJob.perform_now(@vote.motion.meeting_id) }
    assert_equal 2, @stage.reload.attempts
    assert_equal 2, @calls.size
    with_live_transport { MatchCampaignActionsJob.perform_now(@vote.motion.meeting_id) }
    assert_equal 2, @calls.size
    travel_to Time.zone.local(2026, 11, 10, 20)
    meeting = new_action_meeting(Date.current)
    with_live_transport(error: Timeout::Error.new("Synthetic uncertain transport")) do
      assert_raises(Timeout::Error) { MatchCampaignActionsJob.perform_now(meeting.id) }
    end
    uncertain = CampaignActionReview.where(meeting: meeting).sole
    assert_equal "uncertain", uncertain.status
    assert_nil uncertain.requests.sole.council_ai_reservation.finished_at
    travel_to Time.zone.local(2026, 11, 11, 20)
    later = new_action_meeting(Date.current)
    with_live_transport { MatchCampaignActionsJob.perform_now(later.id) }
    stage = CampaignActionReview.where(meeting: later).sole
    assert_equal "live_concurrency_limit", stage.error_code
    assert_equal 0, stage.attempts
    stage.council_ai_budget_run.update!(revoked_at: Time.current)
    with_live_transport { MatchCampaignActionsJob.perform_now(later.id) }
    assert_equal "live_run_revoked", stage.reload.error_code
    assert_equal 3, @calls.size
    assert_equal 3, month.reservations.count
  end

  test "model input limits stale pricing and monthly revocation hold before any provider transport" do
    month = authorize_live(policy: { "max_input_tokens" => 1 })
    with_live_transport { MatchCampaignActionsJob.perform_now(@vote.motion.meeting_id) }
    assert_equal "live_request_limit", @stage.reload.error_code
    assert_equal 0, @stage.attempts
    assert_nil @stage.council_ai_budget_run_id
    travel_to Time.zone.local(2026, 11, 22, 20)
    with_live_transport { MatchCampaignActionsJob.perform_now(@vote.motion.meeting_id) }
    assert_equal "live_estimate_unavailable", @stage.reload.error_code
    month.update!(revoked_at: Time.current)
    with_live_transport { MatchCampaignActionsJob.perform_now(@vote.motion.meeting_id) }
    assert_equal "monthly_budget_revoked", @stage.reload.error_code
    assert_equal 0, @stage.attempts
    assert_empty @calls
    assert_equal 0, month.reservations.count
  end

  test "policy renewal retains the live window but cannot widen it into history" do
    assert_raises(ActiveRecord::RecordInvalid) { authorize_live(policy: { "starting_on" => "2024-04-01" }) }
    month = authorize_live
    assert_not month.update(live_actions: month.live_actions.merge("starting_on" => "2024-04-01"))
    month.reload
    travel_to Time.zone.local(2026, 12, 1, 20)
    renewal = authorize_live(policy: { "starting_on" => "2026-11-08" })
    assert_equal "2026-11-08", renewal.live_actions.fetch("starting_on")
    assert_equal 0, renewal.reserved_microusd
    assert_empty @calls
  end

  private

  def authorize_live(limit: 5_000_000, policy: {})
    CouncilAiBudgetMonth.create!(budget_month: Date.current.beginning_of_month, limit_microusd: limit,
      actor: @actor, authorized_at: Time.current, authorization_basis: "Synthetic live policy only",
      live_actions: { "starting_on" => Date.current.iso8601, "estimate_method" => "utf8_bytes_plus_1024",
        "model" => @stage.parameters.fetch("model"), "daily_limit_microusd" => 1_000_000,
        "request_limit_microusd" => 500_000, "max_requests_per_day" => 10, "max_concurrent" => 1,
        "max_input_tokens" => 200_000, "max_output_tokens" => 8_000 }.merge(policy))
  end

  def new_action_meeting(date)
    vote = activity_vote(date: date, description: "Consider rental inspection changes", value: "yes", peer_value: "yes", agenda_title: "Short-term rental rules")
    vote.motion.meeting.meeting_documents.create!(document_type: "minutes_pdf",
      source_url: "https://example.test/live-minutes-#{date}.pdf", extracted_text: "The Council considered rental inspection changes.")
    vote.motion.meeting
  end

  def with_live_transport(content: nil, error: nil, &block)
    calls = @calls
    response_for = ->(parameters) { content || action_response(CampaignActionReview.find_by!(parameters: parameters)).to_json }
    client = Object.new
    client.define_singleton_method(:chat) do |parameters:|
      calls << parameters
      raise error if error
      { "id" => "synthetic-live-response", "model" => parameters.fetch(:model),
        "choices" => [ { "message" => { "content" => response_for.call(parameters) }, "finish_reason" => "stop" } ],
        "usage" => { "prompt_tokens" => 100, "completion_tokens" => 100, "total_tokens" => 200 } }
    end
    OpenAI::Client.stub(:new, client, &block)
  end
end
