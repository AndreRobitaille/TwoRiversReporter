# Homepage Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current homepage layout with a newspaper-style inverted pyramid that helps residents find their topic in 15 seconds.

**Architecture:** Rewrite `HomeController#index` to produce four data sets (top stories, wire items, next council meetings, briefing headlines). Replace the homepage view and partials with new zone-based partials. Add homepage-specific CSS. Delete old partials and CSS.

**Tech Stack:** Rails 8.1, server-rendered HTML, existing CSS custom properties from atomic design system.

**Spec:** `docs/superpowers/specs/2026-04-10-homepage-redesign-design.md`
**Mockup:** `.superpowers/brainstorm/1386395-1775853637/content/homepage-v5.html`

**Pre-requisites:**
- Sync production database to development (run separately, will break admin MFA on dev)
- Create a git worktree for this feature branch

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `app/controllers/home_controller.rb` | Rewrite | Four zone queries, headline/meeting-ref loading |
| `app/views/home/index.html.erb` | Rewrite | Zone layout with diamond dividers |
| `app/views/home/_top_story.html.erb` | Create | Primary/secondary story card partial |
| `app/views/home/_wire_card.html.erb` | Create | Mid-tier wire card partial |
| `app/views/home/_wire_row.html.erb` | Create | Compact wire row partial (replaces old `_meeting_row`) |
| `app/views/home/_next_up.html.erb` | Create | Council/work session calendar card |
| `app/assets/stylesheets/home.css` | Create | All homepage-specific CSS |
| `test/controllers/home_controller_test.rb` | Rewrite | Tests for new zone structure |
| `app/views/home/_topic_headline_item.html.erb` | Delete | Old headline item partial |
| `app/views/home/_meeting_week_group.html.erb` | Delete | Old meeting table group |
| `app/views/home/_meeting_row.html.erb` | Delete | Old meeting table row |

---

### Task 1: Rewrite HomeController with new zone queries

**Files:**
- Modify: `app/controllers/home_controller.rb`

- [ ] **Step 1: Write the failing test for top stories**

In `test/controllers/home_controller_test.rb`, replace the entire file:

```ruby
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
    assert_select ".top-story .read-more"
  end

  test "top stories limited to 2 items" do
    # Create a third high-impact topic
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

    # low_topic (impact 2) should appear in wire, not top stories
    assert_select ".wire-card .wire-topic, .wire-list-item .list-topic", minimum: 1
    # high_topic should NOT appear in wire (it's in top stories)
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
    # Higher impact topic should appear first (if both present)
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
    # Non-council meeting should NOT appear
    Meeting.create!(
      body_name: "Plan Commission Meeting",
      starts_at: 8.days.from_now,
      detail_page_url: "http://example.com/plan"
    )

    get root_url
    assert_response :success
    assert_select ".nextup-card", count: 2
    nextup_text = css_select(".nextup-zone").text
    assert_match(/City Council Meeting/i, nextup_text)
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
    # Only high-impact topics exist — they go to top stories, nothing for wire
    @low_topic.update!(resident_impact_score: 5)

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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/home_controller_test.rb`
Expected: Failures — old view references `.card--warm`, `.card--cool`, etc. that the tests no longer expect.

- [ ] **Step 3: Rewrite HomeController**

Replace `app/controllers/home_controller.rb` entirely:

