require "test_helper"
require "timeout"

class CouncilProfilesParallelLiveActionBudgetTest < ActiveJob::TestCase
  self.use_transactional_tests = false

  test "concurrent automatic runs share the same final monthly allowance" do
    travel_to Time.zone.local(2026, 11, 8, 20)
    actor = User.create!(email_address: "parallel-live-#{SecureRandom.hex(4)}@example.test", admin: true, status: "active")
    meeting = Meeting.create!(body_name: "Synthetic Council", starts_at: 1.hour.ago, detail_page_url: "https://example.test/live-budget-parallel")
    stages = 2.times.map do |n|
      parameters = Ai::OpenAiService.build_chat_parameters(model: "gpt-5.6-terra",
        messages: [ { role: "user", content: "Synthetic source #{n}" } ], response_format: { type: "json_object" })
        .merge(max_completion_tokens: 200)
      CampaignActionReview.create!(meeting: meeting, input_key: CouncilProfiles::ReserveAiSpend.request_digest(parameters),
        parameters: parameters, context: { pairs: [], minutes: "Synthetic source #{n}" })
    end
    amount = Campaigns::CostPreflight.for_stage(stages.first).fetch(:cost_microusd)
    month = CouncilAiBudgetMonth.create!(budget_month: Date.current.beginning_of_month, limit_microusd: amount,
      actor: actor, authorized_at: Time.current, authorization_basis: "Synthetic concurrency policy",
      live_actions: { "starting_on" => Date.current.iso8601, "estimate_method" => "utf8_bytes_plus_1024", "model" => "gpt-5.6-terra",
        "daily_limit_microusd" => amount * 3, "request_limit_microusd" => amount * 2,
        "max_requests_per_day" => 4, "max_concurrent" => 2, "max_input_tokens" => 10_000, "max_output_tokens" => 200 })
    entered, release, second_pid = Queue.new, Queue.new, Queue.new
    pause = -> { entered << :reserved; release.pop }
    CouncilAiReservation.set_callback(:create, :before, pause)
    calls = []
    client = Object.new
    client.define_singleton_method(:chat) do |parameters:|
      calls << parameters
      { "choices" => [ { "finish_reason" => "stop", "message" => { "content" => { matches: [] }.to_json } } ],
        "usage" => { "prompt_tokens" => 20, "completion_tokens" => 20, "total_tokens" => 40 } }
    end
    workers = []
    OpenAI::Client.stub(:new, client) do
      Timeout.timeout(15) do
        workers << Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            result = Campaigns::MatchActions.call(CampaignActionReview.find(stages.first.id))
            entered << result.error_code
          end
        end
        assert_equal :reserved, entered.pop
        workers << Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            second_pid << connection.select_value("SELECT pg_backend_pid()")
            Campaigns::MatchActions.call(CampaignActionReview.find(stages.last.id))
          end
        end
        pid = Integer(second_pid.pop)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
        waiting = false
        until waiting || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          waiting = ActiveRecord::Base.uncached { ActiveRecord::Base.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{pid}") == "Lock" }
          sleep 0.01 unless waiting
        end
        assert waiting, "The competing automatic grant must wait on the monthly lock"
        release << true
        workers.each(&:value)
      end
    end
    assert_equal 1, calls.size
    assert_equal amount, month.reserved_microusd
    assert_equal "completed", stages.first.reload.status
    assert_equal "monthly_budget_limit", stages.last.reload.error_code
    assert_equal 0, stages.last.attempts
    assert_equal 1, CampaignActionRequest.where(campaign_action_review: stages).count
  ensure
    release << true if release
    workers&.each { |worker| worker.join(15) }
    CouncilAiReservation.skip_callback(:create, :before, pause) if pause
    if month
      runs = CouncilAiBudgetRun.where(live_budget_month: month)
      days = runs.pluck(:council_ai_budget_day_id)
      CampaignActionRequest.where(campaign_action_review: stages).delete_all
      CampaignActionReview.where(id: stages).delete_all
      CouncilAiReservation.where(council_ai_budget_run: runs).delete_all
      runs.delete_all
      CouncilAiBudgetDay.where(id: days).delete_all
      month.delete
    end
    meeting&.destroy!
    actor&.delete
  end
end
