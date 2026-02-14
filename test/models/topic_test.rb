require "test_helper"

class TopicTest < ActiveSupport::TestCase
  setup do
    Topic.destroy_all
  end

  test "normalizes name on create" do
    topic = Topic.create!(name: "  Foo Bar!  ")
    assert_equal "foo bar", topic.name
  end

  test "publicly_visible scope" do
    Topic.create!(name: "approved", status: "approved")
    Topic.create!(name: "pinned", pinned: true, status: "proposed")
    Topic.create!(name: "blocked", status: "blocked")
    Topic.create!(name: "proposed", status: "proposed")

    assert_equal 2, Topic.publicly_visible.count
    assert_includes Topic.publicly_visible.map(&:name), "approved"
    assert_includes Topic.publicly_visible.map(&:name), "pinned"
  end

  test "maintains derived fields on create" do
    topic = Topic.create!(name: "Public Safety", status: "proposed")
    assert_equal "public safety", topic.canonical_name
    assert_equal "public-safety", topic.slug
    assert_equal "proposed", topic.review_status
  end

  test "updates canonical name and slug when name changes" do
    topic = Topic.create!(name: "Old Name", status: "proposed")
    topic.update!(name: "New Name")
    assert_equal "new name", topic.canonical_name
    assert_equal "new-name", topic.slug
  end

  test "backfill job populates appearances and lifecycle" do
    topic = Topic.create!(name: "Test Topic", status: "proposed")
    meeting = Meeting.create!(
      body_name: "City Council",
      meeting_type: "Regular",
      starts_at: 1.day.ago,
      status: "minutes_posted",
      detail_page_url: "http://example.com/meeting/1"
    )
    agenda_item = AgendaItem.create!(
      meeting: meeting,
      number: "1",
      title: "Item 1",
      order_index: 1
    )
    AgendaItemTopic.create!(topic: topic, agenda_item: agenda_item)

    Topics::BackfillContinuityJob.perform_now(topic.id)

    topic.reload
    assert_equal 1, topic.topic_appearances.count
    appearance = topic.topic_appearances.first
    assert_equal meeting, appearance.meeting
    assert_equal agenda_item, appearance.agenda_item
    assert_equal "agenda_item", appearance.evidence_type

    assert_not_nil topic.first_seen_at
    assert_not_nil topic.last_seen_at
    assert_equal "active", topic.lifecycle_status
  end
end
