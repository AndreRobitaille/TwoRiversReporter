require "test_helper"

class GeneratedImages::TopicEligibilityTest < ActiveSupport::TestCase
  test "eligible when topic is homepage top-six and has briefing headline" do
    topic = Topic.create!(name: "Eligible Topic", status: "approved", reuse_strategy: "canonical", resident_impact_score: 5, last_activity_at: 1.day.ago)
    TopicBriefing.create!(topic: topic, headline: "Headline", generation_tier: "full")

    result = GeneratedImages::TopicEligibility.new(topic).call

    assert result.eligible?
    assert_nil result.reason
  end

  test "not eligible when not in selector" do
    topic = Topic.create!(name: "Ineligible Topic", status: "approved", reuse_strategy: "canonical", resident_impact_score: 3, last_activity_at: 1.day.ago)
    TopicBriefing.create!(topic: topic, headline: "Headline", generation_tier: "full")

    result = GeneratedImages::TopicEligibility.new(topic).call

    assert_not result.eligible?
    assert_equal "not in homepage top six", result.reason
  end

  test "not eligible without briefing headline" do
    topic = Topic.create!(name: "Missing Briefing Topic", status: "approved", reuse_strategy: "canonical", resident_impact_score: 5, last_activity_at: 1.day.ago)

    result = GeneratedImages::TopicEligibility.new(topic).call

    assert_not result.eligible?
    assert_equal "missing briefing", result.reason
  end
end
