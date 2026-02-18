require "test_helper"

class Topics::TriageToolTest < ActiveSupport::TestCase
  test "record_review_event creates event without user for automated triage" do
    topic = Topic.create!(name: "test automated audit", status: "proposed")

    tool = Topics::TriageTool.new(
      apply: true, dry_run: false,
      min_confidence: 0.5, max_topics: 10,
      similarity_threshold: 0.75, agenda_item_limit: 5,
      user_id: nil, user_email: nil
    )

    tool.send(:record_review_event, nil, topic, "approved", "Auto-approve via triage tool: test")

    event = topic.topic_review_events.last
    assert_not_nil event, "Event should be created even without a user"
    assert_nil event.user_id
    assert_equal "approved", event.action
    assert event.automated?, "Event should be marked as automated"
  end
end
