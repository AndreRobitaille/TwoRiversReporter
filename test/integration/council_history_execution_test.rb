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
