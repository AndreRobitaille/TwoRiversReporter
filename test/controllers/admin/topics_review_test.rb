require "test_helper"
require "securerandom"

module Admin
  class TopicsReviewTest < ActionDispatch::IntegrationTest
    setup do
      @admin = User.create!(email_address: "admin@example.com", admin: true)
      sign_in_as_admin(@admin)

      # Create sample topics
      @proposed_topic = Topic.create!(name: "Proposed Topic", status: "proposed", review_status: "proposed")
      @approved_topic = Topic.create!(name: "Approved Topic", status: "approved", review_status: "approved")
      @blocked_topic = Topic.create!(name: "Blocked Topic", status: "blocked", review_status: "blocked")
    end

    def proposed_topic
      Topic.create!(name: "proposed #{SecureRandom.hex(4)}",
                    status: "proposed", review_status: "proposed", lifecycle_status: "active")
    end

    test "should filter by review_status" do
      get admin_topics_url(review_status: "proposed")
      assert_response :success
      assert_select "a[href=?]", admin_topic_path(@proposed_topic), text: @proposed_topic.name
      assert_select "a", text: @approved_topic.name, count: 0

      get admin_topics_url(review_status: "approved")
      assert_response :success
      assert_select "a", text: @proposed_topic.name, count: 0
      assert_select "a[href=?]", admin_topic_path(@approved_topic), text: @approved_topic.name
    end

    test "should approve proposed topic" do
      assert_difference "TopicReviewEvent.count", 1 do
        post approve_admin_topic_url(@proposed_topic)
      end

      @proposed_topic.reload
      assert_equal "approved", @proposed_topic.status
      assert_equal "approved", @proposed_topic.review_status

      event = TopicReviewEvent.order(:created_at).last
      assert_equal @admin, event.user
      assert_equal @proposed_topic, event.topic
      assert_equal "approved", event.action
    end

    test "should block proposed topic" do
      assert_difference "TopicReviewEvent.count", 1 do
        post block_admin_topic_url(@proposed_topic)
      end

      @proposed_topic.reload
      assert_equal "blocked", @proposed_topic.status
      assert_equal "blocked", @proposed_topic.review_status

      event = TopicReviewEvent.order(:created_at).last
      assert_equal "blocked", event.action
    end

    test "blocking a topic adds its name to blocklist" do
      topic = Topic.create!(name: "Public Comment Period", status: "proposed", review_status: "proposed")

      assert_difference "TopicBlocklist.count" do
        post block_admin_topic_url(topic)
      end

      assert TopicBlocklist.exists?(name: "public comment period"),
        "Blocked topic name should be added to blocklist"
    end

    test "blocking a topic does not duplicate existing blocklist entry" do
      topic = Topic.create!(name: "Duplicate Entry", status: "proposed", review_status: "proposed")
      TopicBlocklist.create!(name: "duplicate entry")

      assert_no_difference "TopicBlocklist.count" do
        post block_admin_topic_url(topic)
      end
    end

    test "should mark approved topic as needs review" do
      assert_difference "TopicReviewEvent.count", 1 do
        post needs_review_admin_topic_url(@approved_topic)
      end

      @approved_topic.reload
      assert_equal "proposed", @approved_topic.status
      assert_equal "proposed", @approved_topic.review_status

      event = TopicReviewEvent.order(:created_at).last
      assert_equal "needs_review", event.action
    end

    test "should bulk approve" do
      topic2 = Topic.create!(name: "Proposed 2", status: "proposed", review_status: "proposed")

      assert_difference "TopicReviewEvent.count", 2 do
        post bulk_update_admin_topics_url, params: {
          topic_ids: [ @proposed_topic.id, topic2.id ],
          reason: "dupe cleanup",
          commit: "Approve Selected"
        }
      end

      @proposed_topic.reload
      topic2.reload

      assert_equal "approved", @proposed_topic.review_status
      assert_equal "approved", topic2.review_status

      assert TopicReviewEvent.where(action: "approved", reason: "dupe cleanup").count >= 2
    end

    test "should bulk block" do
      topic2 = Topic.create!(name: "Proposed 2", status: "proposed", review_status: "proposed")

      assert_difference "TopicReviewEvent.count", 2 do
        post bulk_update_admin_topics_url, params: {
          topic_ids: [ @proposed_topic.id, topic2.id ],
          commit: "Block Selected"
        }
      end

      @proposed_topic.reload
      topic2.reload

      assert_equal "blocked", @proposed_topic.review_status
      assert_equal "blocked", topic2.review_status

      assert TopicReviewEvent.where(action: "blocked").count >= 2
    end

    test "should bulk mark for review" do
      @approved_topic.update!(status: "approved", review_status: "approved")

      assert_difference "TopicReviewEvent.count", 1 do
        post bulk_update_admin_topics_url, params: {
          topic_ids: [ @approved_topic.id ],
          commit: "Mark for Review"
        }
      end

      @approved_topic.reload
      assert_equal "proposed", @approved_topic.review_status
    end

    # --- Task 12: triage actions restored to the inbox row itself ---

    test "each inbox row carries a dom id turbo can replace" do
      topic = proposed_topic
      get admin_topics_url

      assert_select "tbody#topic_#{topic.id}", count: 1
    end

    test "a proposed topic offers approve and block from the index" do
      topic = proposed_topic
      get admin_topics_url

      assert_select "form[action=?]", approve_admin_topic_path(topic)
      assert_select "form[action=?]", block_admin_topic_path(topic)
    end

    test "an approved topic offers needs-review and block" do
      topic = Topic.create!(name: "approved #{SecureRandom.hex(4)}", status: "approved", review_status: "approved")
      get admin_topics_url

      assert_select "form[action=?]", needs_review_admin_topic_path(topic)
      assert_select "form[action=?]", block_admin_topic_path(topic)
    end

    test "a blocked topic offers unblock" do
      topic = Topic.create!(name: "blocked #{SecureRandom.hex(4)}", status: "blocked", review_status: "blocked")
      get admin_topics_url

      assert_select "form[action=?]", unblock_admin_topic_path(topic)
    end

    test "every row offers pin or unpin" do
      pinned = Topic.create!(name: "pinned #{SecureRandom.hex(4)}", status: "approved", review_status: "approved", pinned: true)
      unpinned = Topic.create!(name: "unpinned #{SecureRandom.hex(4)}", status: "approved", review_status: "approved")
      get admin_topics_url

      assert_select "form[action=?]", unpin_admin_topic_path(pinned)
      assert_select "form[action=?]", pin_admin_topic_path(unpinned)
    end

    test "approving actually approves and returns a replaceable row" do
      topic = proposed_topic

      post approve_admin_topic_path(topic), as: :turbo_stream

      assert_response :success
      assert_equal "approved", topic.reload.status
      assert_equal "approved", topic.review_status
      assert_match "turbo-stream", response.media_type
      assert_match "topic_#{topic.id}", response.body,
        "the turbo stream must target the id the index actually rendered"
    end

    test "blocking blocks the topic" do
      topic = proposed_topic
      post block_admin_topic_path(topic), as: :turbo_stream
      assert_equal "blocked", topic.reload.status
    end

    test "pinning pins the topic" do
      topic = Topic.create!(name: "topin #{SecureRandom.hex(4)}", status: "approved", review_status: "approved")
      post pin_admin_topic_path(topic), as: :turbo_stream
      assert topic.reload.pinned?
    end

    test "row_for builds a row from a topic" do
      topic = proposed_topic
      row = Admin::Topics::InboxQuery.row_for(topic)

      assert_equal topic.id, row.topic_id
      assert_equal topic.name, row.name
      assert_equal "proposed", row.review_status
    end

    # --- Fix round 1: update's turbo_stream branch must match its html
    # sibling's status handling, or an invalid save silently succeeds (200)
    # and renders a row built from the invalid in-memory @topic. ---

    test "updating via turbo_stream on success replaces the row" do
      topic = Topic.create!(name: "valid name #{SecureRandom.hex(4)}", status: "approved", review_status: "approved")

      patch admin_topic_path(topic), params: { topic: { description: "A fresh description" } }, as: :turbo_stream

      assert_response :success
      assert_match "turbo-stream", response.media_type
      assert_match "topic_#{topic.id}", response.body
      assert_equal "A fresh description", topic.reload.description
    end

    test "updating via turbo_stream with an invalid name returns unprocessable_entity and does not corrupt the row" do
      original_name = "valid name #{SecureRandom.hex(4)}"
      topic = Topic.create!(name: original_name, status: "approved", review_status: "approved")

      patch admin_topic_path(topic), params: { topic: { name: "" } }, as: :turbo_stream

      assert_response :unprocessable_entity
      assert_equal original_name.downcase, topic.reload.name, "the invalid save must not have persisted"
      assert_no_match ">#{admin_topic_path(topic)}<", response.body,
        "an invalid save must not fall back to rendering the topic's own URL as the row's visible link text"
    end
  end
end
