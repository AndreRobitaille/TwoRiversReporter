require "test_helper"

class TopicsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @meeting = Meeting.create!(
      body_name: "City Council",
      meeting_type: "Regular",
      starts_at: Time.current,
      status: "parsed",
      detail_page_url: "http://example.com/m1"
    )

    @agenda_item = AgendaItem.create!(meeting: @meeting, title: "Item 1")

    @active_topic = Topic.create!(name: "Active Topic", lifecycle_status: "active", status: "approved")
    @dormant_topic = Topic.create!(name: "Dormant Topic", lifecycle_status: "dormant", status: "approved")
    @resolved_topic = Topic.create!(name: "Resolved Topic", lifecycle_status: "resolved", status: "approved")
    @recurring_topic = Topic.create!(name: "Recurring Topic", lifecycle_status: "recurring", status: "approved")

    # Associate topics with agenda items
    AgendaItemTopic.create!(topic: @active_topic, agenda_item: @agenda_item)
    AgendaItemTopic.create!(topic: @dormant_topic, agenda_item: @agenda_item)
    AgendaItemTopic.create!(topic: @resolved_topic, agenda_item: @agenda_item)
    AgendaItemTopic.create!(topic: @recurring_topic, agenda_item: @agenda_item)

    # Update last_activity_at manually as backfill job does it
    now = Time.current
    @active_topic.update!(last_activity_at: now)
    @recurring_topic.update!(last_activity_at: now - 1.day)
    @dormant_topic.update!(last_activity_at: now - 2.days)
    @resolved_topic.update!(last_activity_at: now - 3.days)
  end

  test "index groups topics by lifecycle status" do
    get topics_url
    assert_response :success

    # Check for group headers
    assert_select "h2", text: /Active Topics/
    assert_select "h2", text: /Recurring Topics/
    assert_select "h2", text: /Dormant Topics/
    assert_select "h2", text: /Resolved Topics/

    # Check ordering of groups (Active -> Recurring -> Dormant -> Resolved)
    body = response.body
    active_idx = body.index("Active Topics")
    recurring_idx = body.index("Recurring Topics")
    dormant_idx = body.index("Dormant Topics")
    resolved_idx = body.index("Resolved Topics")

    assert active_idx < recurring_idx, "Active should come before Recurring"
    assert recurring_idx < dormant_idx, "Recurring should come before Dormant"
    assert dormant_idx < resolved_idx, "Dormant should come before Resolved"
  end

  test "index shows counts in headers" do
    get topics_url
    assert_response :success
    assert_select "h2", text: /Active Topics/ do
      assert_select "span", text: "(1)"
    end
  end

  test "index shows recently updated topics ordered by recency" do
    get topics_url
    assert_response :success

    titles = css_select("section#recent-topics .card-title").map { |node| node.text.strip }
    assert_equal [ @active_topic.name, @recurring_topic.name, @dormant_topic.name, @resolved_topic.name ], titles
  end
end
