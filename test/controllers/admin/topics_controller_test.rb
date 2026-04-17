require "test_helper"
require "securerandom"

module Admin
  class TopicsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @admin = User.create!(email_address: "admin@example.com", password: "password", admin: true, totp_enabled: true)
      @admin.ensure_totp_secret!

      post session_url, params: { email_address: "admin@example.com", password: "password" }
      follow_redirect!

      totp = ROTP::TOTP.new(@admin.totp_secret, issuer: "TwoRiversMatters")
      post mfa_session_url, params: { code: totp.now }
      follow_redirect!

      @topic = Topic.create!(name: "Topic A #{SecureRandom.hex(4)}")
    end

    test "index renders inbox rows with repair entrypoint" do
      Topic.create!(name: "budget shortfall #{SecureRandom.hex(4)}", status: "proposed", review_status: "proposed", lifecycle_status: "active")
      cleanup_topic = Topic.create!(name: "cleanup candidate #{SecureRandom.hex(4)}", status: "approved", review_status: "approved", lifecycle_status: "dormant", description: "Needs cleanup")
      TopicAlias.create!(topic: cleanup_topic, name: "cleanup alt #{SecureRandom.hex(3)}")

      get admin_topics_url

      assert_response :success
      assert_match "Topic Inbox", response.body
      assert_select "form[action=?][method=get]", admin_topics_path
      assert_select "input[name=q]"
      assert_select "select[name=status]"
      assert_select "select[name=review_status]"
      assert_select "select[name=lifecycle_status]"
      assert_select "a[href*='sort=name']", text: /Topic/
      assert_select "a[href*='sort=mention_count']", text: /Mentions/
      assert_select "table"
      assert_select "th", text: "Topic"
      assert_select "th", text: "Signals"
      assert_select "th", text: "Mentions"
      assert_select "a[href=?]", admin_topic_path(@topic), text: @topic.name
      assert_select "a[href=?]", admin_topic_path(@topic), text: "Open Topic"
      assert_match /cleanup candidate/i, response.body
      assert_match /cleanup alt/i, response.body
      assert_no_match "Recently changed ·", response.body
      assert_no_match "Needs cleanup", response.body
    end

    test "index sorts by mentions from header param" do
      lower = Topic.create!(name: "lower mentions #{SecureRandom.hex(4)}", status: "approved", review_status: "approved")
      higher = Topic.create!(name: "higher mentions #{SecureRandom.hex(4)}", status: "approved", review_status: "approved")
      meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: Time.current, status: "minutes_posted", detail_page_url: "http://example.com/meeting/#{SecureRandom.hex(6)}")
      2.times do |index|
        agenda_item = AgendaItem.create!(meeting: meeting, number: index + 1, title: "Item #{index + 1}", order_index: index + 1)
        AgendaItemTopic.create!(topic: higher, agenda_item: agenda_item)
      end
      agenda_item = AgendaItem.create!(meeting: meeting, number: 9, title: "Item 9", order_index: 9)
      AgendaItemTopic.create!(topic: lower, agenda_item: agenda_item)

      get admin_topics_url(sort: "mention_count")

      assert_response :success
      assert_match(/higher mentions.*lower mentions/m, response.body)
    end

    test "index filters by lifecycle status" do
      active_topic = Topic.create!(name: "active cleanup #{SecureRandom.hex(4)}", status: "approved", review_status: "approved", lifecycle_status: "active")
      Topic.create!(name: "resolved cleanup #{SecureRandom.hex(4)}", status: "approved", review_status: "approved", lifecycle_status: "resolved")

      get admin_topics_url(lifecycle_status: "active")

      assert_response :success
      assert_select "a[href=?]", admin_topic_path(active_topic)
      assert_no_match /resolved cleanup/i, response.body
    end

    test "should get index" do
      get admin_topics_url
      assert_response :success
    end

    test "updating resident impact score sets override timestamp" do
      topic = Topic.create!(name: "Impact Test #{SecureRandom.hex(4)}", status: "approved")

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
