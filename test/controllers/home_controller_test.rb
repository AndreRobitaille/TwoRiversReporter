require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  setup do
    @council_meeting = Meeting.create!(
      body_name: "City Council Meeting",
      starts_at: 5.days.ago,
      detail_page_url: "http://example.com/council"
    )

    @high_topic = Topic.create!(
      name: "lead service lines",
      status: "approved",
      lifecycle_status: "active",
      resident_impact_score: 5,
      last_activity_at: 3.days.ago,
      description: "Replacing aging lead water pipes"
    )

    @mid_topic = Topic.create!(
      name: "municipal borrowing",
      status: "approved",
      lifecycle_status: "active",
      resident_impact_score: 4,
      last_activity_at: 4.days.ago,
      description: "How the city funds big projects"
    )

    @low_topic = Topic.create!(
      name: "building permits",
      status: "approved",
      lifecycle_status: "active",
      resident_impact_score: 2,
      last_activity_at: 6.days.ago,
      description: "Permit fees and process"
    )

    # Appearances linking topics to meetings
    item1 = AgendaItem.create!(meeting: @council_meeting, title: "Lead Lines")
    AgendaItemTopic.create!(topic: @high_topic, agenda_item: item1)
    TopicAppearance.create!(
      topic: @high_topic, meeting: @council_meeting, agenda_item: item1,
      appeared_at: @council_meeting.starts_at, body_name: @council_meeting.body_name,
      evidence_type: "agenda_item"
    )

    item2 = AgendaItem.create!(meeting: @council_meeting, title: "Borrowing")
    AgendaItemTopic.create!(topic: @mid_topic, agenda_item: item2)
    TopicAppearance.create!(
      topic: @mid_topic, meeting: @council_meeting, agenda_item: item2,
      appeared_at: @council_meeting.starts_at, body_name: @council_meeting.body_name,
      evidence_type: "agenda_item"
    )

    item3 = AgendaItem.create!(meeting: @council_meeting, title: "Permits")
    AgendaItemTopic.create!(topic: @low_topic, agenda_item: item3)
    TopicAppearance.create!(
      topic: @low_topic, meeting: @council_meeting, agenda_item: item3,
      appeared_at: @council_meeting.starts_at, body_name: @council_meeting.body_name,
      evidence_type: "agenda_item"
    )
  end

  test "renders successfully" do
    get root_url
    assert_response :success
  end

  test "top stories show highest impact topics" do
    TopicBriefing.create!(topic: @high_topic, headline: "Lead line headline", generation_tier: "full")

    get root_url
    assert_response :success
    assert_select ".top-story .story-topic", text: /lead service lines/i
    assert_select ".top-story .story-headline", text: /Lead line headline/
    assert_select ".top-story .read-more", text: /Meeting details/
  end

  test "top stories limited to 2 items" do
    third = Topic.create!(
      name: "property taxes", status: "approved", lifecycle_status: "active",
      resident_impact_score: 5, last_activity_at: 2.days.ago
    )

    get root_url
    assert_response :success
    assert_select ".top-story, .second-story", count: 2
  end

  test "top stories require impact >= 4" do
    @high_topic.update!(resident_impact_score: 3)
    @mid_topic.update!(resident_impact_score: 3)

    get root_url
    assert_response :success
    assert_select ".top-story", count: 0
  end

  test "wire shows mid-impact topics excluding top stories" do
    get root_url
    assert_response :success

    assert_select ".wire-card .wire-topic, .wire-list-item .list-topic", minimum: 1
    wire_text = css_select(".wire-zone").text
    assert_no_match(/lead service lines/i, wire_text)
  end

  test "wire items sorted by impact desc" do
    wire_topic_a = Topic.create!(
      name: "sidewalk program", status: "approved", lifecycle_status: "active",
      resident_impact_score: 3, last_activity_at: 5.days.ago
    )
    wire_topic_b = Topic.create!(
      name: "dnr grant", status: "approved", lifecycle_status: "active",
      resident_impact_score: 2, last_activity_at: 4.days.ago
    )

    get root_url
    body = response.body
    sidewalk_pos = body.index("sidewalk program")
    dnr_pos = body.index("dnr grant")
    if sidewalk_pos && dnr_pos
      assert sidewalk_pos < dnr_pos, "Higher impact topic should appear first in wire"
    end
  end

  test "next up shows council meetings and work sessions" do
    council = Meeting.create!(
      body_name: "City Council Meeting",
      starts_at: 10.days.from_now,
      detail_page_url: "http://example.com/next-council"
    )
    work_session = Meeting.create!(
      body_name: "City Council Work Session",
      starts_at: 17.days.from_now,
      detail_page_url: "http://example.com/next-ws"
    )
    Meeting.create!(
      body_name: "Plan Commission Meeting",
      starts_at: 8.days.from_now,
      detail_page_url: "http://example.com/plan"
    )

    get root_url
    assert_response :success
    assert_select ".nextup-card", count: 2
    nextup_text = css_select(".nextup-zone").text
    assert_match(/City Council/i, nextup_text)
    assert_match(/Work Session/i, nextup_text)
    assert_no_match(/Plan Commission/i, nextup_text)
  end

  test "next up limited to 2 meetings" do
    3.times do |i|
      Meeting.create!(
        body_name: (i.even? ? "City Council Meeting" : "City Council Work Session"),
        starts_at: (10 + i * 7).days.from_now,
        detail_page_url: "http://example.com/next-#{i}"
      )
    end

    get root_url
    assert_select ".nextup-card", maximum: 2
  end

  test "escape hatches link to topics and meetings" do
    get root_url
    assert_select "a[href='#{topics_path}']", minimum: 1
    assert_select "a[href='#{meetings_path}']", minimum: 1
  end

  test "renders with no data" do
    TopicAppearance.destroy_all
    AgendaItemTopic.destroy_all
    AgendaItem.destroy_all
    TopicStatusEvent.destroy_all
    Motion.destroy_all
    Meeting.destroy_all
    Topic.destroy_all

    get root_url
    assert_response :success
  end

  test "wire zone omitted when no qualifying wire topics" do
    # Remove low-impact topic so only 2 high-impact remain (both go to top stories)
    @low_topic.destroy!

    get root_url
    assert_response :success
    assert_select ".wire-zone", count: 0
  end

  test "topics outside 30-day window excluded" do
    @high_topic.update!(last_activity_at: 45.days.ago)
    @mid_topic.update!(last_activity_at: 45.days.ago)

    get root_url
    assert_select ".top-story", count: 0
  end

  test "blocked topics excluded" do
    blocked = Topic.create!(
      name: "blocked thing", status: "blocked", lifecycle_status: "active",
      resident_impact_score: 5, last_activity_at: 1.day.ago
    )

    get root_url
    assert_no_match(/blocked thing/, response.body)
  end

  test "topic description shown when present" do
    TopicBriefing.create!(topic: @high_topic, headline: "headline", generation_tier: "full")

    get root_url
    assert_select ".story-desc", text: /Replacing aging lead water pipes/
  end
end
