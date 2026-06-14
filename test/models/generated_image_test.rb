require "test_helper"

class GeneratedImageTest < ActiveSupport::TestCase
  test "validates status and purpose" do
    topic = Topic.create!(name: "Test Topic", status: "approved")
    image = GeneratedImage.new(imageable: topic, status: "ready", purpose: "feature_and_og")

    assert image.valid?

    image.status = "unknown"
    assert_not image.valid?
    assert_includes image.errors[:status], "is not included in the list"

    image.status = "ready"
    image.purpose = "unknown"
    assert_not image.valid?
    assert_includes image.errors[:purpose], "is not included in the list"
  end

  test "current_generated_image returns newest ready image for purpose" do
    topic = Topic.create!(name: "Test Topic 2", status: "approved")

    old_image = GeneratedImage.create!(
      imageable: topic,
      status: "ready",
      purpose: "feature_and_og",
      source_content_fingerprint: "old",
      generated_at: 2.days.ago
    )
    new_image = GeneratedImage.create!(
      imageable: topic,
      status: "ready",
      purpose: "feature_and_og",
      source_content_fingerprint: "new",
      generated_at: 1.hour.ago
    )
    GeneratedImage.create!(
      imageable: topic,
      status: "failed",
      purpose: "feature_and_og",
      source_content_fingerprint: "failed",
      generated_at: Time.current
    )

    assert_equal new_image, topic.current_generated_image(:og)
    assert_not_equal old_image, topic.current_generated_image(:og)
  end

  test "usable_for :og returns og and feature_and_og images" do
    topic = Topic.create!(name: "Test Topic 2c", status: "approved")
    og_image = GeneratedImage.create!(
      imageable: topic,
      status: "ready",
      purpose: "og",
      source_content_fingerprint: "og",
      generated_at: 2.hours.ago
    )
    feature_and_og_image = GeneratedImage.create!(
      imageable: topic,
      status: "ready",
      purpose: "feature_and_og",
      source_content_fingerprint: "fao",
      generated_at: 1.hour.ago
    )
    feature_image = GeneratedImage.create!(
      imageable: topic,
      status: "ready",
      purpose: "feature",
      source_content_fingerprint: "feature",
      generated_at: 30.minutes.ago
    )

    assert_equal [ feature_and_og_image, og_image ], GeneratedImage.usable_for(:og).to_a
    assert_includes GeneratedImage.usable_for(:og), og_image
    assert_includes GeneratedImage.usable_for(:og), feature_and_og_image
    assert_not_includes GeneratedImage.usable_for(:og), feature_image
  end

  test "usable_for :feature returns feature and feature_and_og images" do
    topic = Topic.create!(name: "Test Topic 2d", status: "approved")
    feature_image = GeneratedImage.create!(
      imageable: topic,
      status: "ready",
      purpose: "feature",
      source_content_fingerprint: "feature",
      generated_at: 2.hours.ago
    )
    feature_and_og_image = GeneratedImage.create!(
      imageable: topic,
      status: "ready",
      purpose: "feature_and_og",
      source_content_fingerprint: "fao",
      generated_at: 1.hour.ago
    )
    og_image = GeneratedImage.create!(
      imageable: topic,
      status: "ready",
      purpose: "og",
      source_content_fingerprint: "og",
      generated_at: 30.minutes.ago
    )

    assert_equal [ feature_and_og_image, feature_image ], GeneratedImage.usable_for(:feature).to_a
    assert_includes GeneratedImage.usable_for(:feature), feature_image
    assert_includes GeneratedImage.usable_for(:feature), feature_and_og_image
    assert_not_includes GeneratedImage.usable_for(:feature), og_image
  end

  test "newest scope orders generated_at desc nulls last then created_at desc" do
    topic = Topic.create!(name: "Test Topic 2b", status: "approved")

    null_generated_at = GeneratedImage.create!(
      imageable: topic,
      status: "ready",
      purpose: "feature_and_og",
      source_content_fingerprint: "null-generated-at",
      generated_at: nil,
      created_at: 1.minute.ago,
      updated_at: 1.minute.ago
    )
    older_generated_at = GeneratedImage.create!(
      imageable: topic,
      status: "ready",
      purpose: "feature_and_og",
      source_content_fingerprint: "older-generated-at",
      generated_at: 2.hours.ago,
      created_at: 2.hours.ago,
      updated_at: 2.hours.ago
    )
    newer_generated_at = GeneratedImage.create!(
      imageable: topic,
      status: "ready",
      purpose: "feature_and_og",
      source_content_fingerprint: "newer-generated-at",
      generated_at: 1.hour.ago,
      created_at: 1.hour.ago,
      updated_at: 1.hour.ago
    )

    assert_equal [ newer_generated_at, older_generated_at, null_generated_at ], GeneratedImage.ready.newest.to_a
  end

  test "usable_for default feature excludes og purpose" do
    topic = Topic.create!(name: "Test Topic 2e", status: "approved")
    feature_image = GeneratedImage.create!(
      imageable: topic,
      status: "ready",
      purpose: "feature",
      source_content_fingerprint: "feature",
      generated_at: 1.hour.ago
    )
    feature_and_og_image = GeneratedImage.create!(
      imageable: topic,
      status: "ready",
      purpose: "feature_and_og",
      source_content_fingerprint: "fao",
      generated_at: 30.minutes.ago
    )
    og_image = GeneratedImage.create!(
      imageable: topic,
      status: "ready",
      purpose: "og",
      source_content_fingerprint: "og",
      generated_at: 10.minutes.ago
    )

    assert_equal [ feature_and_og_image, feature_image ], GeneratedImage.usable_for(:feature).to_a
    assert_not_includes GeneratedImage.usable_for(:feature), og_image
    assert_includes GeneratedImage.usable_for(:og), og_image
  end

  test "generated_at nil does not outrank timestamped ready image" do
    topic = Topic.create!(name: "Test Topic 3", status: "approved")

    nil_image = GeneratedImage.create!(
      imageable: topic,
      status: "ready",
      purpose: "feature_and_og",
      source_content_fingerprint: "nil",
      generated_at: nil
    )
    timestamped_image = GeneratedImage.create!(
      imageable: topic,
      status: "ready",
      purpose: "feature_and_og",
      source_content_fingerprint: "ts",
      generated_at: 1.hour.ago
    )

    assert_equal timestamped_image, topic.current_generated_image(:og)
    assert_not_equal nil_image, topic.current_generated_image(:og)
  end

  test "Meeting current_generated_image works" do
    meeting = Meeting.create!(detail_page_url: "http://example.com/meeting-image", starts_at: Time.current)

    older = GeneratedImage.create!(
      imageable: meeting,
      status: "ready",
      purpose: "feature",
      source_content_fingerprint: "older",
      generated_at: 2.hours.ago
    )
    newer = GeneratedImage.create!(
      imageable: meeting,
      status: "ready",
      purpose: "feature",
      source_content_fingerprint: "newer",
      generated_at: 30.minutes.ago
    )

    assert_equal newer, meeting.current_generated_image
    assert_not_equal older, meeting.current_generated_image
  end

  test "validates retry_count is non-negative" do
    topic = Topic.create!(name: "Test Topic 4", status: "approved")
    image = GeneratedImage.new(imageable: topic, status: "ready", purpose: "feature")

    image.retry_count = -1

    assert_not image.valid?
    assert_includes image.errors[:retry_count], "must be greater than or equal to 0"
  end

  test "retry_available? allows one retry after first failure" do
    topic = Topic.create!(name: "Retry Topic", status: "approved")
    image = GeneratedImage.new(imageable: topic, status: "failed", purpose: "feature", retry_count: 1)

    assert_predicate image, :retry_available?
  end

  test "retry_available? rejects after second failure" do
    topic = Topic.create!(name: "Retry Topic 2", status: "approved")
    image = GeneratedImage.new(imageable: topic, status: "failed", purpose: "feature", retry_count: 2)

    assert_not image.retry_available?
  end

  test "rejects both source_summary and source_briefing" do
    topic = Topic.create!(name: "Test Topic 5", status: "approved")
    meeting = Meeting.create!(detail_page_url: "http://example.com/meeting-source", starts_at: Time.current)
    summary = MeetingSummary.create!(meeting: meeting, summary_type: "agenda_preview", content: "x")
    briefing = TopicBriefing.create!(topic: topic, headline: "x", editorial_content: "x", record_content: "x", generation_tier: "full")

    image = GeneratedImage.new(
      imageable: topic,
      status: "ready",
      purpose: "feature",
      source_generation_tier: "full",
      source_summary: summary,
      source_briefing: briefing
    )

    assert_not image.valid?
    assert_includes image.errors[:base], "cannot have both source_summary and source_briefing"
  end

  test "uploaded_by has a foreign key to users" do
    foreign_keys = ActiveRecord::Base.connection.foreign_keys(:generated_images)

    assert_includes foreign_keys.map(&:to_table), "users"
    assert_includes foreign_keys.map(&:column), "uploaded_by_id"
  end

  test "destroying source_summary nullifies generated image reference" do
    meeting = Meeting.create!(detail_page_url: "http://example.com/meeting-nullify-summary", starts_at: Time.current)
    summary = MeetingSummary.create!(meeting: meeting, summary_type: "agenda_preview", content: "x")
    topic = Topic.create!(name: "Test Topic Nullify Summary", status: "approved")
    image = GeneratedImage.create!(
      imageable: meeting,
      status: "ready",
      purpose: "feature",
      source_generation_tier: "full",
      source_summary: summary
    )

    summary.destroy!

    assert_predicate image.reload, :persisted?
    assert_nil image.source_summary_id
  end

  test "destroying source_briefing nullifies generated image reference" do
    topic = Topic.create!(name: "Test Topic Nullify Briefing", status: "approved")
    briefing = TopicBriefing.create!(topic: topic, headline: "x", editorial_content: "x", record_content: "x", generation_tier: "full")
    image = GeneratedImage.create!(
      imageable: topic,
      status: "ready",
      purpose: "feature",
      source_generation_tier: "full",
      source_briefing: briefing
    )

    briefing.destroy!

    assert_predicate image.reload, :persisted?
    assert_nil image.source_briefing_id
  end

  test "validates source_summary requires Meeting imageable" do
    topic = Topic.create!(name: "Test Topic 6", status: "approved")
    meeting = Meeting.create!(detail_page_url: "http://example.com/meeting-source-2", starts_at: Time.current)
    summary = MeetingSummary.create!(meeting: meeting, summary_type: "agenda_preview", content: "x")

    image = GeneratedImage.new(
      imageable: topic,
      status: "ready",
      purpose: "feature",
      source_generation_tier: "full",
      source_summary: summary
    )

    assert_not image.valid?
    assert_includes image.errors[:imageable], "must match source_summary.meeting"
  end

  test "validates source_summary exact meeting match" do
    meeting_a = Meeting.create!(detail_page_url: "http://example.com/meeting-source-a", starts_at: Time.current)
    meeting_b = Meeting.create!(detail_page_url: "http://example.com/meeting-source-b", starts_at: 1.hour.ago)
    summary = MeetingSummary.create!(meeting: meeting_b, summary_type: "agenda_preview", content: "x")

    image = GeneratedImage.new(
      imageable: meeting_a,
      status: "ready",
      purpose: "feature",
      source_generation_tier: "full",
      source_summary: summary
    )

    assert_not image.valid?
    assert_includes image.errors[:imageable], "must match source_summary.meeting"
  end

  test "validates source_briefing exact topic match" do
    meeting = Meeting.create!(detail_page_url: "http://example.com/meeting-source-3", starts_at: Time.current)
    topic_a = Topic.create!(name: "Test Topic 7", status: "approved")
    topic_b = Topic.create!(name: "Test Topic 8", status: "approved")
    briefing = TopicBriefing.create!(topic: topic_b, headline: "x", editorial_content: "x", record_content: "x", generation_tier: "full")

    image = GeneratedImage.new(
      imageable: meeting,
      status: "ready",
      purpose: "feature",
      source_generation_tier: "full",
      source_briefing: briefing
    )

    assert_not image.valid?
    assert_includes image.errors[:imageable], "must match source_briefing.topic"
  end

  test "validates source_briefing exact topic match for topic imageable" do
    topic_a = Topic.create!(name: "Test Topic 9", status: "approved")
    topic_b = Topic.create!(name: "Test Topic 10", status: "approved")
    briefing = TopicBriefing.create!(topic: topic_b, headline: "x", editorial_content: "x", record_content: "x", generation_tier: "full")

    image = GeneratedImage.new(
      imageable: topic_a,
      status: "ready",
      purpose: "feature",
      source_generation_tier: "full",
      source_briefing: briefing
    )

    assert_not image.valid?
    assert_includes image.errors[:imageable], "must match source_briefing.topic"
  end
end
