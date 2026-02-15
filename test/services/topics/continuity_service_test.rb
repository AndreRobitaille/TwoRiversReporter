require "test_helper"

module Topics
  class ContinuityServiceTest < ActiveSupport::TestCase
    setup do
      Topic.destroy_all
      Meeting.destroy_all
      AgendaItem.destroy_all

      @topic = Topic.create!(name: "Test Topic", status: "proposed")

      # Meeting 1: 7 months ago (Dormant base)
      @m1 = Meeting.create!(body_name: "Committee", starts_at: 7.months.ago, detail_page_url: "http://example.com/1")
      @ai1 = AgendaItem.create!(meeting: @m1, title: "Initial Discussion", number: "1")
      AgendaItemTopic.create!(topic: @topic, agenda_item: @ai1)
      # This creates an appearance via callback
    end

    test "sets status to dormant if no recent activity" do
      Topics::ContinuityService.call(@topic)
      @topic.reload

      assert_equal "dormant", @topic.lifecycle_status
    end

    test "sets status to active if recent activity" do
      # Meeting 2: 1 month ago
      m2 = Meeting.create!(body_name: "Committee", starts_at: 1.month.ago, detail_page_url: "http://example.com/2")
      ai2 = AgendaItem.create!(meeting: m2, title: "Follow up", number: "2")
      AgendaItemTopic.create!(topic: @topic, agenda_item: ai2)

      Topics::ContinuityService.call(@topic)
      @topic.reload

      assert_equal "active", @topic.lifecycle_status
    end

    test "sets status to resolved if motion passed recently" do
      # Meeting 2: 1 month ago, with resolution
      m2 = Meeting.create!(body_name: "Council", starts_at: 1.month.ago, detail_page_url: "http://example.com/2")
      ai2 = AgendaItem.create!(meeting: m2, title: "Final Vote", number: "2")
      AgendaItemTopic.create!(topic: @topic, agenda_item: ai2)

      # Create Motion linked to AI
      Motion.create!(meeting: m2, agenda_item: ai2, outcome: "passed", description: "Approve ordinance")

      Topics::ContinuityService.call(@topic)
      @topic.reload

      assert_equal "resolved", @topic.lifecycle_status

      event = @topic.topic_status_events.find_by(lifecycle_status: "resolved")
      assert_not_nil event
      assert_equal "motion_outcome", event.evidence_type
    end

    test "sets status to recurring if appearance after resolution cooldown" do
      # Create clean topic
      topic = Topic.create!(name: "Recurring Topic", status: "proposed")

      # Resolution 8 months ago
      m_old = Meeting.create!(body_name: "Council", starts_at: 8.months.ago, detail_page_url: "http://example.com/old")
      ai_old = AgendaItem.create!(meeting: m_old, title: "Old Vote", number: "1")
      AgendaItemTopic.create!(topic: topic, agenda_item: ai_old)
      Motion.create!(meeting: m_old, agenda_item: ai_old, outcome: "passed", description: "Resolved")

      # Run service to set to resolved
      Topics::ContinuityService.call(topic)
      topic.reload

      # Check if status is resolved before recurring check
      assert_equal "resolved", topic.lifecycle_status, "Topic should be resolved first. Current status: #{topic.lifecycle_status}"

      # New appearance today
      m_new = Meeting.create!(body_name: "Council", starts_at: Time.current, detail_page_url: "http://example.com/new")
      ai_new = AgendaItem.create!(meeting: m_new, title: "Revisit", number: "2")
      AgendaItemTopic.create!(topic: topic, agenda_item: ai_new)

      Topics::ContinuityService.call(topic)
      topic.reload

      assert_equal "recurring", topic.lifecycle_status

      event = topic.topic_status_events.where(lifecycle_status: "recurring").last
      assert_equal "recurring", event.lifecycle_status
      assert_equal "agenda_recurrence", event.evidence_type
    end



    test "detects deferral signals" do
      # Meeting 2: 1 month ago, deferred
      m2 = Meeting.create!(body_name: "Committee", starts_at: 1.month.ago, detail_page_url: "http://example.com/2")
      ai2 = AgendaItem.create!(meeting: m2, title: "Discussion", recommended_action: "Defer to next meeting", number: "2")
      AgendaItemTopic.create!(topic: @topic, agenda_item: ai2)

      Topics::ContinuityService.call(@topic)
      @topic.reload

      # Status should be active (recent appearance), but log deferral
      assert_equal "active", @topic.lifecycle_status

      event = @topic.topic_status_events.where(evidence_type: "deferral_signal").last
      assert_not_nil event
      assert_match /defer/, event.notes.downcase
    end

    test "detects disappearance signals" do
      # Initial setup was 7 months ago (dormant).
      # Disappearance window is 12 months.
      # Let's make the last appearance 13 months ago.
      @m1.update!(starts_at: 13.months.ago)
      @topic.topic_appearances.update_all(appeared_at: 13.months.ago)

      Topics::ContinuityService.call(@topic)
      @topic.reload

      assert_equal "dormant", @topic.lifecycle_status

      event = @topic.topic_status_events.where(evidence_type: "disappearance_signal").last
      assert_not_nil event
      assert_equal "dormant", event.lifecycle_status
    end

    test "detects cross-body progression" do
      # M1 is "Committee"

      # M2 is "Council"
      m2 = Meeting.create!(body_name: "Council", starts_at: 1.month.ago, detail_page_url: "http://example.com/2")
      ai2 = AgendaItem.create!(meeting: m2, title: "Council Disc", number: "2")
      AgendaItemTopic.create!(topic: @topic, agenda_item: ai2)

      Topics::ContinuityService.call(@topic)

      event = @topic.topic_status_events.where(evidence_type: "cross_body_progression").last
      assert_not_nil event
      assert_equal "Committee", event.source_ref["from"]
      assert_equal "Council", event.source_ref["to"]
    end

    test "is idempotent" do
      # Setup scenario that creates events (resolution + cross-body from setup)
      m2 = Meeting.create!(body_name: "Council", starts_at: 1.month.ago, detail_page_url: "http://example.com/2")
      ai2 = AgendaItem.create!(meeting: m2, title: "Final Vote", number: "2")
      AgendaItemTopic.create!(topic: @topic, agenda_item: ai2)
      Motion.create!(meeting: m2, agenda_item: ai2, outcome: "passed", description: "Resolved")

      # First run
      Topics::ContinuityService.call(@topic)
      initial_count = TopicStatusEvent.count
      assert initial_count > 0

      # Second run - should add no new events
      assert_no_difference "TopicStatusEvent.count" do
        Topics::ContinuityService.call(@topic)
      end
    end
  end
end
