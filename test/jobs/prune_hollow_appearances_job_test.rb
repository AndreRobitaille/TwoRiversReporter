require "test_helper"

class PruneHollowAppearancesJobTest < ActiveJob::TestCase
  def create_meeting_with_item(title:)
    meeting = Meeting.create!(
      body_name: "Public Utilities Committee",
      starts_at: 1.day.ago,
      detail_page_url: "http://example.com/m#{SecureRandom.hex(4)}"
    )
    item = meeting.agenda_items.create!(title: title, order_index: 1)
    [meeting, item]
  end

  def create_summary(meeting, item_details:)
    meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: { "item_details" => item_details }
    )
  end

  def link_topic(item, topic_name:)
    topic = Topic.create!(name: topic_name, status: "approved")
    AgendaItemTopic.create!(agenda_item: item, topic: topic)
    topic
  end

  test "prunes appearance when activity_level is status_update with null vote/decision/public_hearing" do
    meeting, item = create_meeting_with_item(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
    create_summary(meeting, item_details: [
      {
        "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
        "summary" => "Leaf totals exceeded prior year, no decisions made.",
        "activity_level" => "status_update",
        "vote" => nil,
        "decision" => nil,
        "public_hearing" => nil,
        "citations" => ["Page 4"]
      }
    ])
    topic = link_topic(item, topic_name: "garbage and recycling service changes")

    assert_equal 1, topic.topic_appearances.count
    assert_equal 1, topic.agenda_item_topics.count

    PruneHollowAppearancesJob.perform_now(meeting.id)

    assert_equal 0, topic.reload.topic_appearances.count
    assert_equal 0, topic.agenda_item_topics.count
  end

  test "preserves appearance when activity_level is discussion" do
    meeting, item = create_meeting_with_item(title: "8. WATER UTILITY: DIRECTOR UPDATE")
    create_summary(meeting, item_details: [
      {
        "agenda_item_title" => "8. WATER UTILITY: DIRECTOR UPDATE",
        "summary" => "Lead service line inspection push tied to 2027 deadline.",
        "activity_level" => "discussion",
        "vote" => nil,
        "decision" => nil,
        "public_hearing" => nil,
        "citations" => ["Page 3"]
      }
    ])
    topic = link_topic(item, topic_name: "lead service line replacement")

    PruneHollowAppearancesJob.perform_now(meeting.id)

    assert_equal 1, topic.reload.agenda_item_topics.count
  end

  test "preserves appearance when a motion is linked even if activity_level is status_update" do
    meeting, item = create_meeting_with_item(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
    create_summary(meeting, item_details: [
      {
        "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
        "summary" => "Routine update.",
        "activity_level" => "status_update",
        "vote" => nil,
        "decision" => nil,
        "public_hearing" => nil,
        "citations" => ["Page 4"]
      }
    ])
    topic = link_topic(item, topic_name: "garbage and recycling service changes")

    # A real motion was linked — the prune job must respect it even if
    # the AI mis-labeled the activity_level.
    Motion.create!(
      meeting: meeting,
      agenda_item: item,
      description: "Move to approve new solid waste rate schedule",
      outcome: "passed"
    )

    PruneHollowAppearancesJob.perform_now(meeting.id)

    assert_equal 1, topic.reload.agenda_item_topics.count
  end

  test "preserves appearance when public_hearing is non-null" do
    meeting, item = create_meeting_with_item(title: "5. PUBLIC HEARING ON RATE INCREASE")
    create_summary(meeting, item_details: [
      {
        "agenda_item_title" => "5. PUBLIC HEARING ON RATE INCREASE",
        "summary" => "Two residents spoke about proposed increase.",
        "activity_level" => "status_update",
        "vote" => nil,
        "decision" => nil,
        "public_hearing" => "Two residents testified against the rate increase.",
        "citations" => ["Page 2"]
      }
    ])
    topic = link_topic(item, topic_name: "utility rates")

    PruneHollowAppearancesJob.perform_now(meeting.id)

    assert_equal 1, topic.reload.agenda_item_topics.count
  end

  test "prunes when agenda item has no matching item_details entry (procedural) on new-format summary" do
    meeting, item = create_meeting_with_item(title: "12. ADJOURNMENT")
    # New-format summary: has at least one entry with activity_level.
    # The procedural adjournment item isn't in item_details at all.
    create_summary(meeting, item_details: [
      {
        "agenda_item_title" => "7. OTHER ITEM",
        "summary" => "Something real happened.",
        "activity_level" => "discussion",
        "vote" => nil,
        "decision" => nil,
        "public_hearing" => nil,
        "citations" => ["Page 1"]
      }
    ])
    topic = link_topic(item, topic_name: "adjournment")

    PruneHollowAppearancesJob.perform_now(meeting.id)

    assert_equal 0, topic.reload.agenda_item_topics.count
  end

  test "skips entirely when summary is old-format (no entry has activity_level)" do
    meeting, item = create_meeting_with_item(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
    # Old-format summary: no entry has activity_level. Job should be a no-op.
    create_summary(meeting, item_details: [
      {
        "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
        "summary" => "Routine update.",
        "vote" => nil,
        "decision" => nil,
        "public_hearing" => nil,
        "citations" => ["Page 4"]
      }
    ])
    topic = link_topic(item, topic_name: "garbage and recycling service changes")

    PruneHollowAppearancesJob.perform_now(meeting.id)

    assert_equal 1, topic.reload.agenda_item_topics.count
  end

  test "returns early when meeting has no summary" do
    meeting, item = create_meeting_with_item(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
    topic = link_topic(item, topic_name: "garbage and recycling service changes")

    assert_nothing_raised do
      PruneHollowAppearancesJob.perform_now(meeting.id)
    end
    assert_equal 1, topic.reload.agenda_item_topics.count
  end
end