```ruby
class HomeController < ApplicationController
  ACTIVITY_WINDOW = 30.days
  TOP_STORY_MIN_IMPACT = 4
  TOP_STORY_LIMIT = 2
  WIRE_MIN_IMPACT = 2
  WIRE_CARD_COUNT = 4
  WIRE_ROW_LIMIT = 6
  NEXT_UP_LIMIT = 2

  COUNCIL_PATTERNS = [
    "City Council Meeting",
    "City Council Work Session",
    "City Council Special Meeting"
  ].freeze

  def index
    @top_stories = build_top_stories
    wire_all = build_wire(@top_stories.map(&:id))
    @wire_cards = wire_all.first(WIRE_CARD_COUNT)
    @wire_rows = wire_all.drop(WIRE_CARD_COUNT).first(WIRE_ROW_LIMIT)
    @next_up = build_next_up
    load_headlines(@top_stories + @wire_cards)
    load_meeting_refs(@top_stories + @wire_cards + @wire_rows)
  end

  private

  def build_top_stories
    Topic.approved
      .where("resident_impact_score >= ?", TOP_STORY_MIN_IMPACT)
      .where("last_activity_at > ?", ACTIVITY_WINDOW.ago)
      .order(resident_impact_score: :desc, last_activity_at: :desc)
      .limit(TOP_STORY_LIMIT)
      .to_a
  end

  def build_wire(exclude_ids)
    scope = Topic.approved
      .where("resident_impact_score >= ?", WIRE_MIN_IMPACT)
      .where("last_activity_at > ?", ACTIVITY_WINDOW.ago)
      .order(resident_impact_score: :desc, last_activity_at: :desc)

    scope = scope.where.not(id: exclude_ids) if exclude_ids.any?
    scope.limit(WIRE_CARD_COUNT + WIRE_ROW_LIMIT).to_a  # max 10 items total (4 cards + 6 rows)
  end

  def build_next_up
    Meeting
      .where("starts_at > ?", Time.current)
      .where(body_name: COUNCIL_PATTERNS)
      .order(starts_at: :asc)
      .limit(NEXT_UP_LIMIT)
  end

  def load_headlines(topics)
    return if topics.empty?

    @headlines = TopicBriefing
      .where(topic_id: topics.map(&:id))
      .each_with_object({}) { |b, h| h[b.topic_id] = b.headline if b.headline.present? }
  end

  def load_meeting_refs(topics)
    return if topics.empty?

    topic_ids = topics.map(&:id)

    # For each topic, find its most recent meeting appearance
    latest_appearances = TopicAppearance
      .joins(:meeting)
      .where(topic_id: topic_ids)
      .select("DISTINCT ON (topic_appearances.topic_id) topic_appearances.topic_id, meetings.id AS meeting_id, meetings.body_name, meetings.starts_at")
      .order(Arel.sql("topic_appearances.topic_id, meetings.starts_at DESC"))

    @meeting_refs = latest_appearances.each_with_object({}) do |row, h|
      h[row.topic_id] = {
        meeting_id: row.meeting_id,
        body_name: row.body_name,
        date: row.starts_at
      }
    end
  end
end
```

- [ ] **Step 4: Run tests — they will still fail because views don't exist yet**

Run: `bin/rails test test/controllers/home_controller_test.rb`
Expected: Template errors — the new view files don't exist yet. That's fine; we'll create them in Task 2.

- [ ] **Step 5: Commit controller and tests**

```bash
git add app/controllers/home_controller.rb test/controllers/home_controller_test.rb
git commit -m "refactor: rewrite HomeController for newspaper homepage layout

Replace dual what-happened/coming-up queries with unified impact-sorted
zones: top stories, wire (cards + rows), next up, escape hatches."
```

---

### Task 2: Create homepage CSS

**Files:**
- Create: `app/assets/stylesheets/home.css`

- [ ] **Step 1: Create `app/assets/stylesheets/home.css`**

Extract all homepage-specific CSS from the v5 mockup. This file handles only the homepage zones — the site nav, footer, and shared components stay in `application.css`.

