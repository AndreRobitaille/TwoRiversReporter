require "test_helper"

module Topics
  class FindOrCreateServiceTest < ActiveSupport::TestCase
    setup do
      # Clear data to ensure clean state
      AgendaItemTopic.destroy_all
      TopicAlias.destroy_all
      Topic.destroy_all
      TopicBlocklist.destroy_all
    end

    test "creates a new topic when none exists" do
      topic = Topics::FindOrCreateService.call("New Topic")
      assert_instance_of Topic, topic
      assert_equal "new topic", topic.name
      assert_equal "proposed", topic.status
      assert_equal "proposed", topic.review_status
    end

    test "returns existing topic (exact match)" do
      existing = Topic.create!(name: "existing topic", status: "approved")
      topic = Topics::FindOrCreateService.call("Existing Topic")
      assert_equal existing, topic
    end

    test "returns existing topic via alias (exact match)" do
      existing = Topic.create!(name: "main topic", status: "approved")
      TopicAlias.create!(name: "aliased topic", topic: existing)

      topic = Topics::FindOrCreateService.call("Aliased Topic")
      assert_equal existing, topic
    end

    test "creates alias and returns existing topic for similar input" do
      existing = Topic.create!(name: "very unique topic name", status: "approved")

      # "very unique topic nam" (typo) -> should be similar
      # pg_trgm needs to be enabled in test DB.
      # This test assumes Postgres with pg_trgm.

      topic = Topics::FindOrCreateService.call("very unique topic nam")

      assert_equal existing, topic
      assert TopicAlias.exists?(name: "very unique topic nam", topic: existing)
    end

    test "returns nil if blocked" do
      TopicBlocklist.create!(name: "blocked topic")
      topic = Topics::FindOrCreateService.call("Blocked Topic")
      assert_nil topic
    end

    test "returns nil if blocked (case insensitive)" do
      TopicBlocklist.create!(name: "blocked topic")
      topic = Topics::FindOrCreateService.call("BLOCKED TOPIC")
      assert_nil topic
    end
  end
end
