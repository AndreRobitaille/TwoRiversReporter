require "test_helper"

class PruneHollowAppearancesJobTest < ActiveJob::TestCase
  def create_meeting_with_item(title:)
    meeting = Meeting.create!(
      body_name: "Public Utilities Committee",
      starts_at: 1.day.ago,
      detail_page_url: "http://example.com/m#{SecureRandom.hex(4)}"
    )
    item = meeting.agenda_items.create!(title: title, order_index: 1)
    [ meeting, item ]
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
        "citations" => [ "Page 4" ]
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
        "citations" => [ "Page 3" ]
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
        "citations" => [ "Page 4" ]
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
        "citations" => [ "Page 2" ]
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
        "citations" => [ "Page 1" ]
      }
    ])
    topic = link_topic(item, topic_name: "adjournment")

    PruneHollowAppearancesJob.perform_now(meeting.id)

    assert_equal 0, topic.reload.agenda_item_topics.count
    assert_equal 0, topic.reload.topic_appearances.count
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
        "citations" => [ "Page 4" ]
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

  test "normalizes YY-NNN council agenda numbering correctly" do
    meeting, item = create_meeting_with_item(title: "26-001 Public hearing on zoning")
    create_summary(meeting, item_details: [
      {
        "agenda_item_title" => "26-001 Public hearing on zoning",
        "summary" => "Residents testified on proposed zoning change.",
        "activity_level" => "discussion",
        "vote" => nil,
        "decision" => nil,
        "public_hearing" => "Three residents spoke in favor, one opposed.",
        "citations" => [ "Page 2" ]
      }
    ])
    topic = link_topic(item, topic_name: "zoning change discussion")

    PruneHollowAppearancesJob.perform_now(meeting.id)

    # Should be preserved — YY-NNN normalization matches correctly,
    # the entry is found, activity_level is "discussion", public_hearing
    # is non-null, none of the hollow conditions apply.
    assert_equal 1, topic.reload.agenda_item_topics.count
    assert_equal 1, topic.reload.topic_appearances.count
  end

  test "demotes topic to blocked + dormant when pruning drops it to 0 appearances" do
    meeting, item = create_meeting_with_item(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
    create_summary(meeting, item_details: [
      {
        "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
        "summary" => "Nothing substantive.",
        "activity_level" => "status_update",
        "vote" => nil, "decision" => nil, "public_hearing" => nil,
        "citations" => []
      }
    ])
    topic = link_topic(item, topic_name: "phantom topic alpha")

    assert_no_enqueued_jobs(only: Topics::GenerateTopicBriefingJob) do
      PruneHollowAppearancesJob.perform_now(meeting.id)
    end

    topic.reload
    assert_equal "blocked", topic.status
    assert_equal "dormant", topic.lifecycle_status
    assert_nil topic.last_activity_at

    event = topic.topic_status_events.order(:created_at).last
    refute_nil event, "expected a TopicStatusEvent audit row"
    assert_equal "hollow_appearance_prune", event.evidence_type
    assert_equal "dormant", event.lifecycle_status
  end

  test "demotes topic to dormant when pruning drops it to 1 appearance" do
    meeting_a = Meeting.create!(
      body_name: "Public Utilities Committee",
      starts_at: 10.days.ago,
      detail_page_url: "http://example.com/m#{SecureRandom.hex(4)}"
    )
    item_a = meeting_a.agenda_items.create!(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED", order_index: 1)

    meeting_b = Meeting.create!(
      body_name: "Public Utilities Committee",
      starts_at: 2.days.ago,
      detail_page_url: "http://example.com/m#{SecureRandom.hex(4)}"
    )
    item_b = meeting_b.agenda_items.create!(title: "5. REAL SUBSTANTIVE ITEM", order_index: 1)

    create_summary(meeting_a, item_details: [
      {
        "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
        "summary" => "Nothing substantive.",
        "activity_level" => "status_update",
        "vote" => nil, "decision" => nil, "public_hearing" => nil,
        "citations" => []
      }
    ])

    topic = Topic.create!(name: "phantom topic beta", status: "approved", lifecycle_status: "active")
    AgendaItemTopic.create!(agenda_item: item_a, topic: topic)
    AgendaItemTopic.create!(agenda_item: item_b, topic: topic)

    assert_equal 2, topic.reload.topic_appearances.count

    assert_enqueued_with(
      job: Topics::GenerateTopicBriefingJob,
      args: [ { topic_id: topic.id, meeting_id: meeting_a.id } ]
    ) do
      PruneHollowAppearancesJob.perform_now(meeting_a.id)
    end

    topic.reload
    assert_equal 1, topic.topic_appearances.count
    assert_equal "approved", topic.status
    assert_equal "dormant", topic.lifecycle_status
    # last_activity_at is recomputed to the remaining (real) appearance's time
    assert_in_delta meeting_b.starts_at.to_f, topic.last_activity_at.to_f, 1.0

    event = topic.topic_status_events.order(:created_at).last
    refute_nil event, "expected a TopicStatusEvent audit row"
    assert_equal "hollow_appearance_prune", event.evidence_type
    assert_equal "dormant", event.lifecycle_status
  end

  test "leaves topic intact and enqueues briefing when pruning drops it to 2+ appearances" do
    meeting_a, item_a = create_meeting_with_item(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
    meeting_b, item_b = create_meeting_with_item(title: "5. REAL ITEM ONE")
    meeting_c, item_c = create_meeting_with_item(title: "6. REAL ITEM TWO")

    create_summary(meeting_a, item_details: [
      {
        "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
        "summary" => "Nothing substantive.",
        "activity_level" => "status_update",
        "vote" => nil, "decision" => nil, "public_hearing" => nil,
        "citations" => []
      }
    ])

    topic = Topic.create!(name: "mixed topic", status: "approved", lifecycle_status: "active")
    AgendaItemTopic.create!(agenda_item: item_a, topic: topic)
    AgendaItemTopic.create!(agenda_item: item_b, topic: topic)
    AgendaItemTopic.create!(agenda_item: item_c, topic: topic)

    assert_enqueued_with(
      job: Topics::GenerateTopicBriefingJob,
      args: [ { topic_id: topic.id, meeting_id: meeting_a.id } ]
    ) do
      PruneHollowAppearancesJob.perform_now(meeting_a.id)
    end

    topic.reload
    assert_equal 2, topic.topic_appearances.count
    assert_equal "approved", topic.status
    assert_equal "active", topic.lifecycle_status
    assert_equal 0, topic.topic_status_events.count
  end

  test "does not enqueue briefing when resident_impact is admin-locked" do
    meeting_a, item_a = create_meeting_with_item(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
    meeting_b, item_b = create_meeting_with_item(title: "5. REAL ITEM ONE")
    meeting_c, item_c = create_meeting_with_item(title: "6. REAL ITEM TWO")

    create_summary(meeting_a, item_details: [
      {
        "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
        "summary" => "Nothing substantive.",
        "activity_level" => "status_update",
        "vote" => nil, "decision" => nil, "public_hearing" => nil,
        "citations" => []
      }
    ])

    topic = Topic.create!(
      name: "admin locked topic",
      status: "approved",
      lifecycle_status: "active",
      resident_impact_score: 5,
      resident_impact_overridden_at: 1.day.ago
    )
    AgendaItemTopic.create!(agenda_item: item_a, topic: topic)
    AgendaItemTopic.create!(agenda_item: item_b, topic: topic)
    AgendaItemTopic.create!(agenda_item: item_c, topic: topic)

    assert_no_enqueued_jobs(only: Topics::GenerateTopicBriefingJob) do
      PruneHollowAppearancesJob.perform_now(meeting_a.id)
    end

    topic.reload
    assert_equal 2, topic.topic_appearances.count
  end

  test "does not enqueue briefing when 1 appearance remains and impact is admin-locked" do
    meeting_a, item_a = create_meeting_with_item(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
    meeting_b, item_b = create_meeting_with_item(title: "5. REAL ITEM")

    create_summary(meeting_a, item_details: [
      {
        "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
        "summary" => "Nothing substantive.",
        "activity_level" => "status_update",
        "vote" => nil, "decision" => nil, "public_hearing" => nil,
        "citations" => []
      }
    ])

    topic = Topic.create!(
      name: "admin locked 1-remaining topic",
      status: "approved",
      lifecycle_status: "active",
      resident_impact_score: 5,
      resident_impact_overridden_at: 1.day.ago
    )
    AgendaItemTopic.create!(agenda_item: item_a, topic: topic)
    AgendaItemTopic.create!(agenda_item: item_b, topic: topic)

    assert_no_enqueued_jobs(only: Topics::GenerateTopicBriefingJob) do
      PruneHollowAppearancesJob.perform_now(meeting_a.id)
    end

    topic.reload
    assert_equal 1, topic.topic_appearances.count
    assert_equal "dormant", topic.lifecycle_status
  end

  test "destroys orphaned TopicSummary when all of a topic's appearances on a meeting are pruned" do
    meeting, item = create_meeting_with_item(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
    create_summary(meeting, item_details: [
      {
        "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
        "summary" => "Leaf totals; nothing substantive.",
        "activity_level" => "status_update",
        "vote" => nil, "decision" => nil, "public_hearing" => nil,
        "citations" => []
      }
    ])
    topic = link_topic(item, topic_name: "garbage and recycling service changes")

    # Per-meeting topic digest created by SummarizeMeetingJob. When the
    # appearance is pruned this row is stale and must go with it.
    TopicSummary.create!(
      topic: topic,
      meeting: meeting,
      summary_type: "topic_digest",
      content: "stale digest",
      generation_data: { "factual_record" => [ { "statement" => "agenda included this topic" } ] }
    )

    assert_equal 1, TopicSummary.where(topic: topic, meeting: meeting).count

    PruneHollowAppearancesJob.perform_now(meeting.id)

    assert_equal 0, TopicAppearance.where(topic_id: topic.id, meeting_id: meeting.id).count
    assert_equal 0, TopicSummary.where(topic: topic, meeting: meeting).count,
      "stale TopicSummary should be destroyed alongside its pruned appearances"
  end

  test "preserves TopicSummary when topic still has another appearance on the same meeting" do
    meeting = Meeting.create!(
      body_name: "Public Utilities Committee",
      starts_at: 1.day.ago,
      detail_page_url: "http://example.com/m#{SecureRandom.hex(4)}"
    )
    hollow_item = meeting.agenda_items.create!(
      title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
      order_index: 1
    )
    substantive_item = meeting.agenda_items.create!(
      title: "11. Garbage & Recycling Discussion",
      order_index: 2
    )

    create_summary(meeting, item_details: [
      {
        "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
        "summary" => "Routine.",
        "activity_level" => "status_update",
        "vote" => nil, "decision" => nil, "public_hearing" => nil,
        "citations" => []
      },
      {
        "agenda_item_title" => "11. Garbage & Recycling Discussion",
        "summary" => "Committee reviewed proposed changes and deferred a vote.",
        "activity_level" => "discussion",
        "vote" => nil, "decision" => nil, "public_hearing" => nil,
        "citations" => []
      }
    ])

    topic = Topic.create!(name: "garbage and recycling service changes", status: "approved")
    AgendaItemTopic.create!(agenda_item: hollow_item, topic: topic)
    AgendaItemTopic.create!(agenda_item: substantive_item, topic: topic)

    TopicSummary.create!(
      topic: topic,
      meeting: meeting,
      summary_type: "topic_digest",
      content: "live digest",
      generation_data: { "factual_record" => [ { "statement" => "committee deferred" } ] }
    )

    assert_equal 2, TopicAppearance.where(topic_id: topic.id, meeting_id: meeting.id).count

    PruneHollowAppearancesJob.perform_now(meeting.id)

    assert_equal 1, TopicAppearance.where(topic_id: topic.id, meeting_id: meeting.id).count,
      "hollow appearance should be pruned"
    assert_equal 1, TopicSummary.where(topic: topic, meeting: meeting).count,
      "TopicSummary must survive because substantive appearance still exists"
  end
end