```css
/* ============================
   Homepage — Newspaper Layout
   ============================ */

/* Page header */
.home-header {
  text-align: center;
  margin-bottom: var(--space-6);
  padding: var(--space-4) 0;
}
.home-header .page-title {
  font-family: var(--font-display);
  font-weight: 900;
  font-size: var(--text-3xl);
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--color-teal);
}
.home-header .tagline {
  font-family: var(--font-data);
  font-size: var(--text-xs);
  text-transform: uppercase;
  letter-spacing: 0.1em;
  color: var(--color-text-secondary);
  margin-top: var(--space-1);
}

/* Section headers (atom marker + label + gradient line) */
.home-section-header {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  margin-bottom: var(--space-4);
}
.home-section-header .section-label {
  font-family: var(--font-display);
  font-weight: 700;
  font-size: var(--text-xs);
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--color-teal);
  white-space: nowrap;
}
.home-section-header .section-line {
  flex: 1;
  height: 1.5px;
  background: linear-gradient(90deg, var(--color-terra-cotta), transparent);
}

/* Zone spacing */
.home-zone {
  margin-bottom: var(--space-4);
}

/* === ZONE 1: TOP STORIES === */
.top-story {
  position: relative;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-lg);
  overflow: hidden;
  margin-bottom: var(--space-4);
  text-decoration: none;
  color: inherit;
  display: block;
  transition: box-shadow 0.2s, transform 0.15s;
}
.top-story:hover {
  box-shadow: 0 12px 32px rgba(44,37,32,0.16), 0 4px 12px rgba(44,37,32,0.10);
  transform: translateY(-2px);
}
.top-story .story-accent {
  height: 5px;
  background: linear-gradient(90deg, var(--color-terra-cotta), var(--color-amber));
}
.top-story .story-inner {
  padding: var(--space-6);
  position: relative;
}
.top-story .story-deco {
  position: absolute;
  top: 12px;
  right: 14px;
  opacity: 0.08;
}
.top-story .story-topic {
  font-family: var(--font-display);
  font-weight: 800;
  font-size: var(--text-2xl);
  text-transform: uppercase;
  letter-spacing: 0.02em;
  color: var(--color-terra-cotta);
  margin-bottom: var(--space-1);
}
.top-story .story-desc {
  font-family: var(--font-data);
  font-size: var(--text-xs);
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--color-text-muted);
  margin-bottom: var(--space-3);
}
.top-story .story-headline {
  font-size: var(--text-base);
  line-height: 1.6;
  margin-bottom: var(--space-3);
}
.top-story .story-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.top-story .story-meta {
  font-family: var(--font-data);
  font-size: var(--text-xs);
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--color-text-muted);
}
.top-story .read-more,
.second-story .read-more {
  font-family: var(--font-body);
  font-weight: 600;
  font-size: var(--text-sm);
  color: var(--color-teal);
  background: var(--color-info-light);
  padding: var(--space-1) var(--space-3);
  border-radius: var(--radius-md);
  white-space: nowrap;
  transition: background 0.15s, color 0.15s;
}
.top-story:hover .read-more,
.second-story:hover .read-more {
  background: var(--color-teal);
  color: white;
}

/* Secondary story */
.second-story {
  position: relative;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-md);
  overflow: hidden;
  text-decoration: none;
  color: inherit;
  display: block;
  transition: box-shadow 0.2s, transform 0.15s;
}
.second-story:hover {
  box-shadow: var(--shadow-lg);
  transform: translateY(-1px);
}
.second-story .story-accent {
  height: 4px;
  background: linear-gradient(90deg, var(--color-teal), #3d7b8a);
}
.second-story .story-inner {
  padding: var(--space-4) var(--space-6);
}
.second-story .story-topic {
  font-family: var(--font-display);
  font-weight: 700;
  font-size: var(--text-xl);
  text-transform: uppercase;
  letter-spacing: 0.02em;
  color: var(--color-teal);
  margin-bottom: var(--space-1);
}
.second-story .story-desc {
  font-family: var(--font-data);
  font-size: var(--text-xs);
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--color-text-muted);
  margin-bottom: var(--space-2);
}
.second-story .story-headline {
  font-size: var(--text-sm);
  line-height: 1.55;
  margin-bottom: var(--space-3);
}
.second-story .story-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.second-story .story-meta {
  font-family: var(--font-data);
  font-size: var(--text-xs);
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--color-text-muted);
}
.second-story .read-more {
  font-size: var(--text-xs);
  padding: var(--space-1) var(--space-2);
}

/* === ZONE 2: THE WIRE === */
.wire-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: var(--space-3);
  margin-bottom: var(--space-3);
}

.wire-card {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-sm);
  padding: var(--space-4);
  text-decoration: none;
  color: inherit;
  display: flex;
  flex-direction: column;
  transition: box-shadow 0.2s, transform 0.15s;
  position: relative;
  overflow: hidden;
}
.wire-card::before {
  content: '';
  position: absolute;
  top: 0; left: 0; right: 0;
  height: 3px;
  background: var(--color-teal);
  opacity: 0.5;
}
.wire-card:hover {
  box-shadow: var(--shadow-md);
  transform: translateY(-1px);
}
.wire-card:hover::before { opacity: 1; }
.wire-card .wire-topic {
  font-family: var(--font-display);
  font-weight: 700;
  font-size: var(--text-sm);
  text-transform: uppercase;
  letter-spacing: 0.02em;
  color: var(--color-teal);
  margin-bottom: var(--space-1);
}
.wire-card .wire-desc {
  font-family: var(--font-data);
  font-size: 0.58rem;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--color-text-muted);
  margin-bottom: var(--space-2);
}
.wire-card .wire-headline {
  font-size: var(--text-sm);
  line-height: 1.45;
  flex: 1;
}
.wire-card .wire-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-top: var(--space-2);
  padding-top: var(--space-2);
  border-top: 1px solid var(--color-border);
}
.wire-card .wire-meta {
  font-family: var(--font-data);
  font-size: 0.56rem;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--color-text-muted);
}
.wire-card .wire-read {
  font-family: var(--font-body);
  font-weight: 600;
  font-size: var(--text-xs);
  color: var(--color-teal);
}
.wire-card:hover .wire-read { text-decoration: underline; }

/* Compact wire rows */
.wire-list {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-sm);
  overflow: hidden;
}
.wire-list-item {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  padding: var(--space-2) var(--space-4);
  text-decoration: none;
  color: inherit;
  transition: background 0.15s;
}
.wire-list-item:hover { background: var(--color-info-light); }
.wire-list-item + .wire-list-item { border-top: 1px solid var(--color-border); }
.wire-list-item .list-topic {
  font-family: var(--font-display);
  font-weight: 600;
  font-size: var(--text-sm);
  text-transform: uppercase;
  letter-spacing: 0.02em;
  color: var(--color-teal);
  flex-shrink: 0;
}
.wire-list-item .list-desc {
  font-size: var(--text-sm);
  color: var(--color-text-secondary);
  flex: 1;
  min-width: 0;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.wire-list-item .list-arrow {
  color: var(--color-text-muted);
  flex-shrink: 0;
  font-size: var(--text-sm);
  transition: transform 0.15s, color 0.15s;
}
.wire-list-item:hover .list-arrow {
  color: var(--color-teal);
  transform: translateX(3px);
}

/* === ZONE 3: NEXT UP === */
.nextup-zone { margin-bottom: var(--space-4); }
.nextup-strip { display: flex; gap: var(--space-3); }
.nextup-card {
  flex: 1;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-sm);
  overflow: hidden;
  text-decoration: none;
  color: inherit;
  display: flex;
  transition: box-shadow 0.2s, transform 0.15s;
}
.nextup-card:hover { box-shadow: var(--shadow-md); transform: translateY(-1px); }
.nextup-card .date-slab {
  font-family: var(--font-display);
  font-weight: 800;
  padding: var(--space-3) var(--space-3);
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  min-width: 4.25rem;
  line-height: 1.1;
  color: white;
  background: var(--color-teal);
  box-shadow: inset -2px 0 6px rgba(0,0,0,0.15);
}
.nextup-card .date-slab.council { background: var(--color-terra-cotta); }
.nextup-card .date-month {
  font-size: 0.55rem;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  opacity: 0.85;
}
.nextup-card .date-day { font-size: var(--text-2xl); }
.nextup-card .meeting-info {
  padding: var(--space-2) var(--space-3);
  display: flex;
  flex-direction: column;
  justify-content: center;
  flex: 1;
}
.nextup-card .meeting-name {
  font-family: var(--font-display);
  font-weight: 600;
  font-size: var(--text-sm);
  text-transform: uppercase;
  letter-spacing: 0.02em;
}
.nextup-card .meeting-note {
  font-family: var(--font-data);
  font-size: 0.58rem;
  color: var(--color-text-muted);
  text-transform: uppercase;
  letter-spacing: 0.04em;
  margin-top: var(--space-1);
}
.nextup-card .meeting-arrow {
  display: flex;
  align-items: center;
  padding: 0 var(--space-3);
  color: var(--color-text-muted);
  transition: color 0.15s, transform 0.15s;
}
.nextup-card:hover .meeting-arrow { color: var(--color-teal); transform: translateX(3px); }

/* Empty state for next up */
.nextup-empty {
  font-family: var(--font-data);
  font-size: var(--text-xs);
  color: var(--color-text-muted);
  text-transform: uppercase;
  letter-spacing: 0.04em;
  margin-top: var(--space-2);
}

/* === ZONE 4: ESCAPE HATCHES === */
.home-escape { display: flex; gap: var(--space-3); flex-wrap: wrap; }
.home-escape-btn {
  font-family: var(--font-display);
  font-weight: 700;
  font-size: var(--text-sm);
  text-transform: uppercase;
  letter-spacing: 0.04em;
  text-decoration: none;
  padding: var(--space-2) var(--space-6);
  border-radius: var(--radius-md);
  background: linear-gradient(180deg, var(--color-teal) 0%, #003a47 100%);
  color: white;
  box-shadow: var(--shadow-sm), inset 0 1px 0 rgba(255,255,255,0.2);
  border: 1px solid #003040;
  transition: all 0.15s;
}
.home-escape-btn:hover {
  background: linear-gradient(180deg, #005a6b 0%, var(--color-teal) 100%);
  box-shadow: var(--shadow-md), inset 0 1px 0 rgba(255,255,255,0.2);
  transform: translateY(-1px);
}
.home-escape-btn:active {
  transform: translateY(0);
  box-shadow: inset 0 2px 4px rgba(0,0,0,0.2);
}

/* === EMPTY STATES === */
.home-quiet {
  text-align: center;
  padding: var(--space-8) var(--space-4);
  color: var(--color-text-secondary);
  font-size: var(--text-base);
}

/* === MOBILE === */
@media (max-width: 600px) {
  .home-header .page-title { font-size: var(--text-2xl); }
  .top-story .story-inner { padding: var(--space-4); }
  .top-story .story-topic { font-size: var(--text-xl); }
  .top-story .story-headline { font-size: var(--text-sm); }
  .second-story .story-inner { padding: var(--space-3) var(--space-4); }
  .second-story .story-topic { font-size: var(--text-base); }
  .wire-grid { grid-template-columns: 1fr; }
  .wire-list-item .list-desc { display: none; }
  .wire-list-item { padding: var(--space-3) var(--space-4); }
  .wire-list-item .list-topic { flex: 1; }
  .nextup-strip { flex-direction: column; }
  .home-escape { flex-direction: column; }
  .home-escape-btn { text-align: center; padding: var(--space-3); }
}
```

