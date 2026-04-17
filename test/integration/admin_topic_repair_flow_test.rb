require "test_helper"
require "securerandom"

class AdminTopicRepairFlowTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "admin@example.com", password: "password", admin: true, totp_enabled: true)
    @admin.ensure_totp_secret!

    post session_url, params: { email_address: @admin.email_address, password: "password" }
    follow_redirect!

    totp = ROTP::TOTP.new(@admin.totp_secret, issuer: "TwoRiversMatters")
    post mfa_session_url, params: { code: totp.now }
    follow_redirect!
  end

  test "retires bad umbrella topic from repair workspace" do
    topic = Topic.create!(name: "lakeshore community foundation partnership #{SecureRandom.hex(4)}", status: "approved", review_status: "approved")

    post retire_admin_topic_url(topic), params: { reason: "Bad umbrella topic" }

    assert_redirected_to admin_topic_url(topic)
    assert_equal "blocked", topic.reload.status
    assert_equal "blocked", topic.review_status
    assert_equal "retired", TopicReviewEvent.find_by!(topic: topic, action: "retired").action
    assert_equal "Bad umbrella topic", TopicReviewEvent.find_by!(topic: topic, action: "retired").reason
    assert TopicBlocklist.exists?(name: Topic.normalize_name(topic.name))
  end

  test "refuses to retire without a reason" do
    topic = Topic.create!(name: "lakeshore community foundation partnership #{SecureRandom.hex(4)}", status: "approved", review_status: "approved")

    post retire_admin_topic_url(topic), params: { reason: "" }

    assert_redirected_to admin_topic_url(topic)
    assert_equal "Reason is required.", flash[:alert]
    assert_equal "approved", topic.reload.status
    assert_equal "approved", topic.review_status
    assert_nil TopicReviewEvent.find_by(topic: topic, action: "retired")
  end
end
