# Issue #36: Topics Index Pagination — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the all-at-once topics index with a paginated flat list using Pagy + Turbo Frames, dramatically improving load times.

**Architecture:** Add Pagy gem for pagination mechanics. Refactor `TopicsController#index` to load 20 topics per page (flat by recency, no lifecycle grouping). Use a Turbo Frame around the "show more" area so subsequent pages append without full-page reloads. Keep the "Recently Updated" hero section unchanged.

**Tech Stack:** Pagy gem, Turbo Frames, Minitest

---

### Task 1: Add the Pagy gem

**Files:**
- Modify: `Gemfile`
- Modify: `app/controllers/application_controller.rb`

**Step 1: Add pagy to Gemfile**

Add after the `turbo-rails` line:

```ruby
gem "pagy", "~> 9.0"
```

**Step 2: Run bundle install**

Run: `bundle install`
Expected: pagy gem installed successfully

**Step 3: Include Pagy in ApplicationController**

Add at the top of `ApplicationController`:

```ruby
include Pagy::Backend
```

**Step 4: Include Pagy helpers in ApplicationHelper**

Add to `app/helpers/application_helper.rb`:

```ruby
include Pagy::Frontend
```

**Step 5: Commit**

```
feat: add pagy gem for pagination
```

---

### Task 2: Write failing tests for the new paginated index

**Files:**
- Modify: `test/controllers/topics_controller_test.rb`

The existing tests assert lifecycle group headers (`h2` with "Active Topics", etc.) and group ordering. These must be replaced with tests for the new flat-list behavior.

**Step 1: Replace the existing index tests with paginated flat-list tests**

Remove these tests:
- `"index groups topics by lifecycle status"`
- `"index shows counts in headers"`

Replace with these new tests:

```ruby
test "index shows topics sorted by last_activity_at descending" do
  get topics_url
  assert_response :success

  titles = css_select("#all-topics .card-title").map { |node| node.text.strip }
  assert_equal [
    @active_topic.name,
    @recurring_topic.name,
    @dormant_topic.name,
    @resolved_topic.name
  ], titles
end

test "index paginates topics with default page size" do
  # Create enough topics to exceed one page (20 per page)
  18.times do |i|
    topic = Topic.create!(
      name: "Extra Topic #{i}",
      lifecycle_status: "active",
      status: "approved",
      last_activity_at: (i + 10).days.ago
    )
    AgendaItemTopic.create!(topic: topic, agenda_item: @agenda_item)
  end

  get topics_url
  assert_response :success

  # Should show 20 of 22 total topics
  cards = css_select("#all-topics .card")
  assert_equal 20, cards.size

  # Should show count indicator
  assert_select ".topics-count", text: /Showing 20 of 22/

  # Should show "Show more" button
  assert_select "a", text: /Show more/
end

test "index does not show 'Show more' when all topics fit on one page" do
  get topics_url
  assert_response :success

  # Only 4 topics in setup — no pagination needed
  assert_select "a", text: /Show more/, count: 0
end

test "index page 2 returns topics in a turbo frame" do
  18.times do |i|
    topic = Topic.create!(
      name: "Extra Topic #{i}",
      lifecycle_status: "active",
      status: "approved",
      last_activity_at: (i + 10).days.ago
    )
    AgendaItemTopic.create!(topic: topic, agenda_item: @agenda_item)
  end

  get topics_url(page: 2)
  assert_response :success

  # Page 2 should return a turbo frame response with remaining topics
  assert_select "turbo-frame#all-topics-page"
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/topics_controller_test.rb`
Expected: The new tests fail (no `#all-topics` element, no Pagy, no count indicator)

**Step 3: Commit**

```
test: add failing tests for paginated topics index (#36)
```

---

### Task 3: Refactor TopicsController#index for pagination

**Files:**
- Modify: `app/controllers/topics_controller.rb`

**Step 1: Rewrite the index action**

Replace the entire `index` action with:

```ruby
def index
  base_scope = Topic.publicly_visible
                    .joins(:agenda_items)
                    .group("topics.id")
                    .select("topics.*, COUNT(agenda_items.id) as agenda_item_count_cache")
                    .order(last_activity_at: :desc)

  # Recently updated topics (hero section — always first 6)
  @recent_topics = base_scope.where.not(last_activity_at: nil).limit(6)

  # Paginated flat list
  @pagy, @topics = pagy(base_scope, limit: 20)

  # Only compute highlight signals for visible topics
  visible_ids = (@recent_topics.map(&:id) + @topics.map(&:id)).uniq
  @highlight_signals = build_highlight_signals(visible_ids)
end
```

Remove `status_order` and `group_last_activity_sort_key` private methods (no longer needed).

**Step 2: Handle Turbo Frame requests for "show more"**

For page 2+, we only need the topic cards + the next "show more" frame, not the full page layout. Add to the controller:

