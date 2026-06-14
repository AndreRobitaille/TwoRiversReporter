require "test_helper"

class GeneratedImages::HomepageTopicSelectorTest < ActiveSupport::TestCase
  test "returns only top six reusable recent high impact topics" do
    7.times do |i|
      Topic.create!(
        name: "Image Topic #{i}",
        status: "approved",
        reuse_strategy: "canonical",
        resident_impact_score: 4,
        last_activity_at: i.hours.ago
      )
    end

    topics = GeneratedImages::HomepageTopicSelector.new.call

    assert_equal 6, topics.size
    assert topics.all? { |topic| topic.resident_impact_score >= 4 }
  end

  test "orders by impact then recency then id" do
    older_high = Topic.create!(name: "Older High", status: "approved", reuse_strategy: "canonical", resident_impact_score: 5, last_activity_at: 2.days.ago)
    newer_high = Topic.create!(name: "Newer High", status: "approved", reuse_strategy: "canonical", resident_impact_score: 5, last_activity_at: 1.day.ago)
    lower = Topic.create!(name: "Lower", status: "approved", reuse_strategy: "canonical", resident_impact_score: 4, last_activity_at: 1.hour.ago)

    topics = GeneratedImages::HomepageTopicSelector.new.call

    assert_equal [ newer_high.id, older_high.id, lower.id ], topics.map(&:id)
  end

  test "include? only returns true for selected topics" do
    selected = Topic.create!(name: "Selected", status: "approved", reuse_strategy: "canonical", resident_impact_score: 4, last_activity_at: 1.day.ago)
    excluded = Topic.create!(name: "Excluded", status: "approved", reuse_strategy: "canonical", resident_impact_score: 3, last_activity_at: 1.day.ago)

    selector = GeneratedImages::HomepageTopicSelector.new

    assert selector.include?(selected)
    assert_not selector.include?(excluded)
  end
end
