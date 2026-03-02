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

  test "show renders topics section with ongoing and new subsections" do
    get meeting_url(@meeting)
    assert_response :success

    assert_select "h2", text: "Topics in This Meeting"
    assert_select "h3", text: "Ongoing"
    assert_select "h3", text: "New This Meeting"
  end

  test "show renders empty state when no approved topics" do
    AgendaItemTopic.destroy_all
    get meeting_url(@meeting)
    assert_response :success

    assert_select ".section-empty", text: "No topics have been identified for this meeting."
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

    assert_select ".meeting-headline", text: /Council approved the budget/
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

  test "show renders documents section with empty state" do
    @meeting.meeting_documents.destroy_all
    get meeting_url(@meeting)
    assert_response :success

    assert_select ".section-empty", text: "No documents available for this meeting."
  end
end