- [ ] **Step 2: Verify the file is picked up by Propshaft**

Propshaft auto-discovers CSS files in `app/assets/stylesheets/`. Verify it's loaded by checking that the `stylesheet_link_tag :app` in the layout includes it. No manifest changes needed — Propshaft globs the directory.

Run: `bin/rails runner 'puts Rails.application.assets.paths'`
Expected: Output includes `app/assets/stylesheets`

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets/home.css
git commit -m "feat: add homepage-specific CSS for newspaper layout

Three-tier visual hierarchy, atomic motifs, explicit click affordances,
mobile-responsive wire grid and compact rows."
```

---

### Task 3: Create view partials and rewrite index

**Files:**
- Create: `app/views/home/_top_story.html.erb`
- Create: `app/views/home/_wire_card.html.erb`
- Create: `app/views/home/_wire_row.html.erb`
- Create: `app/views/home/_next_up.html.erb`
- Rewrite: `app/views/home/index.html.erb`

- [ ] **Step 1: Create `app/views/home/_top_story.html.erb`**

```erb
<%# Renders a top story card. Locals: topic, headline, meeting_ref, variant (:primary or :secondary) %>
<% variant ||= :primary %>
<% card_class = variant == :primary ? "top-story" : "second-story" %>

<%= link_to topic_path(topic), class: card_class do %>
  <% if variant == :primary %>
    <%= render "shared/starburst", size: 48, opacity: 0.08 %>
  <% end %>
  <div class="story-accent"></div>
  <div class="story-inner">
    <div class="story-topic"><%= topic.name %></div>
    <% if topic.description.present? %>
      <div class="story-desc"><%= topic.description %></div>
    <% end %>
    <% if headline.present? %>
      <p class="story-headline"><%= headline %></p>
    <% end %>
    <div class="story-footer">
      <% if meeting_ref %>
        <span class="story-meta"><%= meeting_ref[:date]&.strftime("%b %-d") %> · <%= meeting_ref[:body_name]&.sub(/ Meeting$/, "") %></span>
      <% else %>
        <span class="story-meta"></span>
      <% end %>
      <span class="read-more">Read more →</span>
    </div>
  </div>
