require "test_helper"
require "timeout"
require_relative "../../support/briefing_withdrawal_scenario"

class Topics::ParallelBriefingWithdrawalTest < ActiveJob::TestCase
  include BriefingWithdrawalScenario
  self.use_transactional_tests = false

  setup { build_withdrawal_scenario }

  teardown do
    Topic.where(id: [ @topic&.id, @other&.id ]).destroy_all
    if @meeting&.persisted?
      stage_ids = @meeting.minutes_extractions.pluck(:id)
      publication_ids = @meeting.minutes_publications.pluck(:id)
      decision_ids = @meeting.council_decisions.pluck(:id)
      observation_ids = CouncilDecisionObservation.where(minutes_extraction_id: stage_ids).pluck(:id)
      versions = @document.source_versions.to_a
      text_versions = MeetingDocumentTextVersion.where(meeting_document_version_id: versions.map(&:id)).to_a
      @meeting.destroy!
      MinutesPublication.where(id: publication_ids).destroy_all
      CouncilDecisionAssignment.where(minutes_extraction_id: stage_ids).delete_all
      CouncilDecisionCorrection.where(observation_id: observation_ids).delete_all
      CouncilDecisionObservation.where(id: observation_ids).destroy_all
      CouncilDecision.where(id: decision_ids).destroy_all
      MinutesExtraction.where(id: stage_ids).destroy_all
      text_versions.each(&:destroy!)
      versions.each(&:destroy!)
    end
    @committee&.destroy!
    Member.where(name: "Alex Example").destroy_all
    User.where(id: @actor&.id).delete_all
    perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
  end

  test "correction waits for first briefing publication then withdraws the newly committed row" do
    @briefing.destroy!
    entered, release, started = Queue.new, Queue.new, Queue.new
    workers = []
    topic_id = @topic.id
    callback = -> do
      if self.topic_id == topic_id
        entered << true
        release.pop
      end
    end
    TopicBriefing.set_callback(:create, :before, callback)
    withdrawal_providers do
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Topics::GenerateTopicBriefingJob.perform_now(topic_id: @topic.id, meeting_id: @meeting.id)
        end
      end
      Timeout.timeout(10) { entered.pop }
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          started << connection.select_value("SELECT pg_backend_pid()")
          CouncilDecisions::ResolveIdentity.call(observation: CouncilDecisionObservation.find(@event.decision_observation_id),
            action: "unassign", actor: User.find(@actor.id), reason: "Synthetic concurrent correction",
            expected_correction_id: nil, request_id: SecureRandom.uuid)
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
      assert_equal "Lock", wait_type, "Correction must wait on the topic even when no briefing row is committed yet"
      release << true
      Timeout.timeout(10) { workers.each(&:value) }
    end
    @topic.reload
    assert_nil @topic.published_topic_briefing
    assert_equal CLAIM, @topic.topic_briefing.headline
    assert_not_nil @topic.topic_briefing.withdrawal_correction_id
    assert_nil @event.reload.council_decision
    assert_not_nil @other.reload.published_topic_briefing
  ensure
    release << true if release
    workers&.each { |worker| worker.join(10) }
    TopicBriefing.skip_callback(:create, :before, callback) if callback
  end
end
