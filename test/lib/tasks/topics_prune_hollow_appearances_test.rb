require "test_helper"
require "rake"

class TopicsPruneHollowAppearancesRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    @task = Rake::Task["topics:prune_hollow_appearances"]
    @task.reenable
    ENV.delete("DRY_RUN")
    ENV["CONFIRM"] = "1"  # default to live mode for tests that need to assert side effects
  end

  teardown do
    ENV.delete("CONFIRM")
    ENV.delete("DRY_RUN")
  end

  def create_meeting_with_item(title:)
    meeting = Meeting.create!(
      body_name: "Public Utilities Committee",
      starts_at: rand(1..200).days.ago,
      detail_page_url: "http://example.com/m#{SecureRandom.hex(4)}"
    )
    item = meeting.agenda_items.create!(title: title, order_index: 1)
    [ meeting, item ]
  end

  def create_old_format_summary(meeting, entry_title:, summary_text: "Routine status update with no decisions.")
    meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: {
        "item_details" => [
          {
            "agenda_item_title" => entry_title,
            "summary" => summary_text,
            "vote" => nil,
            "decision" => nil,
            "public_hearing" => nil,
            "citations" => []
          }
        ]
      }
    )
  end

  test "prunes appearances on standing-slot title matches for old-format summaries" do
    topic = Topic.create!(name: "garbage and recycling service changes", status: "approved", lifecycle_status: "active")

    3.times do
      meeting, item = create_meeting_with_item(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
      create_old_format_summary(meeting, entry_title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
      AgendaItemTopic.create!(agenda_item: item, topic: topic)
    end

    assert_equal 3, topic.reload.topic_appearances.count

    @task.invoke

    assert_equal 0, topic.reload.topic_appearances.count
    assert_equal "blocked", topic.status
    assert_equal "dormant", topic.lifecycle_status
  end

  test "preserves standing-slot appearance when a motion is linked" do
    topic = Topic.create!(name: "real garbage decision", status: "approved", lifecycle_status: "active")

    meeting, item = create_meeting_with_item(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
    create_old_format_summary(meeting, entry_title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
                              summary_text: "Committee voted to adopt a new fee schedule. Motion carried 4-0.")
    AgendaItemTopic.create!(agenda_item: item, topic: topic)
    Motion.create!(meeting: meeting, agenda_item: item, description: "Approve fee schedule", outcome: "passed")

    @task.invoke

    assert_equal 1, topic.reload.topic_appearances.count
  end

  test "preserves appearance when summary prose contains action verbs (no Motion row)" do
    topic = Topic.create!(name: "action verb topic", status: "approved", lifecycle_status: "active")

    # Standing-slot title matches, no Motion row exists, but the summary
    # text contains "voted" — the expanded motion-keyword check should
    # rescue it from pruning. This guards against the backfill
    # overcorrecting on real decisions that weren't captured as Motion rows.
    3.times do
      meeting, item = create_meeting_with_item(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
      create_old_format_summary(meeting, entry_title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
                                summary_text: "Committee voted 5-0 to raise residential rates.")
      AgendaItemTopic.create!(agenda_item: item, topic: topic)
    end

    @task.invoke

    assert_equal 3, topic.reload.topic_appearances.count
  end

  test "preserves non-standing-slot appearances" do
    topic = Topic.create!(name: "specific rezoning", status: "approved", lifecycle_status: "active")

    meeting, item = create_meeting_with_item(title: "5. REZONING OF 1234 MAIN STREET")
    create_old_format_summary(meeting, entry_title: "5. REZONING OF 1234 MAIN STREET")
    AgendaItemTopic.create!(agenda_item: item, topic: topic)

    @task.invoke

    assert_equal 1, topic.reload.topic_appearances.count
  end

  test "DRY_RUN mode does not modify the database" do
    topic = Topic.create!(name: "dry run topic", status: "approved", lifecycle_status: "active")

    3.times do
      meeting, item = create_meeting_with_item(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
      create_old_format_summary(meeting, entry_title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
      AgendaItemTopic.create!(agenda_item: item, topic: topic)
    end

    ENV.delete("CONFIRM")
    ENV["DRY_RUN"] = "1"
    @task.invoke

    assert_equal 3, topic.reload.topic_appearances.count
    assert_equal "active", topic.lifecycle_status
  end

  test "refuses to run without DRY_RUN or CONFIRM" do
    ENV.delete("CONFIRM")
    ENV.delete("DRY_RUN")

    assert_raises(SystemExit) do
      @task.invoke
    end
  end

  test "auto-detects repeated titles as standing slots without explicit pattern match" do
    topic = Topic.create!(name: "repeated title topic", status: "approved", lifecycle_status: "active")

    # Title doesn't match the explicit standing-slot pattern list, but it
    # repeats 3+ times across the topic's appearances. Auto-detection
    # should kick in.
    3.times do
      meeting, item = create_meeting_with_item(title: "PARKING LOT MAINTENANCE REPORT")
      create_old_format_summary(meeting, entry_title: "PARKING LOT MAINTENANCE REPORT")
      AgendaItemTopic.create!(agenda_item: item, topic: topic)
    end

    @task.invoke

    assert_equal 0, topic.reload.topic_appearances.count
  end
end
