require "test_helper"

module Admin
  class TopicsReviewTest < ActionDispatch::IntegrationTest
    setup do
      @admin = User.create!(email_address: "admin@example.com", password: "password", admin: true, totp_enabled: true)
      @admin.ensure_totp_secret!

      post session_url, params: { email_address: "admin@example.com", password: "password" }
      follow_redirect!

      totp = ROTP::TOTP.new(@admin.totp_secret, issuer: "TwoRiversReporter")
      post mfa_session_url, params: { code: totp.now }
      follow_redirect!

      # Create sample topics
      @proposed_topic = Topic.create!(name: "Proposed Topic", status: "proposed", review_status: "proposed")
      @approved_topic = Topic.create!(name: "Approved Topic", status: "approved", review_status: "approved")
      @blocked_topic = Topic.create!(name: "Blocked Topic", status: "blocked", review_status: "blocked")
    end

    test "should filter by review_status" do
      get admin_topics_url(review_status: "proposed")
      assert_response :success
      assert_select "a", text: @proposed_topic.name
      assert_select "a", text: @approved_topic.name, count: 0

      get admin_topics_url(review_status: "approved")
      assert_response :success
      assert_select "a", text: @proposed_topic.name, count: 0
      assert_select "a", text: @approved_topic.name
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
  end
end
