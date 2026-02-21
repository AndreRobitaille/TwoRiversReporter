require "test_helper"

module Admin
  class TopicsControllerDescriptionTest < ActionDispatch::IntegrationTest
    setup do
      @admin = User.create!(email_address: "admin@example.com", password: "password", admin: true, totp_enabled: true)
      @admin.ensure_totp_secret!

      post session_url, params: { email_address: "admin@example.com", password: "password" }
      follow_redirect!

      totp = ROTP::TOTP.new(@admin.totp_secret, issuer: "TwoRiversReporter")
      post mfa_session_url, params: { code: totp.now }
      follow_redirect!
    end

    test "nils description_generated_at when admin edits description" do
      topic = Topic.create!(
        name: "Water Main Replacement",
        description: "AI-generated description",
        description_generated_at: 1.hour.ago
      )

      patch admin_topic_path(topic), params: {
        topic: { description: "Admin-written description" }
      }

      topic.reload
      assert_equal "Admin-written description", topic.description
      assert_nil topic.description_generated_at
    end

    test "preserves description_generated_at when admin edits non-description fields" do
      generated_at = 1.hour.ago
      topic = Topic.create!(
        name: "Budget Review",
        description: "AI-generated description",
        description_generated_at: generated_at
      )

      patch admin_topic_path(topic), params: {
        topic: { importance: 5 }
      }

      topic.reload
      assert_equal 5, topic.importance
      assert_in_delta generated_at, topic.description_generated_at, 1.second
    end
  end
end
