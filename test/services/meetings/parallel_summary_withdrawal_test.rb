require "test_helper"
require "timeout"
require_relative "../../support/meeting_summary_withdrawal_scenario"

class Meetings::ParallelSummaryWithdrawalTest < ActiveJob::TestCase
  include MeetingSummaryWithdrawalScenario
  self.use_transactional_tests = false

  setup { build_summary_withdrawal_scenario }
  teardown { clean_summary_withdrawal_scenario }

  test "source replacement waits for first summary publication and withdraws it before commit" do
    @summary.destroy!
    entered, release, started = Queue.new, Queue.new, Queue.new
    workers = []
    meeting_id = @meeting.id
    callback = -> do
      if self.meeting_id == meeting_id
        entered << true
        release.pop
      end
    end
    MeetingSummary.set_callback(:create, :before, callback)
    summary_providers do
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          SummarizeMeetingJob.perform_now(meeting_id, mode: :agenda_preview)
        end
      end
      Timeout.timeout(10) { entered.pop }
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          started << connection.select_value("SELECT pg_backend_pid()")
          download_summary_source("Synthetic concurrent changed source")
        end
      end
      pid = Timeout.timeout(10) { started.pop }
      wait_type = nil
      Timeout.timeout(10) do
        while workers.last.alive?
          wait_type = ActiveRecord::Base.uncached do
            ActiveRecord::Base.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}")
          end
          break if wait_type == "Lock"
          sleep 0.01
        end
      end
      assert_equal "Lock", wait_type, "Source publication must wait even before the first summary exists"
      release << true
      Timeout.timeout(10) { workers.each(&:value) }
    end
    assert_equal 2, @document.reload.source_versions.count
    assert_equal CLAIM, @meeting.meeting_summaries.sole.generation_data.fetch("headline")
    assert_not @meeting.meeting_summaries.sole.published?
    assert_nil ResidentContent::MeetingSelection.preferred_summary(@meeting.reload)
    assert_enqueued_jobs 0, only: SummarizeMeetingJob
  ensure
    release << true if release
    workers&.each { |worker| worker.join(10) }
    MeetingSummary.skip_callback(:create, :before, callback) if callback
  end

  test "knowledge and image publication finish without a foreign key deadlock or queued retry" do
    entered, release, started, errors = Queue.new, Queue.new, Queue.new, Queue.new
    workers = []
    meeting_id = @meeting.id
    callback = -> do
      if self.meeting_id == meeting_id
        entered << true
        release.pop
      end
    end
    KnowledgeSource.set_callback(:create, :before, callback)
    @provider.define_singleton_method(:extract_knowledge) do |**|
      { entries: [ { title: "Concurrent synthetic knowledge", body: "Synthetic fact", confidence: 0.95, reasoning: "Synthetic support" } ] }.to_json
    end
    @provider.define_singleton_method(:build_generated_image_brief) { |*| { "civic_issue" => "Synthetic library", "composition" => "Exterior" } }
    @provider.define_singleton_method(:generate_civic_image) { |**| { bytes: "synthetic", model: "deterministic", format: "jpeg", size: "1536x1024" } }
    clear_enqueued_jobs
    summary_providers do
      GeneratedImages::Config.stub(:enabled?, true) do
        workers << Thread.new do
          ActiveRecord::Base.connection_pool.with_connection { ExtractKnowledgeJob.perform_now(meeting_id) }
        rescue => error
          errors << error
        end
        Timeout.timeout(10) { entered.pop }
        workers << Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            started << connection.select_value("SELECT pg_backend_pid()")
            GeneratedImages::GenerateForMeetingJob.perform_now(meeting_id, force: true)
          end
        rescue => error
          errors << error
        end
        pid = Timeout.timeout(10) { started.pop }
        wait_type = nil
        Timeout.timeout(10) do
          while workers.last.alive?
            wait_type = ActiveRecord::Base.uncached do
              ActiveRecord::Base.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}")
            end
            break if wait_type == "Lock"
            sleep 0.01
          end
        end
        assert_equal "Lock", wait_type, "Image publication must serialize with the captured summary"
        release << true
        Timeout.timeout(10) { workers.each(&:value) }
      end
    end
    assert errors.empty?, "Unexpected worker error: #{errors.pop unless errors.empty?}"
    assert_equal 1, @meeting.knowledge_sources.count
    assert_equal 1, @meeting.generated_images.ready.count
    assert_enqueued_jobs 0, only: [ ExtractKnowledgeJob, GeneratedImages::GenerateForMeetingJob ]
    assert_predicate @summary.reload, :published?
  ensure
    release << true if release
    workers&.each { |worker| worker.join(10) }
    KnowledgeSource.skip_callback(:create, :before, callback) if callback
  end
end
