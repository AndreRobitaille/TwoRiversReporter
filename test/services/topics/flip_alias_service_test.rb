require "test_helper"

module Topics
  class FlipAliasServiceTest < ActiveSupport::TestCase
    test "swaps the topic name with its only alias" do
      topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")
      alias_record = TopicAlias.create!(topic: topic, name: "harbor project")

      flipped_topic = FlipAliasService.new(topic: topic).call

      assert_equal topic, flipped_topic
      assert_equal "harbor project", topic.reload.name
      assert_equal "harbor project", topic.canonical_name
      assert_equal "harbor-project", topic.slug
      assert_equal [ "harbor dredging" ], topic.topic_aliases.order(:name).pluck(:name)
      assert_equal "harbor dredging", alias_record.reload.name
      assert_equal topic, alias_record.reload.topic
    end

    test "refuses to make a glued legacy alias the canonical name" do
      topic = Topic.create!(name: "right of way", status: "approved", review_status: "approved")
      TopicAlias.create!(topic: topic, name: "rightofway")

      error = assert_raises(ArgumentError) { FlipAliasService.new(topic: topic).call }

      assert_equal "A glued legacy alias cannot become the canonical topic name", error.message
      assert_equal "right of way", topic.reload.name
      assert_equal [ "rightofway" ], topic.topic_aliases.pluck(:name)
    end

    test "still swaps a spaced alias onto a glued canonical name" do
      topic = Topic.create!(name: "rightofway", status: "approved", review_status: "approved")
      TopicAlias.create!(topic: topic, name: "right of way")

      FlipAliasService.new(topic: topic).call

      assert_equal "right of way", topic.reload.name
      assert_equal [ "rightofway" ], topic.topic_aliases.pluck(:name)
    end

    test "raises when topic does not have exactly one alias" do
      topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")
      TopicAlias.create!(topic: topic, name: "harbor project")
      TopicAlias.create!(topic: topic, name: "harbor works")

      error = assert_raises(ArgumentError) { FlipAliasService.new(topic: topic).call }

      assert_equal "Topic must have exactly one alias", error.message
      assert_equal "harbor dredging", topic.reload.name
    end
  end
end
