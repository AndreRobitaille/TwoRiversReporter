require "test_helper"

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

    totp = ROTP::TOTP.new(@admin.totp_secret, issuer: "TwoRiversReporter")
    post mfa_session_url, params: { code: totp.now }
    follow_redirect! # to admin_root

    @topic1 = Topic.create!(name: "Topic A", importance: 5, last_seen_at: 1.day.ago)
    @topic2 = Topic.create!(name: "Topic B", importance: 3, last_seen_at: 2.days.ago)
    @topic3 = Topic.create!(name: "Topic C", importance: 8, last_seen_at: 3.days.ago)
  end

  test "can view topics list with sorting" do
    get admin_topics_url
    assert_response :success
    assert_select "tr", count: 4 # header + 3 rows

    # Default sort by last_seen_at desc (Topic A is most recent seen)
    # Actually wait, topic1 seen 1 day ago, topic2 2 days ago, topic3 3 days ago.
    # So A, B, C.

    # Test sorting by importance desc
    get admin_topics_url(sort: "importance", direction: "desc")
    assert_response :success
    # Order should be C (8), A (5), B (3)
    # I can check order by checking ids or content order.

    # Simple check:
    rows = css_select("tbody tr")
    assert_match /topic c/i, rows[0].text
    assert_match /topic a/i, rows[1].text
    assert_match /topic b/i, rows[2].text
  end

  test "can search for topics via json" do
    get search_admin_topics_url(q: "topic a")
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 1, json.length
    assert_equal @topic1.id, json[0]["id"]
    assert_equal "topic a", json[0]["name"]
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
    post merge_admin_topic_url(@topic2), params: { target_topic_id: @topic1.id }

    # Redirects to target topic show page
    assert_redirected_to admin_topic_url(@topic1)

    assert_raises(ActiveRecord::RecordNotFound) { @topic2.reload }

    assert TopicAlias.exists?(name: "topic b", topic_id: @topic1.id)
  end

  test "can create alias" do
    post create_alias_admin_topic_url(@topic1), params: { name: "Alias A" }
    assert_redirected_to admin_topic_url(@topic1)
    assert TopicAlias.exists?(name: "alias a", topic_id: @topic1.id)
  end
end
