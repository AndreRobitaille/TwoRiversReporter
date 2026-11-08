require "test_helper"
require "timeout"
require_relative "../../support/council_spend_scenario"

class CouncilProfilesParallelSpendReservationsTest < ActiveJob::TestCase
  include CouncilSpendScenario
  self.use_transactional_tests = false

  setup { setup_spend_scenario }
  teardown { cleanup_spend_scenario }

  test "council selection before an ordinary claim inherits the missing budget across workers" do
    ordinary_ready, council_selected, release_ordinary, release_council = 4.times.map { Queue.new }
    original_text = Minutes::Input.instance_method(:text)
    original_publish = Minutes::Publish.method(:call)
    # Pause after ordinary input preparation, outside the meeting transaction.
    # The real claim, selection, admission and persistence still execute.
    Minutes::Input.define_method(:text) do
      if Thread.current[:council_selection_race] == :ordinary && !ActiveRecord::Base.connection.transaction_open?
        Thread.current[:council_selection_race] = nil
        ordinary_ready << true
        release_ordinary.pop
      end
      original_text.bind_call(self)
    end
    pause_after_selection = ->(meeting) do
      if Thread.current[:council_selection_race] == :council
        Thread.current[:council_selection_race] = nil
        council_selected << true
        release_council.pop
      end
      original_publish.call(meeting)
    end
    workers = []
    begin
      with_transport do
        Minutes::Publish.stub(:call, pause_after_selection) do
          Timeout.timeout(15) do
            workers << worker do
              Thread.current[:council_selection_race] = :ordinary
              ExtractVotesJob.perform_now(@meeting.id)
            end
            ordinary_ready.pop
            assert_equal "pending", @meeting.minutes_extractions.sole.status
            assert_not @meeting.minutes_extractions.sole.budget_required?
            workers << worker do
              Thread.current[:council_selection_race] = :council
              CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes")
            end
            council_selected.pop
            assert Meeting.find(@meeting.id).council_ai_budget_required?
            release_ordinary << true
            workers.first.value
            assert_empty @calls
            release_council << true
            workers.last.value
          end
        end
        ExtractVotesJob.perform_now(@meeting.id)
      end
      ActiveRecord::Base.uncached do
        assert_empty @calls
        assert_held "votes", "missing_budget"
        assert @meeting.minutes_extractions.sole.budget_required?
        assert_equal 0, MinutesRequest.where(minutes_extraction_id: @meeting.minutes_extractions.select(:id)).count
      end
    ensure
      release_ordinary << true
      release_council << true
      workers.each { |thread| thread.join(15) }
      Minutes::Input.define_method(:text, original_text)
    end
  end

  test "parallel runs cannot both reserve the last daily allowance" do
    first = budget_run(day_limit: 4_100)
    second = budget_run
    entered, release, second_pid = Queue.new, Queue.new, Queue.new
    first_id = first.id
    pause = -> do
      if council_ai_budget_run_id == first_id
        entered << true
        release.pop
      end
    end
    CouncilAiReservation.set_callback(:create, :before, pause)
    workers = []
    begin
      with_transport do
        Timeout.timeout(15) do
          workers << worker { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: first.id) }
          entered.pop
          workers << worker do
            second_pid << ActiveRecord::Base.connection.select_value("SELECT pg_backend_pid()")
            CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "attendance", budget_run_id: second.id)
          end
          assert database_lock_wait?(second_pid.pop), "Second run must wait for the first daily reservation"
          release << true
          workers.each(&:value)
        end
      end
      ActiveRecord::Base.uncached do
        assert_equal 1, @calls.size
        assert_equal 4_100, first.council_ai_budget_day.reserved_microusd
        assert_equal 1, first.reservations.count
        assert_equal 0, second.reservations.count
        assert_equal 1, MinutesRequest.where(minutes_extraction_id: @meeting.minutes_extractions.select(:id)).count
        assert_held "attendance", "daily_budget_limit"
        assert_equal "completed", @meeting.minutes_extractions.find_by!(kind: "votes").status
      end
    ensure
      release << true
      workers.each { |thread| thread.join(15) }
      CouncilAiReservation.skip_callback(:create, :before, pause)
    end
  end

  test "an in-flight request occupies the concurrency slot and completion permits the held counterpart" do
    run = budget_run
    entered, release = Queue.new, Queue.new
    response = ->(parameters) do
      unless parameters[:messages].last[:content].include?("voting_members_present")
        entered << true
        release.pop
      end
      provider_response(parameters)
    end
    workers = []
    begin
      with_transport(response: response) do
        Timeout.timeout(15) do
          workers << worker { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: run.id) }
          entered.pop
          workers << worker { CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "attendance", budget_run_id: run.id) }
          workers.last.value
          ActiveRecord::Base.uncached do
            assert_equal 1, @calls.size
            assert_equal 4_100, run.reservations.sum(:reserved_microusd)
            assert_nil run.reservations.sole.finished_at
            assert_held "attendance", "concurrency_limit"
          end
          release << true
          workers.each(&:value)
        end
      end
      with_transport { ExtractCommitteeMembersJob.perform_now(@meeting.id) }
      ActiveRecord::Base.uncached do
        assert_equal 2, @calls.size
        assert_equal 8_200, run.reservations.sum(:reserved_microusd)
        assert_equal 0, run.reservations.where(finished_at: nil).count
        fresh = Meeting.find(@meeting.id)
        assert_equal 1, fresh.minutes_publications.count
        assert_equal [ "Alex Budget", "Blair Budget" ], fresh.meeting_attendances.joins(:member).order("members.name").pluck("members.name")
        assert_equal [ "no", "yes" ], fresh.motions.sole.votes.order(:id).pluck(:value)
      end
    ensure
      release << true
      workers.each { |thread| thread.join(15) }
    end
  end

  test "dispatch waits for the monthly authorization lock before reserving" do
    run = budget_run
    pid = Queue.new
    thread = nil
    begin
      with_transport do
        CouncilAiBudgetMonth.sole.with_lock do
          thread = worker do
            pid << ActiveRecord::Base.connection.select_value("SELECT pg_backend_pid()")
            CouncilProfiles::ExtractMinutesJob.perform_now(@meeting.id, "votes", budget_run_id: run.id)
          end
          assert database_lock_wait?(pid.pop), "Paid dispatch must lock the monthly allowance"
          assert_empty @calls
          assert_equal 0, run.reservations.count
        end
        Timeout.timeout(15) { thread.value }
      end
      assert_equal 1, @calls.size
      assert_equal 4_100, CouncilAiBudgetMonth.sole.reserved_microusd
      assert_equal "completed", @meeting.minutes_extractions.sole.status
    ensure
      thread&.join(15)
    end
  end

  private

  def worker(&block)
    Thread.new { ActiveRecord::Base.connection_pool.with_connection(&block) }
  end

  def database_lock_wait?(pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      waiting = ActiveRecord::Base.uncached do
        ActiveRecord::Base.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}")
      end
      return true if waiting == "Lock"
      sleep 0.01
    end
    false
  end
end
