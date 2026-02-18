require "test_helper"

module Admin
  class TopicsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @admin = User.create!(email_address: "admin@example.com", password: "password", admin: true, totp_enabled: true)
      @admin.ensure_totp_secret!

      post session_url, params: { email_address: "admin@example.com", password: "password" }
      follow_redirect!

      totp = ROTP::TOTP.new(@admin.totp_secret, issuer: "TwoRiversReporter")
      post mfa_session_url, params: { code: totp.now }
      follow_redirect!

      @topic = Topic.create!(name: "Topic A")
    end

    test "should get index" do
      get admin_topics_url
      assert_response :success
    end

    test "updating resident impact score sets override timestamp" do
      topic = Topic.create!(name: "Impact Test", status: "approved")

      patch admin_topic_path(topic), params: {
        topic: { resident_impact_score: "4" }
      }

      topic.reload
      assert_equal 4, topic.resident_impact_score
      assert_not_nil topic.resident_impact_overridden_at
      assert_in_delta Time.current, topic.resident_impact_overridden_at, 5.seconds
    end
  end
end