<% end %>
```

- [ ] **Step 2: Create `app/views/home/_wire_card.html.erb`**

```erb
<%# Mid-tier wire card. Locals: topic, headline, meeting_ref %>
<%= link_to topic_path(topic), class: "wire-card" do %>
  <div class="wire-topic"><%= topic.name %></div>
  <% if topic.description.present? %>
    <div class="wire-desc"><%= topic.description %></div>
  <% end %>
  <% if headline.present? %>
    <p class="wire-headline"><%= truncate(headline, length: 120) %></p>
  <% end %>
  <div class="wire-footer">
    <% if meeting_ref %>
      <span class="wire-meta"><%= meeting_ref[:date]&.strftime("%b %-d") %> · <%= meeting_ref[:body_name]&.sub(/ Meeting$/, "") %></span>
    <% else %>
      <span class="wire-meta"></span>
    <% end %>
    <span class="wire-read">Read →</span>
  </div>
<% end %>
```

- [ ] **Step 3: Create `app/views/home/_wire_row.html.erb`**

```erb
<%# Compact wire row. Locals: topic %>
<%= link_to topic_path(topic), class: "wire-list-item" do %>
  <span class="list-topic"><%= topic.name %></span>
  <% if topic.description.present? %>
    <span class="list-desc"><%= topic.description %></span>
  <% end %>
  <span class="list-arrow">→</span>
