require "test_helper"

class MeetingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @meeting = Meeting.create!(
      body_name: "City Council",
      meeting_type: "Regular",
      starts_at: 3.days.ago,
      status: "minutes_posted",
      detail_page_url: "http://example.com/meeting-nav-test"
    )

    # Ongoing topic (2+ appearances)
    @ongoing_topic = Topic.create!(
      name: "downtown tif district",
      status: "approved",
      lifecycle_status: "active",
      last_activity_at: 2.days.ago
    )
    item1 = AgendaItem.create!(meeting: @meeting, title: "TIF Discussion")
    AgendaItemTopic.create!(topic: @ongoing_topic, agenda_item: item1)
    # AgendaItemTopic callback auto-creates a TopicAppearance for this meeting.
    # Add a second appearance on another meeting to make this topic "ongoing".
    other_meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 30.days.ago, status: "minutes_posted",
      detail_page_url: "http://example.com/old-meeting-nav"
    )
    TopicAppearance.create!(
      topic: @ongoing_topic, meeting: other_meeting,
      appeared_at: other_meeting.starts_at, body_name: "City Council",
      evidence_type: "agenda_item"
    )

    # New topic (1 appearance)
    @new_topic = Topic.create!(
      name: "new sidewalk project",
      status: "approved",
      lifecycle_status: "active",
      last_activity_at: 2.days.ago
    )
    item2 = AgendaItem.create!(meeting: @meeting, title: "Sidewalk Plan")
    AgendaItemTopic.create!(topic: @new_topic, agenda_item: item2)
    # AgendaItemTopic callback auto-creates the single TopicAppearance.

    # Blocked topic (should be excluded)
    @blocked_topic = Topic.create!(
      name: "blocked issue",
      status: "blocked",
      lifecycle_status: "active"
    )
    item3 = AgendaItem.create!(meeting: @meeting, title: "Blocked Item")
    AgendaItemTopic.create!(topic: @blocked_topic, agenda_item: item3)
  end

  # --- Index tests ---

  test "index assigns enriched upcoming meetings with topics" do
    upcoming = Meeting.create!(
      body_name: "Plan Commission Meeting",
      meeting_type: "Regular",
      starts_at: 5.days.from_now,
      status: "upcoming",
      detail_page_url: "http://example.com/upcoming-1"
    )
    # Add a topic so it's "enriched"
    topic = Topic.create!(name: "test upcoming topic", status: "approved", lifecycle_status: "active", last_activity_at: 1.day.ago)
    item = AgendaItem.create!(meeting: upcoming, title: "Test")
    AgendaItemTopic.create!(topic: topic, agenda_item: item)

    get meetings_url
    assert_response :success
    assert_includes assigns(:upcoming_enriched), upcoming
  end

  test "index assigns enriched recent meetings with summaries" do
    MeetingSummary.create!(meeting: @meeting, summary_type: "minutes_recap", generation_data: { "headline" => "Test" })
    get meetings_url
    assert_response :success
    assert_includes assigns(:recent_enriched), @meeting
  end

  test "index exposes thin meetings without summaries" do
    get meetings_url
    assert_response :success
    # @meeting has no summary, so it's thin
    assert assigns(:recent_thin).size >= 1
  end

  test "index assigns search_results when q param present" do
    get meetings_url, params: { q: "City Council" }
    assert_response :success
    assert assigns(:search_results).any?
  end

  test "index search_results is nil when no q param" do
    get meetings_url
    assert_response :success
    assert_nil assigns(:search_results)
  end

  test "show assigns ongoing and new topics" do
    get meeting_url(@meeting)
    assert_response :success

    assert assigns(:ongoing_topics).include?(@ongoing_topic)
    assert assigns(:new_topics).include?(@new_topic)
  end

  test "show excludes non-approved topics" do
    get meeting_url(@meeting)
    assert_response :success

    all_topics = assigns(:ongoing_topics) + assigns(:new_topics)
    refute all_topics.include?(@blocked_topic)
  end

  test "show renders topic doors on agenda items" do
    # Need a summary with item_details matching an agenda item to trigger doors
    MeetingSummary.create!(
      meeting: @meeting,
      summary_type: "minutes_recap",
      generation_data: {
        "headline" => "Test",
        "item_details" => [ { "agenda_item_title" => "TIF Discussion", "summary" => "Discussed TIF" } ]
      }
    )
    get meeting_url(@meeting)
    assert_response :success

    assert_select ".meeting-topic-door"
  end

  test "show renders document links in header" do
    get meeting_url(@meeting)
    assert_response :success

    assert_select ".meeting-article-docs"
  end

  test "show assigns summary with generation_data" do
    summary = MeetingSummary.create!(
      meeting: @meeting,
      summary_type: "minutes_recap",
      generation_data: { "headline" => "Test headline" }
    )

    get meeting_url(@meeting)
    assert_response :success
    assert_equal summary, assigns(:summary)
  end

  test "show assigns nil summary when none exists" do
    get meeting_url(@meeting)
    assert_response :success
    assert_nil assigns(:summary)
  end

  test "show renders headline from generation_data" do
    MeetingSummary.create!(
      meeting: @meeting,
      summary_type: "minutes_recap",
      generation_data: { "headline" => "Council approved the budget 5-2." }
    )

    get meeting_url(@meeting)
    assert_response :success

    assert_select ".meeting-article-lede", text: /Council approved the budget/
  end

  test "show renders empty state when no summary exists" do
    get meeting_url(@meeting)
    assert_response :success

    assert_select ".section-empty", text: "No summary available for this meeting yet."
  end

  test "show renders legacy markdown when no generation_data" do
    MeetingSummary.create!(
      meeting: @meeting,
      summary_type: "minutes_recap",
      content: "## Old Recap\n\nThis is the old markdown."
    )

    get meeting_url(@meeting)
    assert_response :success

    assert_select ".meeting-legacy-recap"
  end

  test "index search matches on body_name" do
    get meetings_url, params: { q: "City Council" }
    assert_response :success
    assert assigns(:search_results).include?(@meeting)
  end

  test "index search matches on topic name" do
    get meetings_url, params: { q: "downtown tif" }
    assert_response :success
    assert assigns(:search_results).include?(@meeting)
  end

  test "index search matches on year" do
    year = @meeting.starts_at.year.to_s
    get meetings_url, params: { q: year }
    assert_response :success
    assert assigns(:search_results).include?(@meeting)
  end

  test "index search matches on month name" do
    month = @meeting.starts_at.strftime("%B").downcase
    get meetings_url, params: { q: month }
    assert_response :success
    assert assigns(:search_results).include?(@meeting)
  end

  test "index search returns empty for no matches" do
    get meetings_url, params: { q: "xyznonexistent999" }
    assert_response :success
    assert assigns(:search_results).empty?
  end

  # --- Index view integration tests ---

  test "index renders Coming Up when enriched upcoming exist" do
    upcoming = Meeting.create!(
      body_name: "City Council Meeting",
      meeting_type: "Regular",
      starts_at: 3.days.from_now,
      status: "upcoming",
      detail_page_url: "http://example.com/upcoming-render"
    )
    topic = Topic.create!(name: "render test topic", status: "approved", lifecycle_status: "active", last_activity_at: 1.day.ago)
    item = AgendaItem.create!(meeting: upcoming, title: "Test")
    AgendaItemTopic.create!(topic: topic, agenda_item: item)

    get meetings_url
    assert_response :success
    assert_select ".section-label", text: "Coming Up"
  end

  test "index renders What Happened when enriched recent exist" do
    MeetingSummary.create!(meeting: @meeting, summary_type: "minutes_recap", generation_data: { "headline" => "Test" })
    get meetings_url
    assert_response :success
    assert_select ".section-label", text: "What Happened"
  end

  test "index shows empty note when no enriched upcoming" do
    get meetings_url
    assert_response :success
    assert_select ".meetings-empty-note"
  end

  test "index renders headline in recent card" do
    MeetingSummary.create!(
      meeting: @meeting,
      summary_type: "minutes_recap",
      generation_data: { "headline" => "Big news from council" }
    )
    get meetings_url
    assert_response :success
    assert_select ".meetings-card-headline", text: /Big news from council/
  end

  test "index renders topic pills on upcoming card" do
    upcoming = Meeting.create!(
      body_name: "City Council Meeting",
      meeting_type: "Regular",
      starts_at: 3.days.from_now,
      status: "upcoming",
      detail_page_url: "http://example.com/upcoming-pills"
    )
    topic = Topic.create!(
      name: "test pill topic",
      status: "approved",
      lifecycle_status: "active",
      last_activity_at: 1.day.ago
    )
    item = AgendaItem.create!(meeting: upcoming, title: "Test Item")
    AgendaItemTopic.create!(topic: topic, agenda_item: item)

    get meetings_url
    assert_response :success
    assert_select ".meetings-topic-pill", text: "test pill topic"
  end

  test "index search shows helpful empty state" do
    get meetings_url, params: { q: "absolutelynothingtofind" }
    assert_response :success
    assert_select ".meetings-search-empty"
    assert_select ".meetings-search-hint"
  end

  test "index search replaces zones with results" do
    get meetings_url, params: { q: "City Council" }
    assert_response :success
    assert_select ".section-label", text: "Results"
    refute_select ".section-label", text: "Coming Up"
    refute_select ".section-label", text: "What Happened"
  end

  # --- Summary fallback chain tests ---

  test "assigns @summary from agenda_preview when no higher-tier summary exists" do
    @meeting.meeting_summaries.create!(
      summary_type: "agenda_preview",
      generation_data: { "headline" => "Agenda preview headline", "source_type" => "agenda" }
    )

    get meeting_url(@meeting)
    assert_response :success
    assert_equal "agenda_preview", assigns(:summary).summary_type
  end

  test "prefers packet_analysis over agenda_preview" do
    @meeting.meeting_summaries.create!(
      summary_type: "agenda_preview",
      generation_data: { "headline" => "Agenda preview", "source_type" => "agenda" }
    )
    @meeting.meeting_summaries.create!(
      summary_type: "packet_analysis",
      generation_data: { "headline" => "Packet analysis", "source_type" => "packet" }
    )

    get meeting_url(@meeting)
    assert_response :success
    assert_equal "packet_analysis", assigns(:summary).summary_type
  end

  test "prefers minutes_recap over agenda_preview" do
    @meeting.meeting_summaries.create!(
      summary_type: "agenda_preview",
      generation_data: { "headline" => "Agenda preview" }
    )
    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: { "headline" => "Minutes" }
    )

    get meeting_url(@meeting)
    assert_response :success
    assert_equal "minutes_recap", assigns(:summary).summary_type
  end
end
