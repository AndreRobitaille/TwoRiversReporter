require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Future meeting with topics
    @future_meeting = Meeting.create!(
      body_name: "City Council",
      meeting_type: "Regular",
      starts_at: 3.days.from_now,
      status: "upcoming",
      detail_page_url: "http://example.com/future"
    )

    # Past meeting with topics
    @past_meeting = Meeting.create!(
      body_name: "Plan Commission",
      meeting_type: "Regular",
      starts_at: 3.days.ago,
      status: "minutes_posted",
      detail_page_url: "http://example.com/past"
    )

    # Meeting outside the windows
    @old_meeting = Meeting.create!(
      body_name: "City Council",
      meeting_type: "Regular",
      starts_at: 60.days.ago,
      status: "minutes_posted",
      detail_page_url: "http://example.com/old"
    )

    # Topics
    @active_topic = Topic.create!(
      name: "downtown tif district",
      status: "approved",
      lifecycle_status: "active",
      last_activity_at: 2.days.ago
    )

    @recurring_topic = Topic.create!(
      name: "Water Utility Rates",
      status: "approved",
      lifecycle_status: "recurring",
      last_activity_at: 5.days.ago
    )

    @blocked_topic = Topic.create!(
      name: "Blocked Topic",
      status: "blocked",
      lifecycle_status: "active"
    )

    # Agenda items linking topics to meetings
    @future_agenda_item = AgendaItem.create!(meeting: @future_meeting, title: "TIF Discussion")
    AgendaItemTopic.create!(topic: @active_topic, agenda_item: @future_agenda_item)

    @past_agenda_item = AgendaItem.create!(meeting: @past_meeting, title: "Water Rates Review")
    AgendaItemTopic.create!(topic: @recurring_topic, agenda_item: @past_agenda_item)

    # Topic appearance for active topic on future meeting
    TopicAppearance.create!(
      topic: @active_topic,
      meeting: @future_meeting,
      agenda_item: @future_agenda_item,
      appeared_at: @future_meeting.starts_at,
      body_name: @future_meeting.body_name,
      evidence_type: "agenda_item"
    )
  end

  test "renders successfully with data" do
    get root_url
    assert_response :success
  end

  test "renders successfully with no data" do
    TopicAppearance.destroy_all
    AgendaItemTopic.destroy_all
    AgendaItem.destroy_all
    TopicStatusEvent.destroy_all
    Meeting.destroy_all
    Topic.destroy_all

    get root_url
    assert_response :success

    assert_select "p", text: /No active topics with upcoming meetings/
    assert_select "p", text: /No recent topic activity detected/
    assert_select "p", text: /No upcoming meetings scheduled/
    assert_select "p", text: /No recent meetings/
  end

  test "shows worth watching topics with upcoming appearances" do
    get root_url
    assert_response :success

    # Active topic with future meeting should appear
    assert_match "downtown tif district", response.body
  end

  test "does not show blocked topics in worth watching" do
    # Give blocked topic a future appearance too
    agenda_item = AgendaItem.create!(meeting: @future_meeting, title: "Blocked Item")
    AgendaItemTopic.create!(topic: @blocked_topic, agenda_item: agenda_item)
    TopicAppearance.create!(
      topic: @blocked_topic,
      meeting: @future_meeting,
      agenda_item: agenda_item,
      appeared_at: @future_meeting.starts_at,
      body_name: @future_meeting.body_name,
      evidence_type: "agenda_item"
    )

    get root_url
    assert_response :success

    assert_no_match "Blocked Topic", response.body
  end

  test "shows recent signals from TopicStatusEvents" do
    TopicStatusEvent.create!(
      topic: @recurring_topic,
      lifecycle_status: "recurring",
      evidence_type: "agenda_recurrence",
      occurred_at: 5.days.ago
    )

    get root_url
    assert_response :success

    # Should show the signal badge
    assert_select ".badge", text: "Resurfaced"
  end

  test "shows upcoming meetings grouped by week" do
    get root_url
    assert_response :success

    # Future meeting should appear in upcoming section
    assert_match "City Council", response.body
    assert_select "h3", text: /This Week|Next Week|#{@future_meeting.starts_at.strftime('%b')}/
  end

  test "shows recent meetings grouped by week" do
    get root_url
    assert_response :success

    # Past meeting should appear
    assert_match "Plan Commission", response.body
  end

  test "shows topic tags on meeting rows" do
    get root_url
    assert_response :success

    assert_select ".tag", text: "downtown tif district"
  end

  test "does not show meetings outside time windows" do
    get root_url
    assert_response :success

    # The old meeting (60 days ago) should not have a View link in the meeting tables
    # but the body name might appear in topic cards, so check specifically in table rows
    old_url = meeting_path(@old_meeting)
    assert_select "a[href='#{old_url}']", count: 0
  end

  test "shows search all meetings link" do
    get root_url
    assert_response :success

    assert_select "a[href='#{meetings_path}']", minimum: 1
  end
end
