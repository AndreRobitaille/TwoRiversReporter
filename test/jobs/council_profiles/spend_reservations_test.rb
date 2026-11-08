require "test_helper"
require "minitest/mock"
require "open-uri"
require_relative "../../support/council_spend_scenario"

class CouncilProfilesSpendReservationsTest < ActiveJob::TestCase
  include CouncilSpendScenario

  setup { setup_spend_scenario }

  test "missing authorization holds council work before transport and ordinary replay cannot bypass it" do
    with_transport do
      CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes")
      ExtractVotesJob.perform_now(@meeting.id)
    end
    assert_empty @calls
    stage = @meeting.minutes_extractions.sole
    assert_equal "budget_paused", stage.status
    assert_equal 0, stage.attempts
    assert stage.budget_required?
    assert_equal "missing_budget", stage.error_code
    assert_equal 0, MinutesRequest.count
    assert_nil @meeting.reload.minutes_publication_id
  end

  test "authorized shared work reserves before transport and completed replay costs nothing" do
    run = budget_run
    response = ->(params) do
      receipt = MinutesRequest.order(:id).last
      reservation = receipt.council_ai_reservation
      assert_equal "dispatched", receipt.status
      assert_equal 4_100, reservation.reserved_microusd
      assert_nil reservation.finished_at
      assert_equal CouncilProfiles::ReserveAiSpend.request_digest(params), reservation.request_estimate["request_digest"]
      assert_includes receipt.messages.last["content"], "FINAL BUDGET ACTION"
      provider_response(params)
    end
    with_transport(response: response) do
      CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: run.id)
      CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "attendance")
    end
    assert_equal 2, @calls.size
    assert_equal 8_200, run.reservations.sum(:reserved_microusd)
    assert_equal 8_200, run.council_ai_budget_day.reserved_microusd
    assert_equal 0, run.reservations.where(finished_at: nil).count
    fresh = Meeting.find(@meeting.id)
    assert_equal [ [ "Alex Budget", "no" ], [ "Blair Budget", "yes" ] ],
      fresh.motions.sole.votes.joins(:member).order("members.name").pluck("members.name", :value)
    assert_equal [ "Alex Budget", "Blair Budget" ], fresh.meeting_attendances.joins(:member).order("members.name").pluck("members.name")
    publication_id = fresh.minutes_publication_id
    run.update!(revoked_at: Time.current)
    with_transport do
      CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes")
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
      Scrapers::PipelineRepairSweep.new([ @meeting.id ], parsed_meeting_ids: [ @meeting.id ]).call
    end
    assert_equal 2, @calls.size
    assert_equal 2, CouncilAiReservation.count
    assert_equal publication_id, Meeting.find(@meeting.id).minutes_publication_id
    assert_no_enqueued_jobs only: ExtractVotesJob
    assert_no_enqueued_jobs only: ExtractCommitteeMembersJob
  end

  test "request and run limits pause without consuming an attempt or losing queued source work" do
    request_limited = budget_run(request_limit_microusd: 4_099)
    with_transport { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: request_limited.id) }
    assert_empty @calls
    assert_held "votes", "request_budget_limit"
    assert_equal 0, CouncilAiReservation.count
    permitted = budget_run(limit_microusd: 4_100)
    with_transport do
      CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: permitted.id)
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end
    assert_equal 1, @calls.size
    assert_held "attendance", "run_budget_limit"
    assert_equal 4_100, permitted.reservations.sum(:reserved_microusd)
    assert_equal "completed", @meeting.minutes_extractions.find_by!(kind: "votes").status
    assert @document.reload.file.attached?
    assert_equal "FINAL BUDGET ACTION.", @document.extracted_text.split(". ").last
    clear_enqueued_jobs
    Scrapers::PipelineRepairSweep.new([ @meeting.id ], parsed_meeting_ids: [ @meeting.id ]).call
    assert_enqueued_with job: ExtractCommitteeMembersJob, args: [ @meeting.id ]
    with_transport { ExtractCommitteeMembersJob.perform_now(@meeting.id) }
    assert_equal 1, @calls.size
    assert_held "attendance", "run_budget_limit"
    assert_equal 1, CouncilAiReservation.count
  end

  test "a second run cannot spend the same daily allowance" do
    run = budget_run(day_limit: 4_100)
    with_transport { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: run.id) }
    assert_equal 1, @calls.size
    next_run = budget_run
    with_transport { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "attendance", budget_run_id: next_run.id) }
    assert_equal 1, @calls.size
    assert_held "attendance", "daily_budget_limit"
    assert_equal 4_100, run.council_ai_budget_day.reserved_microusd
    assert_equal 0, next_run.reservations.count
  end

  test "request count and declared token ceilings are enforced before transport" do
    limits = [
      [ { max_input_tokens: 99 }, "input_token_limit" ],
      [ { max_output_tokens: 3_999 }, "output_token_limit" ]
    ]
    limits.each do |attributes, reason|
      run = budget_run(**attributes)
      with_transport { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: run.id) }
      assert_empty @calls
      assert_held "votes", reason
    end
    run = budget_run(max_requests: 1)
    with_transport do
      CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: run.id)
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end
    assert_equal 1, @calls.size
    assert_held "attendance", "request_count_limit"
    assert_equal 1, run.reservations.count
  end

  test "changed source or prompt cannot borrow an approved estimate and retains the budget requirement" do
    run = budget_run
    with_transport { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: run.id) }
    assert_equal 1, @calls.size
    PromptTemplate.find_by!(key: "extract_committee_members").update!(instructions: "Changed JSON prompt {{text}}")
    with_transport { ExtractCommitteeMembersJob.perform_now(@meeting.id) }
    assert_held "attendance", "missing_request_estimate"
    Documents::PublishText.new(@document.reload).call(raw_pages: [ "Changed budget source." ],
      page_count: 1, quality: "text", extractor_version: "synthetic_v2")
    with_transport { ExtractVotesJob.perform_now(@meeting.id) }
    stage = @meeting.minutes_extractions.where(kind: "votes").order(:id).last
    assert_equal "budget_paused", stage.status
    assert_equal "missing_request_estimate", stage.error_code
    assert stage.budget_required?
    assert_equal 1, @calls.size
    assert_equal 4_100, run.reservations.sum(:reserved_microusd)
  end

  test "uncertain outcomes retain both reserved money and the in-flight slot" do
    run = budget_run
    with_transport(response: ->(*) { raise Timeout::Error, "synthetic unknown bill" }) do
      CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: run.id)
    end
    assert_equal 1, @calls.size
    assert_equal "uncertain", @meeting.minutes_extractions.find_by!(kind: "votes").status
    assert_equal 4_100, run.reservations.sum(:reserved_microusd)
    assert_nil run.reservations.sole.finished_at
    assert_nil MinutesRequest.sole.usage
    with_transport do
      ExtractVotesJob.perform_now(@meeting.id)
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end
    assert_equal 1, @calls.size
    assert_held "attendance", "concurrency_limit"
    assert_equal 1, run.reservations.count
  end

  test "invalid response retries consume separate reservations and limits do not reset attempts" do
    run = budget_run
    malformed = ->(params) { provider_response(params).tap { |r| r["choices"][0]["message"]["content"] = "{" } }
    with_transport(response: malformed) do
      3.times { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: run.id) }
    end
    assert_equal 2, @calls.size
    assert_equal 8_200, run.reservations.sum(:reserved_microusd)
    assert_equal 2, @meeting.minutes_extractions.sole.attempts
    next_run = budget_run
    with_transport { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: next_run.id) }
    assert_equal 2, @calls.size
    assert_equal 0, next_run.reservations.count
    assert_not Minutes::Pipeline.needed?(@meeting.reload, "votes")
  end

  test "receipt failure rolls back reservation before transport" do
    run = budget_run
    fault = -> { raise "synthetic receipt failure" }
    MinutesRequest.set_callback(:create, :before, fault)
    begin
      with_transport { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: run.id) }
    ensure
      MinutesRequest.skip_callback(:create, :before, fault)
    end
    assert_empty @calls
    assert_equal 0, run.reservations.count
    assert_equal 0, MinutesRequest.count
    assert_equal "uncertain", @meeting.minutes_extractions.sole.status
  end

  test "revocation expiration and day rollover cannot silently supply a new allowance" do
    revoked = budget_run
    revoked.update!(revoked_at: Time.current)
    with_transport { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: revoked.id) }
    assert_held "votes", "budget_revoked"
    run = budget_run
    travel_to run.expires_at + 1.second do
      with_transport { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: run.id) }
      assert_held "votes", "budget_expired"
    end
    travel_to Time.current.tomorrow do
      with_transport { ExtractVotesJob.perform_now(@meeting.id) }
      assert_held "votes", "budget_expired"
      assert_equal 1, CouncilAiBudgetDay.count
    end
    assert_empty @calls
    assert_equal 0, CouncilAiReservation.count
  end

  test "request payload binding rejects a changed ceiling or model without consuming money" do
    estimates = prepared_estimates
    estimates.each { |estimate| estimate["request_digest"] = "0" * 64 }
    run = budget_run(request_estimates: estimates)
    with_transport { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: run.id) }
    assert_empty @calls
    assert_held "votes", "missing_request_estimate"
    estimates = prepared_estimates
    estimates.each { |estimate| estimate["estimate_basis"]["model"] = "unpriced-synthetic-model" }
    run = budget_run(request_estimates: estimates)
    with_transport { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: run.id) }
    assert_held "votes", "estimate_model_mismatch"
    assert_empty @calls
    assert_equal 0, CouncilAiReservation.count
  end

  test "fractional micro-dollar estimates round upward at the actual request boundary" do
    estimates = prepared_estimates
    estimates.each do |estimate|
      estimate["input_rate_microusd"] = 1
      estimate["output_rate_microusd"] = 1
    end
    run = budget_run(request_estimates: estimates, request_limit_microusd: 1, limit_microusd: 1)
    with_transport do
      CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: run.id)
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end
    assert_equal 1, @calls.size
    assert_equal 1, run.reservations.sole.reserved_microusd
    assert_held "attendance", "run_budget_limit"
  end

  test "budget authorizations and spending history remain immutable through source and actor removal" do
    run = budget_run
    reader = User.create!(email_address: "budget-reader@example.test", status: "active")
    assert_raises(ActiveRecord::RecordInvalid) { budget_run(actor: reader) }
    assert_not run.update(limit_microusd: run.limit_microusd + 1)
    run.reload
    assert_not run.update(request_estimates: prepared_estimates.take(1))
    run.reload
    day = run.council_ai_budget_day
    assert_not day.update(limit_microusd: day.limit_microusd + 1)
    assert_raises(ActiveRecord::RecordInvalid) do
      CouncilAiBudgetDay.create!(budget_on: day.budget_on, limit_microusd: 999_999, actor: @actor,
        authorized_at: Time.current, authorization_basis: "Attempted duplicate day")
    end
    with_transport { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: run.id) }
    reservation = run.reservations.sole
    original = reservation.attributes
    assert_raises(ActiveRecord::ReadonlyAttributeError) { reservation.update!(reserved_microusd: 0) }
    assert_not reservation.reload.update(finished_at: nil)
    assert_raises(ActiveRecord::DeleteRestrictionError) { reservation.destroy }
    assert_equal original, reservation.reload.attributes
    assert_not @meeting.reload.update(council_ai_budget_required: false)
    stage = @meeting.minutes_extractions.sole
    assert_not stage.update(budget_required: false)
    @meeting.reload.destroy!
    backup = User.create!(email_address: "budget-backup@example.test", admin: true, status: "active")
    backup.passkey_credentials.create!(external_id: SecureRandom.uuid, public_key: "synthetic", sign_count: 0)
    original_actor_id = @actor.id
    @actor.destroy!
    assert_nil run.reload.actor_id
    assert_equal original_actor_id, run.original_actor_id
    assert_equal original_actor_id, day.reload.original_actor_id
    assert_equal original, reservation.reload.attributes
    assert_nil MinutesRequest.sole.minutes_extraction.meeting_id
    require Rails.root.join("db/migrate/20261108060000_add_council_ai_spend_reservations")
    migration = AddCouncilAiSpendReservations.new
    migration.suppress_messages do
      assert_raises(ActiveRecord::IrreversibleMigration) { migration.migrate(:down) }
    end
    assert_equal original, reservation.reload.attributes
  end

  test "process interruption preserves the charge and active reservation until explicit recovery" do
    run = budget_run
    interruption = Class.new(Exception)
    with_transport(response: ->(*) { raise interruption }) do
      assert_raises(interruption) { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: run.id) }
    end
    assert_equal "running", @meeting.minutes_extractions.sole.status
    assert_equal "dispatched", MinutesRequest.sole.status
    assert_nil run.reservations.sole.finished_at
    assert_equal 4_100, run.reservations.sole.reserved_microusd
    with_transport { ExtractCommitteeMembersJob.perform_now(@meeting.id) }
    assert_equal 1, @calls.size
    assert_held "attendance", "concurrency_limit"
  end

  test "completion persistence failure retains the full reservation and blocks another concurrent request" do
    run = budget_run
    fault = -> { raise "synthetic finish failure" if finished_at }
    CouncilAiReservation.set_callback(:update, :before, fault)
    begin
      with_transport { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: run.id) }
    ensure
      CouncilAiReservation.skip_callback(:update, :before, fault)
    end
    assert_equal "uncertain", MinutesRequest.sole.status
    assert_nil run.reservations.sole.finished_at
    assert_equal 4_100, run.reservations.sole.reserved_microusd
    assert_nil @meeting.minutes_extractions.sole.data
    with_transport { ExtractCommitteeMembersJob.perform_now(@meeting.id) }
    assert_equal 1, @calls.size
    assert_held "attendance", "concurrency_limit"
  end

  test "unselected meetings retain existing ingestion and paid holds do not prevent deterministic publication" do
    with_transport do
      ExtractVotesJob.perform_now(@meeting.id)
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end
    assert_equal 2, @calls.size
    assert_equal 0, CouncilAiReservation.count
    assert_equal 2, MinutesRequest.where(council_ai_reservation_id: nil).count
    old_publication = @meeting.reload.minutes_publication
    with_transport { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes") }
    @meeting.reload.update!(starts_at: @meeting.starts_at - 1.day)
    with_transport { ExtractVotesJob.perform_now(@meeting.id) }
    assert_equal 2, @calls.size
    fresh = Meeting.find(@meeting.id).minutes_publication
    assert_not_equal old_publication.id, fresh.id
    assert_equal old_publication.votes_extraction_id, fresh.votes_extraction_id
    assert_equal old_publication.attendance_extraction_id, fresh.attendance_extraction_id
    assert_equal 0, CouncilAiReservation.count
  end
end
