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

  test "index shows active topics sorted by last_activity_at descending" do
    # Create multiple active topics with old activity (>30d) so they skip hero
    topic_a = Topic.create!(name: "Topic A", lifecycle_status: "active", status: "approved", last_activity_at: 35.days.ago)
    topic_b = Topic.create!(name: "Topic B", lifecycle_status: "active", status: "approved", last_activity_at: 40.days.ago)
    topic_c = Topic.create!(name: "Topic C", lifecycle_status: "active", status: "approved", last_activity_at: 45.days.ago)
    [ topic_a, topic_b, topic_c ].each { |t| AgendaItemTopic.create!(topic: t, agenda_item: @agenda_item) }

    get topics_url
    assert_response :success

    titles = css_select("#all-topics .card-title").map { |node| node.text.strip }
    assert_equal [ "topic a", "topic b", "topic c" ], titles
  end

  test "index paginates topics with default page size" do
    # Create 22 active topics with old activity (>30d) so they all skip hero
    22.times do |i|
      topic = Topic.create!(
        name: "Paginated Topic #{i.to_s.rjust(2, '0')}",
        lifecycle_status: "active",
        status: "approved",
        last_activity_at: (31 + i).days.ago
      )
      AgendaItemTopic.create!(topic: topic, agenda_item: @agenda_item)
    end

    get topics_url
    assert_response :success

    # Should show 20 of 22 topics in main list
    cards = css_select("#all-topics .card")
    assert_equal 20, cards.size

    # Should show count indicator
    assert_select ".topics-count", text: /Showing.*of 22/

    # Should show "Show more" button
    assert_select "a", text: /Show more/
  end

  test "index does not show 'Show more' when all topics fit on one page" do
    # Only @active_topic exists as active — it's in hero, main list is empty
    get topics_url
    assert_response :success

    assert_select "a", text: /Show more/, count: 0
  end

  test "index page 2 returns turbo stream with appended topics" do
    # Create 22 active topics with old activity (>30d) so they all skip hero
    22.times do |i|
      topic = Topic.create!(
        name: "Stream Topic #{i.to_s.rjust(2, '0')}",
        lifecycle_status: "active",
        status: "approved",
        last_activity_at: (31 + i).days.ago
      )
      AgendaItemTopic.create!(topic: topic, agenda_item: @agenda_item)
    end

    get topics_url(page: 2, format: :turbo_stream)
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html; charset=utf-8", response.content_type
    assert_match "all-topics-cards", response.body
    assert_match "all-topics-page", response.body
  end

  test "index shows hero topics ranked by impact with nulls last" do
    # @active_topic has nil impact score — should sort after scored topics
    scored_topic = Topic.create!(
      name: "Scored Topic", lifecycle_status: "active", status: "approved",
      resident_impact_score: 3, last_activity_at: 2.days.ago
    )
    AgendaItemTopic.create!(topic: scored_topic, agenda_item: @agenda_item)

    get topics_url
    assert_response :success

    titles = css_select("#hero-topics .card-title").map { |node| node.text.strip }
    assert_equal "scored topic", titles.first
    # @active_topic (nil score) should come after scored topics
    assert_equal @active_topic.name, titles.last
  end

  test "index shows lifecycle badges on topic cards" do
    # Only active topics are shown — assert only Active badge
    get topics_url
    assert_response :success

    assert_select ".badge", text: "Active"
    assert_select ".badge", text: "Dormant", count: 0
    assert_select ".badge", text: "Resolved", count: 0
    assert_select ".badge", text: "Recurring", count: 0
  end

  test "index highlights topic with recent continuity signal" do
    # Use @active_topic (shown in hero) with a deferral signal
    TopicStatusEvent.create!(
      topic: @active_topic,
      lifecycle_status: "active",
      evidence_type: "deferral_signal",
      occurred_at: 5.days.ago
    )

    get topics_url
    assert_response :success

    assert_select ".card--highlighted", minimum: 1
    assert_select ".card-signals .badge", text: "Delayed"
  end

  test "index does not highlight topics without recent signals" do
    # No TopicStatusEvents created — no highlights expected
    get topics_url
    assert_response :success

    assert_select ".card--highlighted", count: 0
    assert_select ".card-signals", count: 0
  end

  test "index highlights topic with deferral signal" do
    TopicStatusEvent.create!(
      topic: @active_topic,
      lifecycle_status: "active",
      evidence_type: "deferral_signal",
      occurred_at: 10.days.ago
    )

    get topics_url
    assert_response :success

    assert_select ".card-signals .badge", text: "Delayed"
  end

  test "index does not highlight old signals outside 30-day window" do
    TopicStatusEvent.create!(
      topic: @active_topic,
      lifecycle_status: "active",
      evidence_type: "deferral_signal",
      occurred_at: 60.days.ago
    )

    get topics_url
    assert_response :success

    assert_select ".card--highlighted", count: 0
  end

  test "index hero section caps at 6 topics" do
    # Create 8 active topics with recent activity and impact scores (max 5)
    8.times do |i|
      topic = Topic.create!(
        name: "Hero Topic #{i}",
        lifecycle_status: "active",
        status: "approved",
        resident_impact_score: [ 5 - i, 1 ].max,
        last_activity_at: (i + 1).days.ago
      )
      AgendaItemTopic.create!(topic: topic, agenda_item: @agenda_item)
    end

    get topics_url
    assert_response :success

    # Hero should show at most 6 cards (8 new + 1 from setup = 9 eligible, but capped at 6)
    hero_cards = css_select("#hero-topics .card")
    assert_equal 6, hero_cards.size
  end

  test "index only shows active topics" do
    get topics_url
    assert_response :success

    all_titles = css_select(".card-title").map { |node| node.text.strip }
    assert_includes all_titles, @active_topic.name
    refute_includes all_titles, @dormant_topic.name
    refute_includes all_titles, @resolved_topic.name
  end

  test "index hero section shows active topics ranked by resident_impact_score" do
    @active_topic.update!(resident_impact_score: 5, last_activity_at: 2.days.ago)
    low_impact = Topic.create!(
      name: "low impact topic", lifecycle_status: "active", status: "approved",
      resident_impact_score: 1, last_activity_at: 1.day.ago
    )
    AgendaItemTopic.create!(topic: low_impact, agenda_item: @agenda_item)

    get topics_url
    assert_response :success

    hero_titles = css_select("#hero-topics .card-title").map { |node| node.text.strip }
    assert_equal @active_topic.name, hero_titles.first
  end

  test "index hero section excludes topics without activity in last 30 days" do
    @active_topic.update!(resident_impact_score: 5, last_activity_at: 60.days.ago)

    get topics_url
    assert_response :success

    hero_titles = css_select("#hero-topics .card-title").map { |node| node.text.strip }
    refute_includes hero_titles, @active_topic.name
  end

  test "index main list excludes topics already in hero section" do
    @active_topic.update!(resident_impact_score: 5, last_activity_at: 1.day.ago)

    get topics_url
    assert_response :success

    hero_titles = css_select("#hero-topics .card-title").map { |node| node.text.strip }
    main_titles = css_select("#all-topics .card-title").map { |node| node.text.strip }

    hero_titles.each do |title|
      refute_includes main_titles, title
    end
  end

  test "index shows explanation text and explore link" do
    get topics_url
    assert_response :success

    assert_select ".page-subtitle", text: /What Two Rivers city government is working on/
    assert_select "a[href=?]", "/topics/explore"
  end

  # --- Topic show page tests ---

  test "show loads topic and renders successfully" do
    get topic_url(@active_topic)
    assert_response :success
    assert_select "h1", text: @active_topic.name
  end

  test "show redirects to topics index for non-existent topic" do
    get topic_url(id: 999999)
    assert_redirected_to topics_path
  end

  test "show does not display proposed topics" do
    proposed = Topic.create!(name: "Proposed Topic", status: "proposed")
    get topic_url(proposed)
    assert_redirected_to topics_path
  end

  test "show loads upcoming appearances for future meetings" do
    future_meeting = Meeting.create!(
      body_name: "Plan Commission",
      meeting_type: "Regular",
      starts_at: 7.days.from_now,
      status: "parsed",
      detail_page_url: "http://example.com/future",
      location: "City Hall"
    )
    future_item = AgendaItem.create!(meeting: future_meeting, title: "Future Discussion")
    AgendaItemTopic.create!(topic: @active_topic, agenda_item: future_item)
    TopicAppearance.create!(
      topic: @active_topic, meeting: future_meeting,
      agenda_item: future_item, appeared_at: future_meeting.starts_at,
      evidence_type: "agenda_item"
    )

    get topic_url(@active_topic)
    assert_response :success
    assert_select ".topic-upcoming", minimum: 1
  end

  test "show hides upcoming section when no future meetings" do
    get topic_url(@active_topic)
    assert_response :success
    assert_select ".topic-upcoming", count: 0
  end

  test "show loads most recent topic summary" do
    TopicSummary.create!(
      topic: @active_topic, meeting: @meeting,
      content: "## Street Repair\n\n**Factual Record**\n- City approved funding [Packet Page 5].",
      summary_type: "topic_digest", generation_data: { model: "test" }
    )

    get topic_url(@active_topic)
    assert_response :success
    assert_select ".topic-summary", minimum: 1
  end

  test "show hides summary section when no summaries exist" do
    get topic_url(@active_topic)
    assert_response :success
    assert_select ".topic-summary", count: 0
  end

  test "show loads recent activity from past meetings" do
    past_item = AgendaItem.create!(meeting: @meeting, title: "Past Item", summary: "Discussed repairs")
    AgendaItemTopic.create!(topic: @active_topic, agenda_item: past_item)
    TopicAppearance.create!(
      topic: @active_topic, meeting: @meeting,
      agenda_item: past_item, appeared_at: @meeting.starts_at,
      evidence_type: "agenda_item"
    )

    get topic_url(@active_topic)
    assert_response :success
    assert_select ".topic-recent-activity", minimum: 1
  end

  test "show loads decisions with motions and votes" do
    item_with_motion = AgendaItem.create!(meeting: @meeting, title: "Vote Item")
    AgendaItemTopic.create!(topic: @active_topic, agenda_item: item_with_motion)
    motion = Motion.create!(
      meeting: @meeting, agenda_item: item_with_motion,
      description: "Approve street plan", outcome: "Passed"
    )
    member = Member.create!(name: "Ald. Smith")
    Vote.create!(motion: motion, member: member, value: "yes")
    TopicAppearance.create!(
      topic: @active_topic, meeting: @meeting,
      agenda_item: item_with_motion, appeared_at: @meeting.starts_at,
      evidence_type: "agenda_item"
    )

    get topic_url(@active_topic)
    assert_response :success
    assert_select ".topic-decisions", minimum: 1
  end

  test "show hides decisions section when no motions exist" do
    get topic_url(@active_topic)
    assert_response :success
    assert_select ".topic-decisions", count: 0
  end

  test "show displays empty state when topic has no activity at all" do
    empty_topic = Topic.create!(name: "Empty Topic", status: "approved", lifecycle_status: "active")

    get topic_url(empty_topic)
    assert_response :success
    assert_select ".topic-empty-state", minimum: 1
  end

  test "show upcoming cards are links to meeting pages" do
    future_meeting = Meeting.create!(
      body_name: "Plan Commission",
      meeting_type: "Regular",
      starts_at: 7.days.from_now,
      status: "parsed",
      detail_page_url: "http://example.com/future",
      location: "City Hall"
    )
    future_item = AgendaItem.create!(meeting: future_meeting, title: "Future Discussion")
    AgendaItemTopic.create!(topic: @active_topic, agenda_item: future_item)
    TopicAppearance.create!(
      topic: @active_topic, meeting: future_meeting,
      agenda_item: future_item, appeared_at: future_meeting.starts_at,
      evidence_type: "agenda_item"
    )

    get topic_url(@active_topic)
    assert_response :success
    assert_select ".topic-upcoming a.card-link", minimum: 1
  end

  test "show recent activity has button links to meetings" do
    past_item = AgendaItem.create!(meeting: @meeting, title: "Past Item")
    AgendaItemTopic.create!(topic: @active_topic, agenda_item: past_item)
    TopicAppearance.create!(
      topic: @active_topic, meeting: @meeting,
      agenda_item: past_item, appeared_at: @meeting.starts_at,
      evidence_type: "agenda_item"
    )

    get topic_url(@active_topic)
    assert_response :success
    assert_select ".topic-activity-item a.btn", minimum: 1
  end

  test "show key decisions displays vote label" do
    item_with_motion = AgendaItem.create!(meeting: @meeting, title: "Vote Item")
    AgendaItemTopic.create!(topic: @active_topic, agenda_item: item_with_motion)
    motion = Motion.create!(
      meeting: @meeting, agenda_item: item_with_motion,
      description: "Approve street plan", outcome: "Passed"
    )
    member = Member.create!(name: "Ald. Jones")
    Vote.create!(motion: motion, member: member, value: "yes")

    get topic_url(@active_topic)
    assert_response :success
    assert_select ".votes-label", text: "How they voted"
  end

  test "show has back to topics button" do
    get topic_url(@active_topic)
    assert_response :success
    assert_select "a.btn", text: /Back to Topics/
  end
end
