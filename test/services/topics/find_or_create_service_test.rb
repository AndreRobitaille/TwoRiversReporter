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

      assert_equal [ safe_topic ], Topic.reusable.order(:id).to_a
      assert_not_includes Topic.reusable, unsafe_topic
      assert_includes Topic.unsafe_for_auto_reuse, unsafe_topic
    end

    test "returns existing topic (exact match)" do
      existing = Topic.create!(name: "existing topic", status: "approved")
      topic = Topics::FindOrCreateService.call("Existing Topic")
      assert_equal existing, topic
    end

    test "glued aliases match when trigram similarity is under the cutoff" do
      right_of_way = Topic.create!(name: "right of way", status: "approved")
      TopicAlias.create!(topic: right_of_way, name: "rightofway")
      use_permits = Topic.create!(name: "right of way use permits", status: "approved")
      TopicAlias.create!(topic: use_permits, name: "rightofway use permits")

      assert_operator trigram_similarity("rightofway", "right of way"), :<, Topics::FindOrCreateService::SIMILARITY_THRESHOLD
      assert_operator trigram_similarity("rightofway use permits", "right of way use permits"), :<, Topics::FindOrCreateService::SIMILARITY_THRESHOLD

      assert_no_difference [ "Topic.count", "TopicAlias.count" ] do
        assert_equal right_of_way, Topics::FindOrCreateService.call("rightofway")
        assert_equal use_permits, Topics::FindOrCreateService.call("rightofway use permits")
      end
    end

    test "folds a new hyphenated name into the spaced form" do
      topic = Topics::FindOrCreateService.call("right-of-way")

      assert_equal "right of way", topic.name
      assert_equal "right of way", topic.canonical_name
    end

    test "returns existing topic via alias (exact match)" do
      existing = Topic.create!(name: "main topic", status: "approved")
      TopicAlias.create!(name: "aliased topic", topic: existing)

      topic = Topics::FindOrCreateService.call("Aliased Topic")
      assert_equal existing, topic
    end

    test "skips an exact topic after it is blocked without a blocklist entry" do
      existing = Topic.create!(name: "mishicot area ambulance coverage plan", status: "approved")
      assert_equal existing, Topics::FindOrCreateService.call("Mishicot Area Ambulance Coverage Plan")

      existing.update!(status: "blocked")

      assert_no_difference [ "Topic.count", "TopicAlias.count" ] do
        assert_nil Topics::FindOrCreateService.call("Mishicot Area Ambulance Coverage Plan")
      end
      assert_equal "blocked", existing.reload.status
    end

    test "returns an existing proposed topic without approving or duplicating it" do
      existing = Topics::FindOrCreateService.call("New Ambulance Coverage Plan")

      assert_no_difference [ "Topic.count", "TopicAlias.count" ] do
        assert_equal existing, Topics::FindOrCreateService.call("NEW AMBULANCE COVERAGE PLAN")
      end
      assert_equal "proposed", existing.reload.status
      assert_equal "proposed", existing.review_status
    end

    test "exact reusable topic match wins before contextual routing" do
      reusable = Topic.create!(name: "downtown redevelopment", status: "approved")
      former_hamilton = Topic.create!(name: "former hamilton site redevelopment", status: "approved")

      topic = Topics::FindOrCreateService.call(
        "Downtown Redevelopment",
        meeting_body_name: "planning commission",
        document_text: "Former Hamilton site"
      )

      assert_equal reusable, topic
      assert_not_equal former_hamilton, topic
    end

    test "unsafe redevelopment label routes to former hamilton site when context is strong" do
      former_hamilton = Topic.create!(name: "former hamilton site", status: "approved")
      TopicBlocklist.create!(name: "redevelopment", reason: "broad umbrella label")

      topic = Topics::FindOrCreateService.call(
        "Redevelopment",
        item_title: "Former Hamilton property rezoning",
        item_summary: "fischer parcel visioning for the former hamilton site",
        meeting_body_name: "planning commission",
        document_text: "former hamilton site redevelopment discussion"
      )

      assert_equal former_hamilton, topic
    end

    test "blocklisted redevelopment still routes to former hamilton site with strong context" do
      former_hamilton = Topic.create!(name: "former hamilton site", status: "approved")
      TopicBlocklist.create!(name: "redevelopment", reason: "broad umbrella label")

      topic = Topics::FindOrCreateService.call(
        "Redevelopment",
        item_title: "Former Hamilton site parcel update",
        item_summary: "Hamilton site review for the former hamilton property",
        meeting_body_name: "planning commission",
        document_text: "parcel and hamilton site discussion"
      )

      assert_equal former_hamilton, topic
    end

    test "unsafe exact-name topic with no route fails safely" do
      unsafe = Topic.create!(name: "redevelopment", status: "approved", reuse_strategy: "unsafe_for_auto_reuse")

      topic = Topics::FindOrCreateService.call("Redevelopment")

      assert_nil topic
      assert_equal unsafe, Topic.find_by(name: "redevelopment")
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

    private

    def trigram_similarity(left, right)
      Topic.connection.select_value(
        Topic.sanitize_sql_array([ "SELECT similarity(?, ?)", left, right ])
      ).to_f
    end
  end
end
