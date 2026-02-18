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

  test "validates resident_impact_score range 1-5" do
    topic = Topic.new(name: "Test", status: "proposed", resident_impact_score: 6)
    assert_not topic.valid?
    assert_includes topic.errors[:resident_impact_score], "must be less than or equal to 5"

    topic.resident_impact_score = 0
    assert_not topic.valid?
    assert_includes topic.errors[:resident_impact_score], "must be greater than or equal to 1"

    topic.resident_impact_score = 3
    assert topic.valid?
  end

  test "allows nil resident_impact_score" do
    topic = Topic.new(name: "Test", status: "proposed", resident_impact_score: nil)
    assert topic.valid?
  end

  test "resident_impact_admin_locked? returns true within 180 days" do
    topic = Topic.create!(name: "Test Lock True", status: "proposed",
      resident_impact_score: 4,
      resident_impact_overridden_at: 10.days.ago)
    assert topic.resident_impact_admin_locked?
  end

  test "resident_impact_admin_locked? returns false after 180 days" do
    topic = Topic.create!(name: "Test Lock Expired", status: "proposed",
      resident_impact_score: 4,
      resident_impact_overridden_at: 181.days.ago)
    assert_not topic.resident_impact_admin_locked?
  end

  test "resident_impact_admin_locked? returns false when no override" do
    topic = Topic.create!(name: "Test Lock Nil", status: "proposed", resident_impact_score: 3)
    assert_not topic.resident_impact_admin_locked?
  end

  test "update_resident_impact_from_ai skips when admin locked" do
    topic = Topic.create!(name: "Test AI Skip", status: "proposed",
      resident_impact_score: 5,
      resident_impact_overridden_at: 10.days.ago)
    topic.update_resident_impact_from_ai(2)
    assert_equal 5, topic.reload.resident_impact_score
  end

  test "update_resident_impact_from_ai updates when not locked" do
    topic = Topic.create!(name: "Test AI Update", status: "proposed",
      resident_impact_score: 2,
      resident_impact_overridden_at: nil)
    topic.update_resident_impact_from_ai(4)
    assert_equal 4, topic.reload.resident_impact_score
  end

  test "update_resident_impact_from_ai updates when override expired" do
    topic = Topic.create!(name: "Test AI Expired", status: "proposed",
      resident_impact_score: 5,
      resident_impact_overridden_at: 200.days.ago)
    topic.update_resident_impact_from_ai(3)
    assert_equal 3, topic.reload.resident_impact_score
  end
end
