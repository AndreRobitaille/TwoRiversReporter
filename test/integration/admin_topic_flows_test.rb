require "test_helper"
require "securerandom"

class AdminTopicFlowsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(
      email_address: "admin@example.com",
      password: "password",
      password_confirmation: "password",
      admin: true,
      totp_enabled: true
    )
    @admin.ensure_totp_secret!

    # Login
    post session_url, params: { email_address: @admin.email_address, password: "password" }
    follow_redirect! # to mfa_session/new

    totp = ROTP::TOTP.new(@admin.totp_secret, issuer: "TwoRiversMatters")
    post mfa_session_url, params: { code: totp.now }
    follow_redirect! # to admin_root

    suffix = SecureRandom.hex(4)
    @topic1_name = "Topic Alpha #{suffix}"
    @topic2_name = "Topic Beta #{suffix}"
    @topic3_name = "Topic Gamma #{suffix}"
    @topic1 = Topic.create!(name: @topic1_name, importance: 5, last_seen_at: 1.day.ago, status: "proposed", review_status: "proposed")
    @topic2 = Topic.create!(name: @topic2_name, importance: 3, last_seen_at: 2.days.ago, status: "proposed", review_status: "proposed")
    @topic3 = Topic.create!(name: @topic3_name, importance: 8, last_seen_at: 3.days.ago, status: "proposed", review_status: "proposed")
  end

  test "can view topic inbox" do
    get admin_topics_url
    assert_response :success

    assert_select "h1.page-title", text: "Topic Inbox"
    assert_select "form.admin-topics-filters"
    assert_select "table.admin-topics-table"
    assert_select "a[href*='sort=name']", text: "Topic"
    assert_select "a[href*='sort=mention_count']", text: "Mentions"
    assert_select "a[href=?]", admin_topic_path(@topic1), text: @topic1_name.downcase
    assert_select "a[href=?]", admin_topic_path(@topic2), text: @topic2_name.downcase
    assert_select "a[href=?]", admin_topic_path(@topic3), text: @topic3_name.downcase
    assert_select "a.btn--secondary[href=?]", admin_topic_path(@topic1), text: "Open Topic"
    assert_select "a.btn--secondary[href=?]", admin_topic_path(@topic2), text: "Open Topic"
    assert_select "a.btn--secondary[href=?]", admin_topic_path(@topic3), text: "Open Topic"
    assert_match "Signals", response.body
  end

  test "can search for topics via json" do
    get search_admin_topics_url(q: @topic1_name)
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 1, json.length
    assert_equal @topic1.id, json[0]["id"]
    assert_equal @topic1_name.downcase, json[0]["name"]
  end

  test "can search for topics via json by alias" do
    TopicAlias.create!(topic: @topic1, name: "finance")

    get search_admin_topics_url(q: "fin")

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal [ @topic1.id ], json.map { |row| row["id"] }
  end

  test "can update importance inline" do
    patch admin_topic_url(@topic1), params: { topic: { importance: 9 } }
    # Without referer, redirects to fallback (index)
    assert_redirected_to admin_topics_path
    @topic1.reload
    assert_equal 9, @topic1.importance
  end

  test "can merge topic into another" do
    # Merge Topic B into Topic A
    meeting = Meeting.create!(
      body_name: "City Council",
      meeting_type: "Regular",
      starts_at: Time.current,
      status: "minutes_posted",
      detail_page_url: "http://example.com/meeting/#{SecureRandom.hex(6)}"
    )
    agenda_item = AgendaItem.create!(meeting: meeting, number: "1", title: "Item 1", order_index: 1)
    AgendaItemTopic.create!(topic: @topic2, agenda_item: agenda_item)

    post merge_admin_topic_url(@topic2), params: { target_topic_id: @topic1.id }

    # Redirects to target topic show page
    assert_redirected_to admin_topic_url(@topic1)

    assert_raises(ActiveRecord::RecordNotFound) { @topic2.reload }

    assert TopicAlias.exists?(name: @topic2_name.downcase, topic_id: @topic1.id)
    assert_equal 1, @topic1.reload.topic_appearances.count
  end

  test "can create alias" do
    post create_alias_admin_topic_url(@topic1), params: { name: "Alias A" }
    assert_redirected_to admin_topic_url(@topic1)
    assert TopicAlias.exists?(name: "alias a", topic_id: @topic1.id)
  end
end
