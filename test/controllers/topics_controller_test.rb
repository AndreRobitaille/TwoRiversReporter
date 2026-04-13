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

    titles = css_select("[data-section='all-topics'] .topics-card-name").map { |node| node.text.strip }
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
    cards = css_select("[data-section='all-topics'] .topics-card")
    assert_equal 20, cards.size

    # Should show count indicator
    assert_select ".topics-count", text: /of 22/

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

    titles = css_select("#hero-topics .topics-card-name").map { |node| node.text.strip }
    assert_equal "scored topic", titles.first
    # @active_topic (nil score) should come after scored topics
    assert_equal @active_topic.name, titles.last
  end

  test "index does not show lifecycle badges (all topics are active)" do
    get topics_url
    assert_response :success

    # Badges are omitted from index cards — all shown topics are active by definition
    assert_select ".badge", text: "Active", count: 0
    assert_select ".badge", text: "Dormant", count: 0
    assert_select ".badge", text: "Resolved", count: 0
    assert_select ".badge", text: "Recurring", count: 0
  end

  test "index renders topic cards without signal pills" do
    TopicStatusEvent.create!(
      topic: @active_topic,
      lifecycle_status: "active",
      evidence_type: "deferral_signal",
      occurred_at: 5.days.ago
    )

    get topics_url
    assert_response :success

    # Signal pills were removed from cards
    assert_select ".card-signals", count: 0
    # Cards should still render
    assert_select ".topics-card", minimum: 1
  end

  test "index renders cards without highlighted class" do
    get topics_url
    assert_response :success

    # Old card classes no longer used
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
    hero_cards = css_select("#hero-topics .topics-card")
    assert_equal 6, hero_cards.size
  end

  test "index only shows active topics" do
    get topics_url
    assert_response :success

    all_titles = css_select(".topics-card-name").map { |node| node.text.strip }
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

    hero_titles = css_select("#hero-topics .topics-card-name").map { |node| node.text.strip }
    assert_equal @active_topic.name, hero_titles.first
  end

  test "index hero section excludes topics without activity in last 30 days" do
    @active_topic.update!(resident_impact_score: 5, last_activity_at: 60.days.ago)

    get topics_url
    assert_response :success

    hero_titles = css_select("#hero-topics .topics-card-name").map { |node| node.text.strip }
    refute_includes hero_titles, @active_topic.name
  end

  test "index main list excludes topics already in hero section" do
    @active_topic.update!(resident_impact_score: 5, last_activity_at: 1.day.ago)

    get topics_url
    assert_response :success

    hero_titles = css_select("#hero-topics .topics-card-name").map { |node| node.text.strip }
    main_titles = css_select("[data-section='all-topics'] .topics-card-name").map { |node| node.text.strip }

    hero_titles.each do |title|
      refute_includes main_titles, title
    end
  end

  test "index shows explanation text" do
    get topics_url
    assert_response :success

    assert_select ".topics-tagline", text: /What the city is working on/
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

  test "show hides sections with no data instead of showing empty state" do
    get topic_url(@active_topic)
    assert_response :success
    # What to Watch: hidden when no briefing
    assert_select ".topic-article-section--watch", 0
    # Key Decisions: hidden when no motions
    assert_select ".topic-article-section--decisions", 0
    # Story: hidden when no briefing
    assert_select ".topic-article-section--story", 0
    # Record: always shown, with empty state when no generation_data
    assert_select ".topic-article-section--record .section-empty", text: /No meeting activity/
  end

  test "show hides what to watch when no briefing" do
    get topic_url(@active_topic)
    assert_response :success
    assert_select ".topic-article-section--watch", 0
  end

  test "show shows typical committee fallback when no upcoming meetings" do
    # Create a past appearance so typical_committee is derived
    TopicAppearance.create!(
      topic: @active_topic, meeting: @meeting,
      appeared_at: @meeting.starts_at,
      evidence_type: "agenda_item"
    )

    get topic_url(@active_topic)
    assert_response :success
    assert_select ".topic-upcoming-fallback", text: /typically discussed at/i
  end

  test "show hides story when no briefing" do
    get topic_url(@active_topic)
    assert_response :success
    assert_select ".topic-article-section--story", 0
  end

  test "show hides key decisions when no motions" do
    get topic_url(@active_topic)
    assert_response :success
    assert_select ".topic-article-section--decisions", 0
  end

  test "show displays empty state for record when no generation data" do
    get topic_url(@active_topic)
    assert_response :success
    assert_select ".topic-article-section--record .section-empty", text: /No meeting activity/
  end

  test "show displays what to watch from generation_data" do
    TopicBriefing.create!(
      topic: @active_topic,
      headline: "Budget approved",
      generation_data: {
        "headline" => "Budget approved",
        "editorial_analysis" => {
          "what_to_watch" => "Watch for implementation timeline.",
          "current_state" => "Council approved the budget.",
          "process_concerns" => [],
          "pattern_observations" => []
        },
        "factual_record" => [],
        "resident_impact" => { "score" => 3, "rationale" => "Affects taxes." }
      },
      generation_tier: "full"
    )

    get topic_url(@active_topic)
    assert_response :success
    assert_select ".topic-watch-quote", text: /Watch for implementation timeline/
  end

  test "show displays story from generation_data current_state" do
    TopicBriefing.create!(
      topic: @active_topic,
      headline: "Budget approved",
      editorial_content: "Fallback editorial.",
      generation_data: {
        "headline" => "Budget approved",
        "editorial_analysis" => {
          "what_to_watch" => "Watch for timeline.",
          "current_state" => "The council voted 5-2 to approve.",
          "process_concerns" => [ "Rushed through without public comment." ],
          "pattern_observations" => []
        },
        "factual_record" => [],
        "resident_impact" => { "score" => 4, "rationale" => "Tax impact." }
      },
      generation_tier: "full"
    )

    get topic_url(@active_topic)
    assert_response :success
    assert_select ".topic-story-body", text: /voted 5-2/
    assert_select ".topic-aside li", text: /Rushed through/
  end

  test "show displays story from editorial_content fallback when no generation_data" do
    TopicBriefing.create!(
      topic: @active_topic,
      headline: "Budget approved",
      editorial_content: "Fallback editorial content here.",
      generation_tier: "headline_only"
    )

    get topic_url(@active_topic)
    assert_response :success
    assert_select ".topic-story-body", text: /Fallback editorial/
  end

  test "show renders timeline from generation_data factual_record" do
    TopicBriefing.create!(
      topic: @active_topic,
      headline: "Street repairs",
      generation_data: {
        "headline" => "Street repairs",
        "editorial_analysis" => {
          "what_to_watch" => "Watch for contract award.",
          "current_state" => "Repairs approved.",
          "process_concerns" => [],
          "pattern_observations" => []
        },
        "factual_record" => [
          { "date" => "2025-09-02", "event" => "Council approved plan.", "meeting" => "City Council, Sep 2" },
          { "date" => "2025-11-05", "event" => "Contractor selected.", "meeting" => "Public Works, Nov 5" }
        ],
        "resident_impact" => { "score" => 3, "rationale" => "Road closures." }
      },
      generation_tier: "full"
    )

    get topic_url(@active_topic)
    assert_response :success
    assert_select ".topic-timeline-entry", 2
    assert_select ".topic-timeline-date", text: /Sep 2, 2025/
    assert_select ".topic-timeline-content", text: /Council approved plan/
    # Meeting name is cleaned for display (trailing date suffix stripped)
    assert_select ".topic-timeline-meeting", text: /\ACity Council\z/
  end

  test "show enriches record entry with meeting summary content and links to meeting" do
    # Past meeting that the topic appeared at, with a MeetingSummary whose
    # item_details contain substantive content for this topic's agenda item.
    past_meeting = Meeting.create!(
      body_name: "Public Utilities Committee",
      meeting_type: "Regular",
      starts_at: Time.zone.parse("2025-09-02 18:00"),
      status: "parsed",
      detail_page_url: "http://example.com/pu/2025-09-02"
    )
    agenda_item = AgendaItem.create!(meeting: past_meeting, title: "Lead Service Line Replacement")
    # AgendaItemTopic#after_create callback creates the TopicAppearance.
    AgendaItemTopic.create!(topic: @active_topic, agenda_item: agenda_item)
    MeetingSummary.create!(
      meeting: past_meeting,
      summary_type: "minutes_recap",
      content: nil,
      generation_data: {
        "item_details" => [
          {
            "agenda_item_title" => "Lead Service Line Replacement",
            "summary" => "Council approved a $2.4M contract with Northern Pipe for 2026 LSL replacement work."
          }
        ]
      }
    )

    # Briefing with a generic "appeared on the agenda" factual_record entry
    # whose "meeting" label has the AI's typical date suffix.
    TopicBriefing.create!(
      topic: @active_topic,
      headline: "LSL update",
      generation_data: {
        "headline" => "LSL update",
        "editorial_analysis" => {
          "what_to_watch" => "Watch for contract execution.",
          "current_state" => "Contract approved.",
          "process_concerns" => [],
          "pattern_observations" => []
        },
        "factual_record" => [
          {
            "date" => "2025-09-02",
            "event" => "Topic appeared on the agenda.",
            "meeting" => "Public Utilities Committee, Sep 2 2025"
          }
        ],
        "resident_impact" => { "score" => 4, "rationale" => "Water safety." }
      },
      generation_tier: "full"
    )

    get topic_url(@active_topic)
    assert_response :success

    # Event text is enriched: "appeared on the agenda" replaced with the
    # matched item_details summary.
    assert_select ".topic-timeline-event", text: /Northern Pipe/
    refute_match(/appeared on the agenda/i, css_select(".topic-timeline-event").text)

    # Meeting name is rendered as a link to the canonical meeting page,
    # with the cleaned body_name (no date suffix from the AI's raw label).
    assert_select "a.topic-timeline-meeting-link[href=?]", meeting_path(past_meeting), text: /\APublic Utilities Committee\z/
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
    # AgendaItemTopic#after_create callback creates the TopicAppearance.
    AgendaItemTopic.create!(topic: @active_topic, agenda_item: future_item)

    get topic_url(@active_topic)
    assert_response :success
    assert_select "a.topic-upcoming-link", minimum: 1
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

    get topic_url(@active_topic)
    assert_response :success
    assert_select ".topic-article-section--decisions .topic-decision", minimum: 1
  end

  test "show key decisions displays vote grid" do
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
    assert_select ".votes-grid .vote-card", minimum: 1
  end

  test "show briefing freshness badge displays New for recent briefings" do
    TopicBriefing.create!(
      topic: @active_topic,
      headline: "New development on topic",
      generation_tier: "headline_only"
    )

    get topic_url(@active_topic)
    assert_response :success
    assert_select ".badge--primary", text: "New"
  end

  test "show has back to topics button" do
    get topic_url(@active_topic)
    assert_response :success
    assert_select "a.btn", text: /All topics/
  end

  test "show displays lifecycle badge" do
    get topic_url(@active_topic)
    assert_response :success
    assert_select ".badge", text: "Active"
  end
end
