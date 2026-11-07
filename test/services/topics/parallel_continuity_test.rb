require "test_helper"
require "minitest/mock"
require "timeout"

class TopicsParallelContinuityTest < ActiveJob::TestCase
  self.use_transactional_tests = false

  setup do
    suffix = SecureRandom.hex(8)
    @topic = Topic.create!(name: "Synthetic concurrent topic #{suffix}", status: "approved")
    @meeting = Meeting.create!(body_name: "Synthetic Council", starts_at: 1.day.ago, detail_page_url: "https://example.test/concurrent-topics/#{suffix}")
    agenda = @meeting.agenda_items.create!(number: "1", title: "Synthetic resolution")
    agenda.topics << @topic
    @motion = @meeting.motions.create!(agenda_item: agenda, description: "Synthetic motion", outcome: "passed")
    @topic.update!(lifecycle_status: "resolved", first_seen_at: @meeting.starts_at, last_seen_at: @meeting.starts_at, last_activity_at: @meeting.starts_at)
  end

  teardown do
    @topic&.reload&.destroy!
    @meeting&.reload&.destroy!
  end

  test "concurrent continuity runs preserve one event for one decision" do
    entered, release, started = Queue.new, Queue.new, Queue.new
    topic_id = @topic.id
    callback = -> do
      if self.topic_id == topic_id && evidence_type == "motion_outcome" && Thread.current[:continuity_role] == :first
        entered << true
        release.pop
      end
    end
    workers = []
    TopicStatusEvent.set_callback(:create, :before, callback)
    Ai::OpenAiService.stub :new, ->(*) { flunk "Continuity must not call a provider" } do
      workers << run_continuity(:first)
      Timeout.timeout(10) { entered.pop }
      workers << run_continuity(:second, started)
      second_pid = Timeout.timeout(10) { started.pop }
      Timeout.timeout(10) do
        while workers.last.alive?
          wait_type = ActiveRecord::Base.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(second_pid)}")
          break if wait_type == "Lock"
          sleep 0.01
        end
      end
      release << true
      Timeout.timeout(10) { workers.each(&:value) }
    end
    ActiveRecord::Base.uncached do
      events = TopicStatusEvent.where(topic_id: @topic.id, evidence_type: "motion_outcome")
      assert_equal 1, events.count
      assert_equal @motion.id, events.sole.source_ref["motion_id"]
      assert_equal 1, events.with_current_evidence.count
    end
  ensure
    release << true if release
    workers&.each { |worker| worker.join(10) }
    TopicStatusEvent.skip_callback(:create, :before, callback) if callback
  end

  private

  def run_continuity(role, started = nil)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        Thread.current[:continuity_role] = role
        started << connection.select_value("SELECT pg_backend_pid()") if started
        Topics::ContinuityService.call(Topic.find(@topic.id))
      end
    end
  end
end
