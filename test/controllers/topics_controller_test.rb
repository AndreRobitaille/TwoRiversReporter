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
    assert_select ".card-signals .badge", text: "Deferral Observed"
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

    assert_select ".card-signals .badge", text: "Deferral Observed"
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

    assert_select ".page-subtitle", text: /currently under discussion/i
    assert_select "a[href=?]", "/topics/explore"
  end
end
