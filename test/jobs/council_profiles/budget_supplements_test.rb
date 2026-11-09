require "test_helper"
require_relative "../../support/council_spend_scenario"

class CouncilProfilesBudgetSupplementsTest < ActiveJob::TestCase
  include CouncilSpendScenario

  setup do
    travel_to Time.zone.local(2026, 11, 8, 12)
    setup_spend_scenario
  end
  teardown { travel_back }

  test "explicit supplement admits held work once and retains original approvals and reservations" do
    run = budget_run(day_limit: 4_100, month_limit: 4_100)
    day = run.council_ai_budget_day
    month = CouncilAiBudgetMonth.sole
    originals = [ day.attributes, month.attributes ]
    with_transport do
      CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: run.id)
      CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "attendance")
    end
    assert_equal 1, @calls.size
    assert_held "attendance", "monthly_budget_limit"
    receipt_id = MinutesRequest.sole.id
    supplement = authorize(day, "catch-up-approval")
    assert_equal supplement, authorize(day, "catch-up-approval")
    assert_equal 1, CouncilAiBudgetSupplement.count
    with_transport { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "attendance") }
    assert_equal 2, @calls.size
    assert_equal 2, @meeting.minutes_extractions.where(status: "completed").count
    assert_equal originals, [ day.reload.attributes, month.reload.attributes ]
    assert_equal 8_200, month.reserved_microusd
    assert_equal 8_200, day.effective_limit_microusd
    assert_equal receipt_id, MinutesRequest.order(:id).first.id
    report = CouncilProfiles::SpendReport.call
    assert_equal 4_100, report[:original_limit_microusd]
    assert_equal 4_100, report[:supplement_microusd]
    assert_equal 8_200, report[:limit_microusd]
    assert_equal 0, report[:remaining_microusd]
    assert_equal({}, month.live_actions)

    # A changed source needs new work; replaying the same approval cannot pay for it.
    Documents::PublishText.new(@document.reload).call(raw_pages: [ "Corrected source: FINAL BUDGET ACTION." ],
      page_count: 1, quality: "text", extractor_version: "synthetic_v2")
    next_run = budget_run
    with_transport { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: next_run.id) }
    assert_held "votes", "monthly_budget_limit"
    assert_equal 2, @calls.size
    assert_equal 8_200, month.reserved_microusd
  end

  test "supplements require an administrator and cannot rewrite an approval or revive a revoked month" do
    run = budget_run
    day = run.council_ai_budget_day
    reader = User.create!(email_address: "supplement-reader@example.test", status: "active")
    assert_raises(ActiveRecord::RecordInvalid) { authorize(day, "reader", actor: reader) }
    supplement = authorize(day, "owner-approval")
    assert_raises(ArgumentError) { authorize(day, "owner-approval", amount_microusd: 8_200) }
    assert_not supplement.update(amount_microusd: 8_200)
    assert_not supplement.reload.destroy
    assert_equal 4_100, supplement.reload.amount_microusd
    month = CouncilAiBudgetMonth.sole
    month.update!(revoked_at: Time.current)
    assert_raises(ActiveRecord::RecordInvalid) { authorize(day, "revoked") }
    with_transport { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: run.id) }
    assert_held "votes", "monthly_budget_revoked"
    assert_empty @calls
  end

  test "supplement only increases the named day and month and does not relax run limits" do
    run = budget_run(day_limit: 4_100, month_limit: 4_100, limit_microusd: 4_100)
    day = run.council_ai_budget_day
    authorize(day, "limited-run")
    with_transport do
      CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: run.id)
      CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "attendance")
    end
    assert_held "attendance", "run_budget_limit"
    assert_equal 1, @calls.size
    travel 1.day do
      assert_raises(ActiveRecord::RecordInvalid) { authorize(day, "wrong-day") }
      next_run = budget_run(day_limit: 4_099)
      assert_equal 4_099, next_run.council_ai_budget_day.effective_limit_microusd
      with_transport { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "attendance", budget_run_id: next_run.id) }
      assert_held "attendance", "daily_budget_limit"
      assert_equal 1, @calls.size
    end
  end

  private

  def authorize(day, key, actor: @actor, amount_microusd: 4_100)
    CouncilAiBudgetSupplement.authorize!(day: day, actor: actor, amount_microusd: amount_microusd,
      authorization_key: key, authorization_basis: "Explicit synthetic test approval")
  end
end
