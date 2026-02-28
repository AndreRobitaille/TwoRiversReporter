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

  test "coming up card shows high-impact topics with upcoming_headline" do
    @active_topic.update!(resident_impact_score: 4)
    TopicBriefing.create!(
      topic: @active_topic,
      headline: "TIF district expanded last month",
      upcoming_headline: "TIF district expansion vote at Council, Mar 3",
      generation_tier: "full"
    )

    get root_url
    assert_response :success
    assert_match "Coming Up", response.body
    assert_match "TIF district expansion vote at Council, Mar 3", response.body
    # Should NOT show the backward-looking headline in Coming Up
    assert_no_match "expanded last month", response.body.split("What Happened").last.to_s
  end

  test "coming up card hidden when no qualifying topics" do
    get root_url
    assert_response :success
    assert_no_match "Coming Up", response.body
  end

  test "coming up falls back to description when no upcoming_headline" do
    @active_topic.update!(resident_impact_score: 4, description: "Tax incentive district downtown")
    TopicBriefing.create!(
      topic: @active_topic,
      headline: "Some past headline",
      upcoming_headline: nil,
      generation_tier: "full"
    )

    get root_url
    assert_response :success
    assert_match "Tax incentive district downtown", response.body
  end

  test "what happened card shows recent high-impact decisions with headline" do
    @recurring_topic.update!(resident_impact_score: 3)
    agenda_item = AgendaItem.create!(meeting: @past_meeting, title: "Rate Vote")
    AgendaItemTopic.create!(topic: @recurring_topic, agenda_item: agenda_item)
    Motion.create!(
      agenda_item: agenda_item, meeting: @past_meeting,
      description: "Approve rate increase", outcome: "approved"
    )
    TopicBriefing.create!(
      topic: @recurring_topic,
      headline: "Water rates increased 8% for all residents",
      generation_tier: "full"
    )

    get root_url
    assert_response :success
    assert_match "What Happened", response.body
    assert_match "Water rates increased 8% for all residents", response.body
  end

  test "what happened card hidden when no qualifying topics" do
    get root_url
    assert_response :success
    assert_no_match "What Happened", response.body
  end

  test "what happened card appears before coming up card" do
    @active_topic.update!(resident_impact_score: 4)
    @recurring_topic.update!(resident_impact_score: 3)
    agenda_item = AgendaItem.create!(meeting: @past_meeting, title: "Vote")
    AgendaItemTopic.create!(topic: @recurring_topic, agenda_item: agenda_item)
    Motion.create!(agenda_item: agenda_item, meeting: @past_meeting, description: "Vote", outcome: "approved")

    get root_url
    assert_response :success

    what_happened_pos = response.body.index("What Happened")
    coming_up_pos = response.body.index("Coming Up")
    assert what_happened_pos < coming_up_pos, "What Happened should appear before Coming Up"
  end

  test "coming up applies meeting diversity — max 2 per meeting" do
    # Create 4 topics all in the same future meeting
    topics = 4.times.map do |i|
      topic = Topic.create!(
        name: "topic #{i}",
        status: "approved",
        lifecycle_status: "active",
        resident_impact_score: 5 - i
      )
      item = AgendaItem.create!(meeting: @future_meeting, title: "Item #{i}")
      AgendaItemTopic.create!(topic: topic, agenda_item: item)
      TopicAppearance.create!(
        topic: topic, meeting: @future_meeting, agenda_item: item,
        appeared_at: @future_meeting.starts_at, body_name: @future_meeting.body_name,
        evidence_type: "agenda_item"
      )
      topic
    end

    # Create a topic in a different meeting
    other_meeting = Meeting.create!(
      body_name: "Plan Commission", starts_at: 5.days.from_now,
      detail_page_url: "http://example.com/other"
    )
    other_topic = Topic.create!(
      name: "other meeting topic", status: "approved",
      lifecycle_status: "active", resident_impact_score: 3
    )
    other_item = AgendaItem.create!(meeting: other_meeting, title: "Other Item")
    AgendaItemTopic.create!(topic: other_topic, agenda_item: other_item)
    TopicAppearance.create!(
      topic: other_topic, meeting: other_meeting, agenda_item: other_item,
      appeared_at: other_meeting.starts_at, body_name: other_meeting.body_name,
      evidence_type: "agenda_item"
    )

    get root_url
    assert_response :success

    # Extract just the Coming Up card content
    assert_select ".card--warm .card-body" do |card|
      card_text = card.text
      same_meeting_count = topics.count { |t| card_text.include?(t.name) }
      assert same_meeting_count <= 2, "Expected at most 2 topics from same meeting in Coming Up, got #{same_meeting_count}"
      assert_includes card_text, "other meeting topic"
    end
  end

  test "renders successfully with no data" do
    TopicAppearance.destroy_all
    AgendaItemTopic.destroy_all
    AgendaItem.destroy_all
    TopicStatusEvent.destroy_all
    Motion.destroy_all
    Meeting.destroy_all
    Topic.destroy_all

    get root_url
    assert_response :success
    assert_no_match "Coming Up", response.body
    assert_no_match "What Happened", response.body
    assert_select "p", text: /No upcoming meetings scheduled/
    assert_select "p", text: /No recent meetings/
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
    @active_topic.update!(resident_impact_score: 3)
    get root_url
    assert_response :success

    assert_select ".tag", text: "downtown tif district"
  end

  test "does not show meetings outside time windows" do
    get root_url
    assert_response :success

    old_url = meeting_path(@old_meeting)
    assert_select "a[href='#{old_url}']", count: 0
  end

  test "shows search all meetings link" do
    get root_url
    assert_response :success

    assert_select "a[href='#{meetings_path}']", minimum: 1
  end

  test "meeting row shows only topics with impact >= 2" do
    low_impact_topic = Topic.create!(
      name: "minor procedure change",
      status: "approved",
      lifecycle_status: "active",
      resident_impact_score: 1
    )
    high_impact_topic = Topic.create!(
      name: "major road closure",
      status: "approved",
      lifecycle_status: "active",
      resident_impact_score: 3
    )

    item_low = AgendaItem.create!(meeting: @future_meeting, title: "Procedure")
    AgendaItemTopic.create!(topic: low_impact_topic, agenda_item: item_low)

    item_high = AgendaItem.create!(meeting: @future_meeting, title: "Road Work")
    AgendaItemTopic.create!(topic: high_impact_topic, agenda_item: item_high)

    get root_url
    assert_response :success

    assert_select ".tag--topic", text: "major road closure"
    assert_select ".tag--topic", text: "minor procedure change", count: 0
  end

  test "meeting row shows no pills when no topics meet impact threshold" do
    # All existing topics have nil impact score
    get root_url
    assert_response :success

    # No "No topics yet" text should appear
    assert_select ".meeting-topics-col .text-muted", count: 0
  end

  test "meeting within 3-hour buffer stays in upcoming section" do
    # Create a meeting that started 2 hours ago (within 3-hour buffer)
    recent_meeting = Meeting.create!(
      body_name: "Zoning Board",
      meeting_type: "Regular",
      starts_at: 2.hours.ago,
      status: "upcoming",
      detail_page_url: "http://example.com/recent-buffer"
    )

    get root_url
    assert_response :success

    # The meeting should appear in upcoming, not recently completed
    assert_select "section" do |sections|
      upcoming_section = sections.find { |s| s.text.include?("Upcoming Meetings") }
      assert upcoming_section.text.include?("Zoning Board"), "Expected Zoning Board in upcoming section"
    end
  end
end
