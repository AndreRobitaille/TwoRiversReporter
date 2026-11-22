require "test_helper"

class CouncilHistoryExecutionTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    # The spending reservation must be visible on another connection before the
    # transport starts. The rest of the application suite uses transactions.
    @meeting_id = 234_245
    @parameters = { model: "gpt-5.6-luna", messages: [ { role: "user", content: "Synthetic historical minutes" } ],
      response_format: { type: "json_object" }, max_completion_tokens: 4000 }
    travel_to Time.zone.local(2026, 11, 21, 12)
  end

  teardown { CouncilHistoryRequest.where(meeting_id: @meeting_id).delete_all }

  test "the final historical supplement admits the last reservation up to the approved total" do
    reserve = ->(stage) { CouncilHistoryRequest.reserve!(meeting_id: @meeting_id, stage: stage, pilot: false, parameters: @parameters).first }
    prior = reserve.call("earlier_history")
    prior.update!(charged_microusd: 76_000_000 - prior.reserved_microusd, finished_at: Time.current)

    assert_no_difference("CouncilAiReservation.count") do
      admitted = reserve.call("promise_comparisons")
      assert_equal 76_000_000, prior.charged_microusd + admitted.reload.charged_microusd
      error = assert_raises(CouncilProfiles::ReserveAiSpend::Paused) { reserve.call("topic_summaries") }
      assert_equal "historical_total_limit", error.message
    end
  end

  test "historical comparison links its response to the committed pilot reservation and replays for free" do
    meeting = Meeting.create!(starts_at: Time.zone.local(2024, 10, 28, 18), body_name: "Synthetic Council",
      detail_page_url: "https://example.test/historical-comparison-receipt")
    @meeting_id = meeting.id
    stage = CampaignActionReview.create!(meeting: meeting, input_key: Digest::SHA256.hexdigest("historical comparison receipt"),
      parameters: @parameters, context: { "pairs" => [ { "key" => "item-a" } ], "minutes" => "Vote on a public agreement." })
    match = { "key" => "item-a", "status" => "not_direct", "reason" => "The motion addressed a separate proposal." }
    client = Object.new
    calls = 0
    client.define_singleton_method(:chat) do |parameters:|
      calls += 1
      { "id" => "synthetic-result", "model" => parameters.fetch(:model), "choices" => [
        { "message" => { "content" => { matches: [ match ] }.to_json }, "finish_reason" => "stop" }
      ], "usage" => { "prompt_tokens" => 40, "completion_tokens" => 20 } }
    end

    assert_no_difference("CouncilAiReservation.count") do
      OpenAI::Client.stub(:new, client) do
        CouncilHistory::Execution.set(meeting_id: meeting.id, stage: "promise_comparisons", pilot: true) do
          2.times { Campaigns::MatchActions.call(stage.reload) }
        end
      end
    end
    assert_equal 1, calls
    assert_equal [ match ], stage.reload.data.fetch("matches")
    receipt = stage.requests.sole
    reservation = CouncilHistoryRequest.where(meeting_id: meeting.id, pilot: true).sole
    assert_equal reservation.id, receipt.council_history_request_id
    assert_equal [ "received", "synthetic-result", "synthetic-result" ], [ receipt.status, receipt.provider_response_id, reservation.provider_response_id ]
  ensure
    if stage&.persisted?
      CampaignActionRequest.where(campaign_action_review_id: stage.id).delete_all
      stage.delete
    end
    meeting&.delete
  end

  test "historical transport reserves against both ceilings and retains unknown charges across a retry" do
    service = nil
    called = 0
    client = Object.new
    client.define_singleton_method(:chat) do |parameters:|
      called += 1
      raise IOError, "simulated interruption"
    end
    OpenAI::Client.stub(:new, client) { service = Ai::OpenAiService.new }
    CouncilHistory::Execution.set(meeting_id: @meeting_id, stage: "votes", pilot: true) do
      assert_raises(IOError) { service.evaluate_chat(**@parameters.except(:max_completion_tokens)) }
      receipt = CouncilHistoryRequest.where(meeting_id: @meeting_id).sole
      assert_operator receipt.charged_microusd, :>, 0
      assert_equal receipt.reserved_microusd, receipt.charged_microusd
      assert_nil receipt.finished_at
      error = assert_raises(CouncilProfiles::ReserveAiSpend::Paused) { service.evaluate_chat(**@parameters.except(:max_completion_tokens)) }
      assert_equal "historical_request_uncertain", error.message
      receipt.update!(charged_microusd: CouncilHistoryRequest::PILOT_LIMIT)
      changed = @parameters.merge(messages: [ { role: "user", content: "Changed source" } ])
      error = assert_raises(CouncilProfiles::ReserveAiSpend::Paused) { service.evaluate_chat(**changed.except(:max_completion_tokens)) }
      assert_equal "historical_pilot_limit", error.message
      receipt.update!(charged_microusd: CouncilHistoryRequest::TOTAL_LIMIT)
      CouncilHistory::Execution.set(pilot: false) do
        error = assert_raises(CouncilProfiles::ReserveAiSpend::Paused) { service.evaluate_chat(**changed.except(:max_completion_tokens)) }
        assert_equal "historical_total_limit", error.message
      end
      assert_no_enqueued_jobs { SummarizeMeetingJob.perform_later(@meeting_id) }
      assert_equal 1, called
    end
  end
end
