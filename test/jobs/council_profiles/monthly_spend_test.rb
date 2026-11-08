require "test_helper"
require_relative "../../support/council_spend_scenario"

class CouncilProfilesMonthlySpendTest < ActiveJob::TestCase
  include CouncilSpendScenario

  setup { setup_spend_scenario }

  test "another day cannot replenish the monthly allowance and cached work stays free" do
    travel_to Date.current.beginning_of_month.to_time.change(hour: 12) do
      run = budget_run(month_limit: 4_100)
      with_transport { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: run.id) }
      assert_equal 1, @calls.size
      assert_equal "completed", @meeting.minutes_extractions.sole.status
      assert_equal 4_100, CouncilAiBudgetMonth.sole.reserved_microusd
    end
    travel_to (Date.current.beginning_of_month + 1).to_time.change(hour: 12) do
      next_run = budget_run
      with_transport do
        CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "attendance", budget_run_id: next_run.id)
        ExtractVotesJob.perform_now(@meeting.id)
        ExtractCommitteeMembersJob.perform_now(@meeting.id)
      end
      assert_equal 1, @calls.size
      assert_held "attendance", "monthly_budget_limit"
      assert_equal 0, next_run.reservations.count
      assert_equal 0, next_run.council_ai_budget_day.reserved_microusd
      assert_equal 4_100, CouncilAiBudgetMonth.sole.reserved_microusd
      assert_equal 1, MinutesRequest.count
      assert @document.reload.file.attached?
    end
  end

  test "missing and revoked months hold paid work without losing attempts" do
    run = budget_run
    month = CouncilAiBudgetMonth.sole
    attributes = month.attributes.except("id", "created_at", "updated_at")
    month.delete # Simulate an existing installation without monthly authorization.
    with_transport do
      CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: run.id)
      ExtractVotesJob.perform_now(@meeting.id)
    end
    assert_empty @calls
    assert_held "votes", "missing_monthly_budget"
    assert_equal 0, MinutesRequest.count
    assert_equal 0, CouncilAiReservation.count
    month = CouncilAiBudgetMonth.create!(attributes)
    with_transport { ExtractVotesJob.perform_now(@meeting.id) }
    assert_equal 1, @calls.size
    month.update!(revoked_at: Time.current)
    with_transport do
      ExtractVotesJob.perform_now(@meeting.id)
      CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "attendance")
    end
    assert_equal 1, @calls.size
    assert_held "attendance", "monthly_budget_revoked"
    assert_equal 4_100, month.reserved_microusd
  end

  test "a new calendar month needs its own explicit allowance" do
    run = budget_run
    with_transport { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: run.id) }
    travel_to Date.current.next_month.beginning_of_month.to_time.change(hour: 12) do
      day = CouncilAiBudgetDay.create!(budget_on: Date.current, limit_microusd: 100_000, actor: @actor,
        authorized_at: Time.current, authorization_basis: "Synthetic next-day allowance without a month")
      next_run = CouncilAiBudgetRun.create!(run.attributes.except("id", "created_at", "updated_at")
        .merge(council_ai_budget_day_id: day.id, authorized_at: Time.current, expires_at: 1.hour.from_now))
      with_transport { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "attendance", budget_run_id: next_run.id) }
      assert_held "attendance", "missing_monthly_budget"
      assert_equal 1, @calls.size
      assert_equal 1, CouncilAiBudgetMonth.count
      assert_equal 4_100, CouncilAiBudgetMonth.sole.reserved_microusd
    end
  end

  test "monthly authorization cannot be duplicated increased or restored after revocation" do
    budget_run
    month = CouncilAiBudgetMonth.sole
    assert_not month.update(limit_microusd: 2_000_000)
    assert_not month.reload.update(budget_month: month.budget_month.next_month)
    attributes = month.reload.attributes.except("id", "created_at", "updated_at")
    assert_not CouncilAiBudgetMonth.new(attributes).valid?
    assert_not CouncilAiBudgetMonth.new(attributes.merge(budget_month: month.budget_month + 1)).valid?
    reader = User.create!(email_address: "monthly-reader@example.test", status: "active")
    assert_not CouncilAiBudgetMonth.new(attributes.merge(budget_month: month.budget_month.next_month, actor: reader)).valid?
    month.update!(revoked_at: Time.current)
    assert_not month.update(revoked_at: nil)
    assert_not month.reload.destroy
  end

  test "read-only report separates retained ceilings from known usage and uncertain requests" do
    report = CouncilProfiles::SpendReport.call
    assert_equal "missing", report[:authorization]
    assert_equal 0, CouncilAiBudgetMonth.count
    run = budget_run
    with_transport { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: run.id) }
    with_transport(response: ->(*) { raise Timeout::Error, "synthetic unknown bill" }) do
      CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "attendance")
    end
    month = CouncilAiBudgetMonth.sole
    month.update!(revoked_at: Time.current)
    2.times do
      report = CouncilProfiles::SpendReport.call
      assert_equal "revoked", report[:authorization]
      assert_equal 8_200, report[:reserved_microusd]
      assert_equal month.limit_microusd - 8_200, report[:remaining_microusd]
      assert_equal({ requests: 2, reserved_microusd: 8_200, unfinished_requests: 1,
        requests_without_usage: 1, usage_at_reserved_rates_microusd: 150 }, report[:stages].fetch("minutes"))
      assert_not_includes report.to_json, "FINAL BUDGET ACTION"
    end
    assert_equal 2, @calls.size
    assert_equal 2, CouncilAiReservation.count
    assert_equal "missing", CouncilProfiles::SpendReport.call(date: Date.current.next_month)[:authorization]
  end
end
