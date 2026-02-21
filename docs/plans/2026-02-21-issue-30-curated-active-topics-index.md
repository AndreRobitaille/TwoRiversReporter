# Issue #30: Curated Active Topics Index — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Change the topics index from "all approved topics" to a curated active-only view with a high-impact hero section, deduplication, and an escape hatch to a research placeholder page.

**Architecture:** Modify `TopicsController#index` to scope to active lifecycle only. Hero section becomes the top-impact recent active topics. Main list excludes hero topics. Add a minimal placeholder page at `/topics/explore` for the future research view (#62).

**Tech Stack:** Rails controllers/views, Pagy pagination, Turbo Stream, Minitest integration tests.

---

### Task 1: Update existing tests to expect active-only behavior

**Files:**
- Modify: `test/controllers/topics_controller_test.rb`

**Step 1: Write failing tests for active-only index**

Add these tests to `topics_controller_test.rb`. They will fail because the controller still shows all statuses.

```ruby
test "index only shows active topics in main list" do
  get topics_url
  assert_response :success

  card_titles = css_select("#all-topics .card-title").map { |node| node.text.strip }
  assert_includes card_titles, @active_topic.name
  refute_includes card_titles, @dormant_topic.name
  refute_includes card_titles, @resolved_topic.name
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
  assert_select "a[href=?]", topics_explore_path
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/topics_controller_test.rb`
Expected: New tests FAIL (old tests may also fail, that's fine — we'll fix everything in Task 2).

**Step 3: Commit failing tests**

```bash
git add test/controllers/topics_controller_test.rb
git commit -m "test: add failing tests for active-only topics index (#30)"
```

---

### Task 2: Update TopicsController#index for active-only + hero dedup

**Files:**
- Modify: `app/controllers/topics_controller.rb`

**Step 1: Rewrite the index action**

Replace the current `index` method with:

```ruby
def index
  active_scope = Topic.publicly_visible
                      .active
                      .joins(:agenda_items)
                      .group("topics.id")
                      .select("topics.*, COUNT(agenda_items.id) as agenda_item_count_cache")

  # Hero: high-impact active topics with recent activity (30 days), ranked by impact
  @hero_topics = active_scope
                   .where(last_activity_at: 30.days.ago..)
                   .order(resident_impact_score: :desc, last_activity_at: :desc)
                   .limit(6)

  # Main list: remaining active topics, excluding hero, paginated
  hero_ids = @hero_topics.map(&:id)
  remaining_scope = active_scope
                      .where.not(id: hero_ids)
                      .order(last_activity_at: :desc)

  @pagy, @topics = pagy(remaining_scope, limit: 20)

  # Highlight signals for all visible topics
  visible_ids = (hero_ids + @topics.map(&:id)).uniq
  @highlight_signals = build_highlight_signals(visible_ids)

  respond_to do |format|
    format.html
    format.turbo_stream
  end
end
```

**Step 2: Run tests**

Run: `bin/rails test test/controllers/topics_controller_test.rb`
Expected: New active-only tests PASS. Some old tests may still fail due to view changes (hero section ID changed from `recent-topics` to `hero-topics`). That's fine — we fix the view in Task 3.

---

### Task 3: Update the topics index view

**Files:**
- Modify: `app/views/topics/index.html.erb`

**Step 1: Rewrite the index view**

Replace the full contents of `index.html.erb` with:

```erb
<% content_for(:title) { "Topics - Two Rivers Reporter" } %>

<div class="page-header">
  <h1 class="page-title">Topics</h1>
  <p class="page-subtitle">Topics currently under discussion in Two Rivers</p>
</div>

<% if @topics.empty? && @hero_topics.empty? %>
  <div class="card text-center" style="padding: var(--space-12);">
    <p class="text-secondary mb-0">No active topics right now. Check back after upcoming meetings.</p>
  </div>
<% else %>
  <% if @hero_topics.present? %>
    <section class="topic-group mb-8" id="hero-topics">
      <div class="group-header mb-4">
        <h2 class="h3 mb-2">What Matters Now</h2>
        <p class="text-secondary mb-0">High-impact topics with recent activity.</p>
      </div>
      <div class="card-grid">
        <% @hero_topics.each do |topic| %>
          <%= render "topics/topic_card", topic: topic, highlight_signals: @highlight_signals %>
        <% end %>
      </div>
    </section>
  <% end %>

  <section class="topic-group mb-8" id="all-topics">
    <div class="group-header mb-4">
      <div class="flex justify-between items-center">
        <h2 class="h3 mb-0">Active Topics</h2>
        <span id="topics-count" class="topics-count text-secondary text-sm">
          Showing <%= @pagy.to %> of <%= @pagy.count %> topics
        </span>
      </div>
    </div>
    <div id="all-topics-cards" class="card-grid">
      <% @topics.each do |topic| %>
        <%= render "topics/topic_card", topic: topic, highlight_signals: @highlight_signals %>
      <% end %>
    </div>

    <div id="all-topics-page">
      <% if @pagy.next %>
        <div class="topics-show-more">
          <%= link_to topics_path(page: @pagy.next, format: :turbo_stream),
                class: "btn btn--secondary" do %>
            Show more
          <% end %>
        </div>
      <% end %>
    </div>
  </section>
<% end %>

<div class="text-center mt-8 mb-8">
  <p class="text-secondary text-sm">
    Looking for older or resolved topics?
    <%= link_to "Explore the full archive", topics_explore_path %>.
  </p>
</div>
```

**Step 2: Run tests**

Run: `bin/rails test test/controllers/topics_controller_test.rb`
Expected: Tests referencing `#recent-topics` will fail. Fix those in Task 4.

---

### Task 4: Fix existing tests for new structure

**Files:**
- Modify: `test/controllers/topics_controller_test.rb`

**Step 1: Update old tests**

The following tests need changes:

1. **"index shows topics sorted by last_activity_at descending"** — Now only active topics appear. Update expected list and section ID.
2. **"index paginates topics with default page size"** — Extra topics must be `lifecycle_status: "active"`. Count changes because hero topics are excluded from paginated list.
3. **"index does not show 'Show more' when all topics fit on one page"** — Only 1 active topic in setup now (others are dormant/resolved/recurring), so count may change.
4. **"index page 2 returns turbo stream"** — Same: extra topics must be active.
5. **"index shows recently updated topics ordered by recency"** — Section renamed to `#hero-topics`. Only active topics with impact scores appear. Update accordingly.
6. **"index shows lifecycle badges on topic cards"** — Only active topics shown on index now. Dormant/Resolved/Recurring won't appear.

Update each test to reflect active-only behavior, `#hero-topics` ID, and deduplication. Remove or adjust assertions about dormant/resolved/recurring topics appearing in the index (they no longer do).

**Step 2: Run full test suite**

Run: `bin/rails test test/controllers/topics_controller_test.rb`
Expected: ALL tests PASS.

**Step 3: Commit controller + view + test changes**

```bash
git add app/controllers/topics_controller.rb app/views/topics/index.html.erb test/controllers/topics_controller_test.rb
git commit -m "feat: curate topics index to active-only with impact-ranked hero (#30)"
```

---

### Task 5: Add research placeholder route, controller, and view

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/topics/explore_controller.rb`
- Create: `app/views/topics/explore/index.html.erb`
- Test: `test/controllers/topics/explore_controller_test.rb`

**Step 1: Write failing test for the placeholder page**

Create `test/controllers/topics/explore_controller_test.rb`:

```ruby
require "test_helper"

class Topics::ExploreControllerTest < ActionDispatch::IntegrationTest
  test "explore page renders with back link to topics" do
    get topics_explore_url
    assert_response :success
    assert_select "a[href=?]", topics_path
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/topics/explore_controller_test.rb`
Expected: FAIL — route/controller/view don't exist yet.

**Step 3: Add route**

In `config/routes.rb`, add after the `resources :topics` line:

```ruby
get "topics/explore", to: "topics/explore#index", as: :topics_explore
```

Note: this line must come BEFORE `resources :topics` to avoid routing conflicts (Rails would try to match `explore` as a topic ID). Move the line above `resources :topics`.

**Step 4: Create controller**

Create `app/controllers/topics/explore_controller.rb`:

```ruby
class Topics::ExploreController < ApplicationController
  def index
  end
end
```

**Step 5: Create view**

Create `app/views/topics/explore/index.html.erb`:

```erb
<% content_for(:title) { "Explore Topics - Two Rivers Reporter" } %>

<div class="page-header">
  <h1 class="page-title">Explore Topics</h1>
  <p class="page-subtitle">Search and filter across all topics — active, resolved, and historical.</p>
</div>

<div class="card text-center" style="padding: var(--space-12);">
  <p class="text-secondary mb-4">This feature is coming soon. We're building a research-oriented view for digging into topic history.</p>
  <p><%= link_to "Back to active topics", topics_path, class: "btn btn--secondary" %></p>
</div>
```

**Step 6: Run tests**

Run: `bin/rails test test/controllers/topics/explore_controller_test.rb`
Expected: PASS.

Run: `bin/rails test test/controllers/topics_controller_test.rb`
Expected: ALL PASS (the `topics_explore_path` link in the view now resolves).

**Step 7: Commit**

```bash
git add config/routes.rb app/controllers/topics/explore_controller.rb app/views/topics/explore/index.html.erb test/controllers/topics/explore_controller_test.rb
git commit -m "feat: add research view placeholder at /topics/explore (#30, #62)"
```

---

### Task 6: Run full CI and verify

**Step 1: Run full test suite**

Run: `bin/rails test`
Expected: ALL PASS.

**Step 2: Run lint + security**

Run: `bin/ci`
Expected: PASS.

**Step 3: Final commit if any fixups needed**

If rubocop or tests surface issues, fix and commit.

---

### Task 7: Update migration plan

**Files:**
- Modify: `docs/topic-first-migration-plan.md`

**Step 1: Mark #30 complete in the migration plan**

Change line 70 (Phase 5, item 4) from:
```
4) Topics index: filters (status, body, timeframe).
```
to:
```
4) [x] Topics index: curated active-only view with explore placeholder.
```

**Step 2: Commit**

```bash
git add docs/topic-first-migration-plan.md
git commit -m "docs: mark #30 complete in migration plan"
```
