require "test_helper"

class TopicBriefingTest < ActiveSupport::TestCase
  setup do
    @topic = Topic.create!(name: "Downtown Parking Changes", status: "approved")
    @meeting = Meeting.create!(
      body_name: "City Council",
      starts_at: 1.day.ago,
      detail_page_url: "http://example.com/meeting"
    )
  end

  test "valid with required fields" do
    briefing = TopicBriefing.new(
      topic: @topic,
      headline: "Council approved modified parking plan 4-3",
      generation_tier: "full"
    )
    assert briefing.valid?
  end

  test "requires topic" do
    briefing = TopicBriefing.new(headline: "Test", generation_tier: "full")
    assert_not briefing.valid?
    assert briefing.errors[:topic].any?
  end

  test "requires headline" do
    briefing = TopicBriefing.new(topic: @topic, generation_tier: "full")
    assert_not briefing.valid?
    assert briefing.errors[:headline].any?
  end

  test "requires generation_tier" do
    briefing = TopicBriefing.new(topic: @topic, headline: "Test")
    assert_not briefing.valid?
    assert briefing.errors[:generation_tier].any?
  end

  test "generation_tier must be valid value" do
    briefing = TopicBriefing.new(
      topic: @topic,
      headline: "Test",
      generation_tier: "invalid"
    )
    assert_not briefing.valid?
  end

  test "one briefing per topic" do
    TopicBriefing.create!(
      topic: @topic,
      headline: "First",
      generation_tier: "headline_only"
    )
    duplicate = TopicBriefing.new(
      topic: @topic,
      headline: "Second",
      generation_tier: "full"
    )
    assert_not duplicate.valid?
  end

  test "topic has_one topic_briefing" do
    briefing = TopicBriefing.create!(
      topic: @topic,
      headline: "Test headline",
      generation_tier: "headline_only"
    )
    assert_equal briefing, @topic.topic_briefing
  end

  test "stores triggering meeting" do
    briefing = TopicBriefing.create!(
      topic: @topic,
      headline: "Test",
      generation_tier: "full",
      triggering_meeting: @meeting,
      last_full_generation_at: Time.current
    )
    assert_equal @meeting, briefing.triggering_meeting
  end

  test "generation_data defaults to empty hash" do
    briefing = TopicBriefing.create!(
      topic: @topic,
      headline: "Test",
      generation_tier: "headline_only"
    )
    assert_equal({}, briefing.generation_data)
  end
end