<% end %>
```

- [ ] **Step 4: Create `app/views/home/_next_up.html.erb`**

```erb
<%# Next Up meeting card. Locals: meeting %>
<% is_council = meeting.body_name.include?("Council") && !meeting.body_name.include?("Work Session") %>
<%= link_to meeting_path(meeting), class: "nextup-card" do %>
  <div class="date-slab <%= 'council' if is_council %>">
    <span class="date-month"><%= meeting.starts_at.strftime("%b") %></span>
    <span class="date-day"><%= meeting.starts_at.strftime("%-d") %></span>
  </div>
  <div class="meeting-info">
    <span class="meeting-name"><%= meeting.body_name.sub(/ Meeting$/, "").sub(/^City Council /, "") %></span>
    <% topic_count = meeting.agenda_items.flat_map(&:topics).uniq.select(&:approved?).size %>
    <% if topic_count > 0 %>
      <span class="meeting-note"><%= pluralize(topic_count, "topic") %> on agenda</span>
    <% else %>
      <span class="meeting-note">Agenda not yet posted</span>
    <% end %>
  </div>
  <span class="meeting-arrow">→</span>
<% end %>
```

- [ ] **Step 5: Rewrite `app/views/home/index.html.erb`**

```erb
<% content_for(:title) { "Two Rivers Matters — What's Happening" } %>

<div class="home-header">
  <h1 class="page-title">What's Happening</h1>
  <p class="tagline">Two Rivers city government at a glance</p>
</div>

<%= render "shared/diamond_divider" %>

<%# === ZONE 1: TOP STORIES === %>
<% if @top_stories.any? %>
  <div class="home-zone">
    <% @top_stories.each_with_index do |topic, i| %>
      <%= render "top_story",
            topic: topic,
            headline: @headlines&.dig(topic.id),
            meeting_ref: @meeting_refs&.dig(topic.id),
            variant: i == 0 ? :primary : :secondary %>
    <% end %>
  </div>
<% else %>
  <div class="home-quiet">
    Things are quiet at city hall. Check back after the next council meeting.
  </div>
<% end %>

<%= render "shared/diamond_divider" %>

<%# === ZONE 2: THE WIRE === %>
<% if @wire_cards.any? || @wire_rows.any? %>
  <div class="home-zone wire-zone">
    <div class="home-section-header">
      <%= render "shared/atom_marker", size: 20 %>
      <span class="section-label">The Wire</span>
      <span class="section-line"></span>
    </div>

    <% if @wire_cards.any? %>
      <div class="wire-grid">
        <% @wire_cards.each do |topic| %>
          <%= render "wire_card",
                topic: topic,
                headline: @headlines&.dig(topic.id),
                meeting_ref: @meeting_refs&.dig(topic.id) %>
        <% end %>
      </div>
    <% end %>

    <% if @wire_rows.any? %>
      <div class="wire-list">
        <% @wire_rows.each do |topic| %>
          <%= render "wire_row", topic: topic %>
        <% end %>
      </div>
    <% end %>
  </div>

  <%= render "shared/diamond_divider" %>
<% end %>

<%# === ZONE 3: NEXT UP === %>
<div class="home-zone nextup-zone">
  <div class="home-section-header">
    <%= render "shared/atom_marker", size: 20 %>
    <span class="section-label">Next Up</span>
    <span class="section-line"></span>
  </div>

  <% if @next_up.any? %>
    <div class="nextup-strip">
      <% @next_up.each do |meeting| %>
        <%= render "next_up", meeting: meeting %>
      <% end %>
    </div>
  <% else %>
    <p class="nextup-empty">No council meetings scheduled</p>
  <% end %>
</div>

<%= render "shared/diamond_divider" %>