```ruby
def index
  # ... (above code) ...

  if request.headers["Turbo-Frame"] == "all-topics-page"
    render partial: "topics/topic_page", locals: { topics: @topics, pagy: @pagy, highlight_signals: @highlight_signals }, layout: false
  end
end
```

**Step 3: Run tests**

Run: `bin/rails test test/controllers/topics_controller_test.rb`
Expected: Some tests may still fail (view not updated yet). Controller logic is correct.

**Step 4: Commit**

```
refactor: paginate topics index with Pagy, flat list by recency (#36)
```

---

### Task 4: Update the topics index view

**Files:**
- Modify: `app/views/topics/index.html.erb`
- Create: `app/views/topics/_topic_card.html.erb`
- Create: `app/views/topics/_topic_page.html.erb`

**Step 1: Extract the topic card into a partial**

Create `app/views/topics/_topic_card.html.erb`:

```erb
<% signals = highlight_signals[topic.id] %>
<%= link_to topic_path(topic),
      class: ["card card--clickable", ("card--highlighted" if signals)].compact.join(" "),
      style: "text-decoration: none; color: inherit;" do %>
  <div class="card-header">
    <div class="flex justify-between items-center">
      <h3 class="card-title"><%= topic.name %></h3>
      <%= topic_lifecycle_badge(topic.lifecycle_status) if topic.lifecycle_status %>
    </div>
  </div>
  <div class="card-body">
    <div class="flex justify-between text-secondary text-sm">
      <span><%= topic.try(:agenda_item_count_cache) || topic.agenda_items.count %> agenda items</span>
      <% if topic.last_activity_at %>
        <span>Updated <%= time_ago_in_words(topic.last_activity_at) %> ago</span>
      <% end %>
    </div>
    <% if signals %>
      <div class="card-signals">
        <% signals.each do |label| %>
          <span class="badge badge--outline"><%= label %></span>
        <% end %>
      </div>
    <% end %>
  </div>
<% end %>
```

**Step 2: Create the paginated page partial**

Create `app/views/topics/_topic_page.html.erb`. This is what Turbo Frame requests return:

```erb
<% topics.each do |topic| %>
  <%= render "topics/topic_card", topic: topic, highlight_signals: highlight_signals %>
<% end %>

<% if pagy.next %>
  <turbo-frame id="all-topics-page" data-turbo-action="advance">
    <div class="topics-show-more">
      <%= link_to topics_path(page: pagy.next),
            class: "btn btn--outline",
            data: { turbo_frame: "all-topics-page" } do %>
        Show more (<%= pagy.next * pagy.limit > pagy.count ? pagy.count - pagy.in : pagy.limit %> more)
      <% end %>
    </div>
  </turbo-frame>
<% end %>
```

**Step 3: Rewrite the index view**

Replace the full contents of `app/views/topics/index.html.erb`:

```erb
<% content_for(:title) { "Topics - Two Rivers Reporter" } %>

<div class="page-header">
  <h1 class="page-title">Topics</h1>
  <p class="page-subtitle">Explore issues discussed across city meetings</p>
</div>

<% if @topics.empty? && @recent_topics.empty? %>
  <div class="card text-center" style="padding: var(--space-12);">
    <p class="text-secondary mb-0">No topics have been categorized yet.</p>
  </div>
<% else %>
  <% if @recent_topics.present? %>
    <section class="topic-group mb-8" id="recent-topics">
      <div class="group-header mb-4">
        <h2 class="h3 mb-2">Recently Updated</h2>
        <p class="text-secondary mb-0">The latest topics with new activity across meetings.</p>
      </div>
      <div class="card-grid">
        <% @recent_topics.each do |topic| %>
          <%= render "topics/topic_card", topic: topic, highlight_signals: @highlight_signals %>
        <% end %>
      </div>
    </section>
  <% end %>

  <section class="topic-group mb-8" id="all-topics">
    <div class="group-header mb-4">
      <div class="flex justify-between items-center">
        <h2 class="h3 mb-0">All Topics</h2>
        <span class="topics-count text-secondary text-sm">
          Showing <%= @pagy.from %>–<%= @pagy.to %> of <%= @pagy.count %> topics
        </span>
      </div>
    </div>
    <div class="card-grid">
      <% @topics.each do |topic| %>
        <%= render "topics/topic_card", topic: topic, highlight_signals: @highlight_signals %>
      <% end %>
    </div>

    <% if @pagy.next %>
      <turbo-frame id="all-topics-page" data-turbo-action="advance">
        <div class="topics-show-more">
          <%= link_to topics_path(page: @pagy.next),
                class: "btn btn--outline",
                data: { turbo_frame: "all-topics-page" } do %>
            Show more
          <% end %>
        </div>
      </turbo-frame>
    <% end %>
  </section>
<% end %>
```

**Step 4: Run tests**

Run: `bin/rails test test/controllers/topics_controller_test.rb`
Expected: All tests pass

**Step 5: Commit**

