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

  test "tiered thresholds: blocks at 0.7 but does not approve at 0.7" do
    topic_block = Topic.create!(name: "routine procedural item test", status: "proposed")
    topic_approve = Topic.create!(name: "important civic topic test", status: "proposed")

    tool = Topics::TriageTool.new(
      apply: true, dry_run: false,
      min_confidence: { block: 0.7, merge: 0.75, approve: 0.8, approve_novel: 0.9 },
      max_topics: 10,
      similarity_threshold: 0.75, agenda_item_limit: 5,
      user_id: nil, user_email: nil
    )

    results = {
      "merge_map" => [],
      "approvals" => [ { "topic" => "important civic topic test", "approve" => true, "confidence" => 0.7, "rationale" => "test" } ],
      "blocks" => [ { "topic" => "routine procedural item test", "block" => true, "confidence" => 0.7, "rationale" => "test" } ]
    }

    tool.send(:apply_results, results, nil)

    assert_equal "blocked", topic_block.reload.status, "Should block at 0.7"
    assert_equal "proposed", topic_approve.reload.status, "Should NOT approve at 0.7"
  end

  test "build_context includes community context" do
    Topic.create!(name: "test triage context topic", status: "proposed")

    tool = Topics::TriageTool.new(
      apply: false, dry_run: true,
      min_confidence: Topics::TriageTool::DEFAULT_MIN_CONFIDENCE,
      max_topics: 10,
      similarity_threshold: 0.75, agenda_item_limit: 5,
      user_id: nil, user_email: nil
    )

    context = tool.send(:build_context)
    assert context.key?(:community_context), "Context should include community_context key"
  end
end
