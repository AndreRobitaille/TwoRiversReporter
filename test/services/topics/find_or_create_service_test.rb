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
      assert_equal "canonical", topic.reuse_strategy
    end

    test "new topics default to canonical reuse strategy" do
      topic = Topics::FindOrCreateService.call("Another New Topic")

      assert_equal "canonical", topic.reuse_strategy
    end

    test "unsafe approved topics are excluded from reusable scope" do
      safe_topic = Topic.create!(name: "safe topic", status: "approved")
      unsafe_topic = Topic.create!(name: "unsafe topic", status: "approved", reuse_strategy: "unsafe_for_auto_reuse")

      assert_equal [safe_topic], Topic.reusable.order(:id).to_a
      assert_not_includes Topic.reusable, unsafe_topic
      assert_includes Topic.unsafe_for_auto_reuse, unsafe_topic
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

    test "exact reusable topic match wins before contextual routing" do
      reusable = Topic.create!(name: "downtown redevelopment", status: "approved")
      former_hamilton = Topic.create!(name: "former hamilton site redevelopment", status: "approved")

      topic = Topics::FindOrCreateService.call(
        "Downtown Redevelopment",
        context: { meeting_body: "planning commission", text: "Former Hamilton site" }
      )

      assert_equal reusable, topic
      assert_not_equal former_hamilton, topic
    end

    test "unsafe redevelopment label routes to former hamilton site when context is strong" do
      former_hamilton = Topic.create!(name: "former hamilton site redevelopment", status: "approved")

      topic = Topics::FindOrCreateService.call(
        "Redevelopment",
        context: { body_name: "former hamilton site", text: "Hamilton site redevelopment discussion" }
      )

      assert_equal former_hamilton, topic
    end

    test "unsafe redevelopment label does not route to hamilton without supporting context" do
      former_hamilton = Topic.create!(name: "former hamilton site redevelopment", status: "approved")

      topic = Topics::FindOrCreateService.call("Redevelopment")

      assert_not_equal former_hamilton, topic
      assert_nil topic if topic.is_a?(NilClass)
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

    test "exact alias fallback only returns approved canonical topics" do
      approved = Topic.create!(name: "approved topic", status: "approved")
      unsafe = Topic.create!(name: "unsafe topic", status: "approved", reuse_strategy: "unsafe_for_auto_reuse")
      TopicAlias.create!(name: "shared alias", topic: approved)
      TopicAlias.create!(name: "unsafe alias", topic: unsafe)

      topic = Topics::FindOrCreateService.call("Shared Alias")

      assert_equal approved, topic

      unsafe_topic = Topics::FindOrCreateService.call("Unsafe Alias")

      assert_not_equal unsafe, unsafe_topic
      assert_equal "unsafe alias", unsafe_topic.name
      assert_equal "proposed", unsafe_topic.status
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