```
feat: flat paginated topics index with show-more button (#36)
```

---

### Task 5: Add CSS for the show-more button

**Files:**
- Modify: `app/assets/stylesheets/application.css`

**Step 1: Add show-more styling**

Add after the existing `.card-grid` block (around line 570):

```css
.topics-show-more {
  display: flex;
  justify-content: center;
  padding: var(--space-8) 0 var(--space-4);
}

.topics-count {
  white-space: nowrap;
}
```

**Step 2: Verify visually**

Run: `bin/dev` and visit `/topics`
Expected: Topics show as a flat list by recency. "Show more" button is centered below the grid. Count shows "Showing 1–20 of N topics".

**Step 3: Commit**

```
style: add show-more button and count indicator styles (#36)
```

---

### Task 6: Fix the Turbo Frame append pattern

The "show more" pattern as designed replaces the frame with new cards. But we want to **append** cards, not replace the whole list. The standard Turbo approach is: the "show more" frame lives **after** the card grid. When clicked, the response contains the new cards **plus** a new frame. The new cards render outside the frame (using `turbo-frame` targeting), while the frame replaces itself.

A simpler approach that works natively: the `_topic_page` partial returns cards + a new show-more frame, and the controller renders this into the frame. The cards appear inside the frame until it's replaced by the next page's frame. This means each "show more" click replaces the previous batch's frame with new cards + a new frame — a growing page.

**Files:**
- Modify: `app/views/topics/index.html.erb`
- Modify: `app/views/topics/_topic_page.html.erb`
- Modify: `app/controllers/topics_controller.rb`

**Step 1: Adjust the index view**

Move the Turbo Frame to wrap a self-replacing section. The card grid stays outside the frame. The frame only contains the "load more" trigger:

In `index.html.erb`, change the `#all-topics` section's frame area to:

```erb
<turbo-frame id="all-topics-page">
  <% if @pagy.next %>
    <div class="topics-show-more">
      <%= link_to topics_path(page: @pagy.next),
            class: "btn btn--outline",
            data: { turbo_frame: "all-topics-page" } do %>
        Show more
      <% end %>
    </div>
  <% end %>
</turbo-frame>
```

**Step 2: Adjust the topic_page partial**

The partial response (for Turbo Frame requests) should return the new cards **outside** the frame, plus the next frame:

```erb
<turbo-frame id="all-topics-page">
  <div class="card-grid">
    <% topics.each do |topic| %>
      <%= render "topics/topic_card", topic: topic, highlight_signals: highlight_signals %>
    <% end %>
  </div>

  <% if pagy.next %>
    <div class="topics-show-more">
      <%= link_to topics_path(page: pagy.next),
            class: "btn btn--outline",
            data: { turbo_frame: "all-topics-page" } do %>
        Show more
      <% end %>
    </div>
  <% end %>
</turbo-frame>
```

This way each click replaces the frame with: a new `.card-grid` of results + a new show-more button (or nothing if last page). The page grows downward with each click.

**Step 3: Update the count indicator**

The count in the initial render is static. For simplicity, keep it showing total count (`103 topics`) rather than trying to update it dynamically. Change the count line in `index.html.erb` to:

```erb
<span class="topics-count text-secondary text-sm">
  <%= @pagy.count %> topics
</span>
```

**Step 4: Run tests**

Run: `bin/rails test test/controllers/topics_controller_test.rb`
Expected: All tests pass

**Step 5: Verify manually**

Run: `bin/dev`, visit `/topics`. Click "Show more" — new cards should appear below the first batch. Click again — more cards appear.

**Step 6: Commit**

```
fix: turbo frame append pattern for show-more pagination (#36)
```

---

### Task 7: Update the topic-first-migration-plan

**Files:**
- Modify: `docs/topic-first-migration-plan.md`

**Step 1: Check off item 5 in Phase 5**

Change line for item 5 from:
```
5) Topics index: pagination + activity window rules.
```
to:
```
5) [x] Topics index: pagination + activity window rules.
```

**Step 2: Commit**

```
docs: mark #36 pagination complete in migration plan
```

---

## Summary of changes

| File | Action |
|------|--------|
| `Gemfile` | Add `pagy` gem |
| `app/controllers/application_controller.rb` | Include `Pagy::Backend` |
| `app/helpers/application_helper.rb` | Include `Pagy::Frontend` |
| `app/controllers/topics_controller.rb` | Replace grouped query with paginated flat list |
| `app/views/topics/index.html.erb` | Flat list + show-more Turbo Frame |
| `app/views/topics/_topic_card.html.erb` | New — extracted card partial |
| `app/views/topics/_topic_page.html.erb` | New — Turbo Frame response partial |
| `app/assets/stylesheets/application.css` | Show-more button styles |
| `test/controllers/topics_controller_test.rb` | Updated tests for flat pagination |
| `docs/topic-first-migration-plan.md` | Mark item complete |