<%# === ZONE 4: ESCAPE HATCHES === %>
<div class="home-escape">
  <%= link_to "Browse All Topics →", topics_path, class: "home-escape-btn" %>
  <%= link_to "All Meetings →", meetings_path, class: "home-escape-btn" %>
</div>
```

- [ ] **Step 6: Run all tests**

Run: `bin/rails test test/controllers/home_controller_test.rb`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add app/views/home/
git commit -m "feat: implement newspaper homepage layout

Four zones: top stories (1-2 cards), the wire (mid-tier cards + compact
rows), next up (council/work session strip), escape hatches. Uses atomic
design motifs (starburst, diamond dividers, atom markers)."
```

---

### Task 4: Delete old partials and clean up CSS

**Files:**
- Delete: `app/views/home/_topic_headline_item.html.erb`
- Delete: `app/views/home/_meeting_week_group.html.erb`
- Delete: `app/views/home/_meeting_row.html.erb`
- Modify: `app/assets/stylesheets/application.css` (remove old homepage CSS)

- [ ] **Step 1: Delete old partials**

```bash
rm app/views/home/_topic_headline_item.html.erb
rm app/views/home/_meeting_week_group.html.erb
rm app/views/home/_meeting_row.html.erb
```

- [ ] **Step 2: Remove old homepage CSS from application.css**

Remove these CSS blocks from `app/assets/stylesheets/application.css`:
- `.home-intro` and all its children (~lines 1126-1157)
- `.card--warm` and all its children (~lines 1160-1213)
- `.card--cool` and all its children (~lines 1187-1213)
- `.week-group` and `.week-group__label` (~lines 1280-1310)
- `.home-divider` (~line 1306)
- `.topic-headline-item` and its children (~lines 1695-1725)
- `.meeting-topics-col` responsive rule (~line 2140)

Use the exact line numbers from the actual file when editing — the approximate numbers above are from the grep output. Grep for each class name to find exact locations.

**Note:** The old `HomeController` methods (`build_what_happened`, `build_coming_up`, `attach_coming_up_headlines`, `attach_what_happened_headlines`, `upcoming_meetings_grouped`, `recent_meetings_grouped`, `group_meetings_by_week`, `week_key`, `week_label`, `apply_meeting_diversity`) and old instance variables (`@coming_up_headlines`, `@what_happened_headlines`, `@upcoming_meeting_groups`, `@recent_meeting_groups`) were already removed in Task 1 when the controller was rewritten.

- [ ] **Step 3: Run full test suite**

Run: `bin/rails test`
Expected: All tests pass. No other views reference the deleted partials.

- [ ] **Step 4: Run linter**

Run: `bin/rubocop`
Expected: No new offenses from our changes.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: remove old homepage partials and CSS

Delete _topic_headline_item, _meeting_week_group, _meeting_row partials.
Remove .home-intro, .card--warm, .card--cool, .week-group,
.topic-headline-item CSS that are no longer used."
```

---

### Task 5: Manual verification and edge cases

**Files:** None — this is testing and polish.

- [ ] **Step 1: Boot dev server and verify visually**

Run: `bin/dev`

Check:
1. Homepage loads with top stories, wire, next up, escape buttons
2. Topic names are uppercase, colored, scannable
3. Descriptions appear below topic names in mono font
4. Headlines appear in body font
5. "Read more →" buttons visible on story cards
6. "Read →" visible on wire cards
7. → arrows on compact rows
8. Diamond dividers between zones
9. Atom markers on section headers
10. Starburst faintly visible in top-right of primary story card

- [ ] **Step 2: Test mobile layout**

Use browser devtools to resize to 375px width. Check:
1. Wire grid goes to single column
2. Compact row descriptions hidden, just topic name + arrow
3. Next Up cards stacked vertically
4. Escape buttons full-width stacked
5. Nothing overflows horizontally

- [ ] **Step 3: Test empty states**

Run: `bin/rails runner 'Topic.approved.update_all(last_activity_at: 60.days.ago)'`

Check homepage shows "Things are quiet at city hall" message.

Then restore: `bin/rails runner 'Topic.approved.update_all(last_activity_at: 5.days.ago)'`

- [ ] **Step 4: Run full CI**

Run: `bin/ci`
Expected: All green.

- [ ] **Step 5: Commit any polish fixes if needed, then final commit message**

If there were any fixes in this task:
```bash
git add -A
git commit -m "fix: homepage polish from manual verification"
```
