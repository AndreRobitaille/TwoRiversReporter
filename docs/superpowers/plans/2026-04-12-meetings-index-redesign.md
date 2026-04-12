# Meetings Index Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the bare data-table meetings index with a three-zone layout: Coming Up (date slab cards), What Happened (headline cards), Find a Meeting (multi-field search).

**Architecture:** The controller builds three collections (`@upcoming`, `@recent`, `@search_results`) with eager-loaded associations. The view renders three zones using new partials. CSS goes in `application.css` under a new Meetings Index section, reusing design tokens and patterns from the homepage (atom marker headers, date slabs).

**Tech Stack:** Rails 8.1, server-rendered HTML, Minitest, Pagy for search pagination

**Spec:** `docs/superpowers/specs/2026-04-12-meetings-index-redesign-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `app/controllers/meetings_controller.rb` | Modify | Build `@upcoming`, `@recent`, `@search_results` with eager loading |
| `app/models/meeting.rb` | Modify | Add `search_multi` class method for multi-field search |
| `app/views/meetings/index.html.erb` | Rewrite | Three-zone layout: Coming Up, What Happened, Find a Meeting |
| `app/views/meetings/_upcoming_card.html.erb` | Create | Date slab + detail panel partial |
| `app/views/meetings/_recent_card.html.erb` | Create | Headline card partial |
| `app/views/meetings/_search_result.html.erb` | Create | Compact search result row partial |
| `app/helpers/meetings_helper.rb` | Modify | Add `best_headline(meeting)`, `council_meeting?(meeting)` helpers |
| `app/assets/stylesheets/application.css` | Modify | Add Meetings Index CSS section |
| `test/controllers/meetings_controller_test.rb` | Modify | Add index tests for all three zones + search |

---

### Task 1: Controller — Build the three collections

**Files:**
- Modify: `app/controllers/meetings_controller.rb`
- Modify: `app/helpers/meetings_helper.rb`
- Test: `test/controllers/meetings_controller_test.rb`

- [ ] **Step 1: Write failing tests for the index action**

Add these tests to `test/controllers/meetings_controller_test.rb`. They test the three collections the controller must provide. Add them after the existing `setup` block's closing `end` and before the first existing test:

```ruby
# --- Index tests ---

test "index assigns upcoming meetings ordered ascending" do
  upcoming = Meeting.create!(
    body_name: "Plan Commission Meeting",
    meeting_type: "Regular",
    starts_at: 5.days.from_now,
    status: "upcoming",
    detail_page_url: "http://example.com/upcoming-1"
  )
  get meetings_url
  assert_response :success
  assert_includes assigns(:upcoming), upcoming
end

test "index assigns recent meetings from last 21 days" do
  get meetings_url
  assert_response :success
  # @meeting from setup is 3.days.ago — should be in recent
  assert_includes assigns(:recent), @meeting
end

test "index excludes meetings older than 21 days from recent" do
  get meetings_url
  assert_response :success
  # other_meeting from setup is 30.days.ago — should NOT be in recent
  old_meeting = Meeting.find_by(detail_page_url: "http://example.com/old-meeting-nav")
  refute_includes assigns(:recent), old_meeting
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/meetings_controller_test.rb -n "/index/"`
Expected: FAIL — the current index action doesn't set `@upcoming`, `@recent`, or `@search_results`.

- [ ] **Step 3: Add helper methods**

Add to `app/helpers/meetings_helper.rb`, before the closing `end` of the module:

```ruby
COUNCIL_PATTERNS = [
  "City Council Meeting",
  "City Council Work Session",
  "City Council Special Meeting"
].freeze

def council_meeting?(meeting)
  meeting.body_name.in?(COUNCIL_PATTERNS) ||
    (meeting.body_name.include?("Council") && !meeting.body_name.include?("Work Session"))
end

def best_headline(meeting)
  summary = meeting.meeting_summaries.find { |s| s.summary_type == "minutes_recap" } ||
            meeting.meeting_summaries.find { |s| s.summary_type == "transcript_recap" } ||
            meeting.meeting_summaries.find { |s| s.summary_type == "packet_analysis" }
  return nil unless summary
  meeting_headline(summary.generation_data)
end
```

Note: `best_headline` iterates the already-eager-loaded `meeting_summaries` association in memory — no additional queries. The priority order matches the meeting show page.

- [ ] **Step 4: Rewrite the index action**

Replace the existing `index` method in `app/controllers/meetings_controller.rb` with:

```ruby
UPCOMING_WINDOW = 21.days
RECENT_WINDOW = 21.days

def index
  @upcoming = Meeting
    .where(starts_at: Time.current..UPCOMING_WINDOW.from_now)
    .includes(:committee, :meeting_documents, :meeting_summaries, agenda_items: :topics)
    .order(starts_at: :asc)

  @recent = Meeting
    .where(starts_at: (RECENT_WINDOW.ago)..Time.current)
    .includes(:committee, :meeting_documents, :meeting_summaries, agenda_items: :topics)
    .order(starts_at: :desc)

  if params[:q].present?
    @pagy, @search_results = pagy(:offset, Meeting.search_multi(params[:q]), limit: 15)
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bin/rails test test/controllers/meetings_controller_test.rb -n "/index/"`
Expected: 4 pass, 1 fail (the `search_results when q param present` test — `search_multi` doesn't exist yet).

- [ ] **Step 6: Commit**

```bash
git add app/controllers/meetings_controller.rb app/helpers/meetings_helper.rb test/controllers/meetings_controller_test.rb
git commit -m "feat(meetings): controller builds upcoming, recent, search collections"
```

---

### Task 2: Multi-field search on Meeting model

**Files:**
- Modify: `app/models/meeting.rb`
- Test: `test/controllers/meetings_controller_test.rb`

- [ ] **Step 1: Write failing tests for search_multi**

Add to `test/controllers/meetings_controller_test.rb`:

```ruby
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/meetings_controller_test.rb -n "/index search/"`
Expected: FAIL — `Meeting.search_multi` is not defined.

- [ ] **Step 3: Implement search_multi**

Add to `app/models/meeting.rb`, after the existing scopes:

```ruby
MONTH_NAMES = {
  "january" => 1, "jan" => 1, "february" => 2, "feb" => 2,
  "march" => 3, "mar" => 3, "april" => 4, "apr" => 4,
  "may" => 5, "june" => 6, "jun" => 6,
  "july" => 7, "jul" => 7, "august" => 8, "aug" => 8,
  "september" => 9, "sep" => 9, "october" => 10, "oct" => 10,
  "november" => 11, "nov" => 11, "december" => 12, "dec" => 12
}.freeze

def self.search_multi(query)
  return none if query.blank?

  terms = query.strip.downcase
  results = none

  # 1. Date detection — extract month/year from query
  date_scope = parse_date_filter(terms)

  # 2. Body name match
  body_matches = where("LOWER(body_name) LIKE ?", "%#{sanitize_sql_like(terms)}%")

  # 3. Topic name match
  topic_matches = joins(agenda_items: :topics)
    .where("LOWER(topics.name) LIKE ?", "%#{sanitize_sql_like(terms)}%")
    .distinct

  # 4. Document full-text match
  doc_ids = MeetingDocument.search(query).pluck(:meeting_id)
  doc_matches = doc_ids.any? ? where(id: doc_ids) : none

  # Union all sources
  combined_ids = (body_matches.pluck(:id) +
                  topic_matches.pluck(:id) +
                  doc_matches.pluck(:id) +
                  (date_scope ? date_scope.pluck(:id) : [])
                 ).uniq

  where(id: combined_ids)
    .includes(:committee, :meeting_documents, :meeting_summaries, agenda_items: :topics)
    .order(starts_at: :desc)
end

def self.parse_date_filter(terms)
  month = nil
  year = nil

  MONTH_NAMES.each do |name, num|
    if terms.include?(name)
      month = num
      break
    end
  end

  year = $1.to_i if terms =~ /\b(20\d{2})\b/

  return nil unless month || year

  if month && year
    start_date = Date.new(year, month, 1)
    where(starts_at: start_date.beginning_of_day..start_date.end_of_month.end_of_day)
  elsif year
    start_date = Date.new(year, 1, 1)
    where(starts_at: start_date.beginning_of_day..start_date.end_of_year.end_of_day)
  elsif month
    # Match the month in any year
    where("EXTRACT(MONTH FROM starts_at) = ?", month)
  end
end

private_class_method :parse_date_filter
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/controllers/meetings_controller_test.rb -n "/index search/"`
Expected: All pass.

- [ ] **Step 5: Run full controller test suite**

Run: `bin/rails test test/controllers/meetings_controller_test.rb`
Expected: All pass (both old show tests and new index tests).

- [ ] **Step 6: Commit**

```bash
git add app/models/meeting.rb test/controllers/meetings_controller_test.rb
git commit -m "feat(meetings): multi-field search across body name, topics, dates, and document text"
```

---

### Task 3: View — Coming Up zone

**Files:**
- Rewrite: `app/views/meetings/index.html.erb`
- Create: `app/views/meetings/_upcoming_card.html.erb`

- [ ] **Step 1: Create the upcoming card partial**

Create `app/views/meetings/_upcoming_card.html.erb`:

```erb
<%# Upcoming meeting card with date slab. Locals: meeting %>
<% is_council = council_meeting?(meeting) %>
<%= link_to meeting_path(meeting), class: "meetings-upcoming-card" do %>
  <div class="meetings-date-slab <%= 'meetings-date-slab--council' if is_council %>">
    <span class="meetings-date-month"><%= meeting.starts_at.strftime("%b") %></span>
    <span class="meetings-date-day"><%= meeting.starts_at.strftime("%-d") %></span>
    <span class="meetings-date-dow"><%= meeting.starts_at.strftime("%a") %></span>
  </div>
  <div class="meetings-upcoming-detail">
    <span class="meetings-upcoming-name"><%= meeting.body_name.sub(/ Meeting$/, "") %></span>
    <span class="meetings-upcoming-meta"><%= meeting.starts_at.strftime("%-l:%M %p") %></span>
    <% approved_topics = meeting.agenda_items.flat_map(&:topics).uniq.select(&:approved?) %>
    <% if approved_topics.any? %>
      <div class="meetings-topic-pills">
        <% approved_topics.first(5).each do |topic| %>
          <span class="meetings-topic-pill"><%= topic.name %></span>
        <% end %>
        <% if approved_topics.size > 5 %>
          <span class="meetings-topic-pill meetings-topic-pill--more">+<%= approved_topics.size - 5 %> more</span>
        <% end %>
      </div>
    <% else %>
      <span class="meetings-upcoming-empty">Scheduled — no agenda yet</span>
    <% end %>
  </div>
  <span class="meetings-card-arrow">→</span>
<% end %>
```

- [ ] **Step 2: Start rewriting the index view**

Replace the entire contents of `app/views/meetings/index.html.erb` with the header and Coming Up zone. We'll add more zones in subsequent tasks:

```erb
<% content_for(:title) { "Meetings - Two Rivers Matters" } %>

<div class="page-header">
  <h1 class="page-title">Meetings</h1>
  <p class="page-subtitle">What happened and what's next</p>
</div>

<%# === COMING UP === %>
<% if @upcoming.any? %>
  <section class="meetings-zone">
    <div class="home-section-header">
      <%= render "shared/atom_marker", size: 20 %>
      <span class="section-label">Coming Up</span>
      <span class="section-line"></span>
    </div>

    <div class="meetings-upcoming-list">
      <% @upcoming.each do |meeting| %>
        <%= render "meetings/upcoming_card", meeting: meeting %>
      <% end %>
    </div>
  </section>
<% end %>
```

- [ ] **Step 3: Start the dev server and verify the Coming Up zone renders**

Run: `bin/dev`

Open the meetings page in a browser. Verify:
- The Coming Up section appears when there are upcoming meetings
- The section is hidden when there are no upcoming meetings
- Date slabs show correctly
- Topic pills render from agenda items

(CSS won't be styled yet — that's Task 6.)

- [ ] **Step 4: Commit**

```bash
git add app/views/meetings/index.html.erb app/views/meetings/_upcoming_card.html.erb
git commit -m "feat(meetings): Coming Up zone with date slab cards"
```

---

### Task 4: View — What Happened zone

**Files:**
- Modify: `app/views/meetings/index.html.erb`
- Create: `app/views/meetings/_recent_card.html.erb`

- [ ] **Step 1: Create the recent card partial**

Create `app/views/meetings/_recent_card.html.erb`:

```erb
<%# Recent meeting card with headline. Locals: meeting %>
<% headline = best_headline(meeting) %>
<%= link_to meeting_path(meeting), class: "meetings-recent-card #{'meetings-recent-card--muted' unless headline}" do %>
  <div class="meetings-recent-header">
    <span class="meetings-recent-name"><%= meeting.body_name.sub(/ Meeting$/, "") %></span>
    <span class="meetings-recent-date"><%= meeting.starts_at.strftime("%b %-d") %></span>
  </div>
  <% if headline %>
    <p class="meetings-recent-headline"><%= headline %></p>
    <% approved_topics = meeting.agenda_items.flat_map(&:topics).uniq.select(&:approved?) %>
    <% if approved_topics.any? %>
      <div class="meetings-topic-pills meetings-topic-pills--warm">
        <% approved_topics.first(4).each do |topic| %>
          <span class="meetings-topic-pill"><%= topic.name %></span>
        <% end %>
      </div>
    <% end %>
  <% else %>
    <p class="meetings-recent-empty">No summary yet</p>
  <% end %>
<% end %>
```

- [ ] **Step 2: Add the What Happened zone to the index view**

Append after the Coming Up section in `app/views/meetings/index.html.erb`:

```erb

<%# === WHAT HAPPENED === %>
<% if @recent.any? %>
  <section class="meetings-zone">
    <div class="home-section-header">
      <%= render "shared/atom_marker", size: 20 %>
      <span class="section-label">What Happened</span>
      <span class="section-line"></span>
    </div>

    <div class="meetings-recent-list">
      <% @recent.each do |meeting| %>
        <%= render "meetings/recent_card", meeting: meeting %>
      <% end %>
    </div>
  </section>
<% end %>
```

- [ ] **Step 3: Verify in browser**

Check that recent meetings appear with headlines (for those that have summaries) and "No summary yet" for those that don't.

- [ ] **Step 4: Commit**

```bash
git add app/views/meetings/index.html.erb app/views/meetings/_recent_card.html.erb
git commit -m "feat(meetings): What Happened zone with headline cards"
```

---

### Task 5: View — Find a Meeting search zone

**Files:**
- Modify: `app/views/meetings/index.html.erb`
- Create: `app/views/meetings/_search_result.html.erb`

- [ ] **Step 1: Create the search result partial**

Create `app/views/meetings/_search_result.html.erb`:

```erb
<%# Search result row. Locals: meeting %>
<% headline = best_headline(meeting) %>
<%= link_to meeting_path(meeting), class: "meetings-search-row #{'meetings-search-row--muted' unless headline}" do %>
  <div class="meetings-search-header">
    <span class="meetings-search-name"><%= meeting.body_name.sub(/ Meeting$/, "") %></span>
    <span class="meetings-search-date"><%= meeting.starts_at.strftime("%b %-d, %Y") %></span>
  </div>
  <% if headline %>
    <p class="meetings-search-headline"><%= headline %></p>
  <% end %>
  <% approved_topics = meeting.agenda_items.flat_map(&:topics).uniq.select(&:approved?) %>
  <% if approved_topics.any? %>
    <div class="meetings-topic-pills meetings-topic-pills--warm">
      <% approved_topics.first(3).each do |topic| %>
        <span class="meetings-topic-pill"><%= topic.name %></span>
      <% end %>
    </div>
  <% end %>
<% end %>
```

- [ ] **Step 2: Add the Find a Meeting zone to the index view**

Append after the What Happened section in `app/views/meetings/index.html.erb`:

```erb

<%# === FIND A MEETING === %>
<section class="meetings-zone">
  <div class="home-section-header">
    <%= render "shared/atom_marker", size: 20 %>
    <span class="section-label">Find a Meeting</span>
    <span class="section-line"></span>
  </div>

  <%= form_with url: meetings_path, method: :get, local: true, class: "meetings-search-form" do |form| %>
    <%= form.text_field :q,
        value: params[:q],
        placeholder: "Search by committee, topic, date, or keyword...",
        class: "form-input meetings-search-input" %>
    <%= form.submit "Search", class: "btn btn--primary" %>
    <% if params[:q].present? %>
      <%= link_to "Clear", meetings_path, class: "btn btn--ghost" %>
    <% end %>
  <% end %>

  <% if params[:q].present? %>
    <% if @search_results.any? %>
      <div class="meetings-search-results">
        <% @search_results.each do |meeting| %>
          <%= render "meetings/search_result", meeting: meeting %>
        <% end %>
      </div>
      <% if @pagy.next %>
        <div class="meetings-show-more">
          <%= link_to "Show more results", meetings_path(q: params[:q], page: @pagy.next), class: "btn btn--secondary" %>
        </div>
      <% end %>
    <% else %>
      <div class="meetings-search-empty">
        <p>No meetings found for "<strong><%= params[:q] %></strong>"</p>
        <p class="meetings-search-hint">Try a different spelling, a committee name, or a year like 2025.</p>
      </div>
    <% end %>
  <% end %>
</section>
```

- [ ] **Step 3: Verify in browser**

Test the following searches:
- A committee name (e.g., "city council")
- A topic name that exists
- A year (e.g., "2026")
- A month name (e.g., "april")
- A nonsense query — verify the helpful empty state appears

- [ ] **Step 4: Commit**

```bash
git add app/views/meetings/index.html.erb app/views/meetings/_search_result.html.erb
git commit -m "feat(meetings): Find a Meeting search zone with multi-field search"
```

---

### Task 6: CSS — Style all three zones

**Files:**
- Modify: `app/assets/stylesheets/application.css`

- [ ] **Step 1: Find the insertion point**

Open `app/assets/stylesheets/application.css`. Find the existing `/* Meeting Detail Page */` section (around line 994). Insert the new Meetings Index section **before** it.

- [ ] **Step 2: Add the Meetings Index CSS**

Insert the following CSS block before the `/* Meeting Detail Page */` comment:

```css
/* ============================================
   Meetings Index
   ============================================ */

.meetings-zone {
  margin-bottom: var(--space-10);
}

/* --- Coming Up: Date Slab Cards --- */

.meetings-upcoming-list {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
}

.meetings-upcoming-card {
  display: flex;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-sm);
  overflow: hidden;
  text-decoration: none;
  color: inherit;
  transition: box-shadow var(--transition-normal), transform var(--transition-fast);
}

.meetings-upcoming-card:hover {
  box-shadow: var(--shadow-md);
  transform: translateY(-1px);
  color: inherit;
  text-decoration: none;
}

.meetings-date-slab {
  font-family: var(--font-display);
  font-weight: 800;
  padding: 0.75rem 1rem;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  min-width: 4.5rem;
  line-height: 1.1;
  color: var(--color-text-inverse);
  background: var(--color-teal);
  box-shadow: inset -2px 0 6px rgb(0 0 0 / 0.15);
}

.meetings-date-slab--council {
  background: var(--color-terra-cotta);
}

.meetings-date-month {
  font-size: 0.6rem;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  opacity: 0.85;
}

.meetings-date-day {
  font-size: var(--font-size-2xl);
  font-weight: 900;
}

.meetings-date-dow {
  font-family: var(--font-data);
  font-size: 0.55rem;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  opacity: 0.8;
  margin-top: 0.1rem;
}

.meetings-upcoming-detail {
  padding: var(--space-3) var(--space-4);
  display: flex;
  flex-direction: column;
  justify-content: center;
  flex: 1;
  gap: var(--space-1);
}

.meetings-upcoming-name {
  font-family: var(--font-display);
  font-weight: 700;
  font-size: var(--font-size-base);
  text-transform: uppercase;
  letter-spacing: 0.02em;
  color: var(--color-teal);
}

.meetings-upcoming-meta {
  font-family: var(--font-data);
  font-size: var(--font-size-xs);
  color: var(--color-text-secondary);
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.meetings-upcoming-empty {
  font-family: var(--font-body);
  font-size: var(--font-size-sm);
  color: var(--color-text-muted);
}

.meetings-card-arrow {
  display: flex;
  align-items: center;
  padding: 0 var(--space-4);
  color: var(--color-text-muted);
  font-size: var(--font-size-base);
  transition: color var(--transition-fast), transform var(--transition-fast);
}

.meetings-upcoming-card:hover .meetings-card-arrow {
  color: var(--color-teal);
  transform: translateX(3px);
}

/* --- Topic Pills (shared across zones) --- */

.meetings-topic-pills {
  display: flex;
  gap: var(--space-1);
  flex-wrap: wrap;
  margin-top: var(--space-1);
}

.meetings-topic-pill {
  font-family: var(--font-body);
  font-size: 0.7rem;
  padding: 0.15rem 0.5rem;
  border-radius: 99px;
  background: var(--color-primary-light);
  color: var(--color-teal);
}

.meetings-topic-pills--warm .meetings-topic-pill {
  background: var(--color-warning-light);
  color: var(--color-text-secondary);
}

.meetings-topic-pill--more {
  background: transparent;
  color: var(--color-text-muted);
  font-style: italic;
}

/* --- What Happened: Recent Cards --- */

.meetings-recent-list {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
}

.meetings-recent-card {
  display: block;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  padding: var(--space-4);
  text-decoration: none;
  color: inherit;
  transition: box-shadow var(--transition-normal), transform var(--transition-fast);
}

.meetings-recent-card:hover {
  box-shadow: var(--shadow-md);
  transform: translateY(-1px);
  color: inherit;
  text-decoration: none;
}

.meetings-recent-card--muted {
  opacity: 0.6;
}

.meetings-recent-header {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
}

.meetings-recent-name {
  font-family: var(--font-display);
  font-weight: 700;
  font-size: var(--font-size-sm);
  text-transform: uppercase;
  letter-spacing: 0.02em;
  color: var(--color-teal);
}

.meetings-recent-date {
  font-family: var(--font-data);
  font-size: var(--font-size-xs);
  color: var(--color-text-secondary);
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.meetings-recent-headline {
  font-family: var(--font-body);
  font-size: var(--font-size-sm);
  font-style: italic;
  color: var(--color-text);
  margin: var(--space-1) 0 0;
  line-height: var(--line-height-normal);
}

.meetings-recent-empty {
  font-family: var(--font-body);
  font-size: var(--font-size-sm);
  color: var(--color-text-muted);
  margin: var(--space-1) 0 0;
}

/* --- Find a Meeting: Search Zone --- */

.meetings-search-form {
  display: flex;
  gap: var(--space-2);
  margin-bottom: var(--space-4);
}

.meetings-search-input {
  flex: 1;
}

.meetings-search-results {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  overflow: hidden;
}

.meetings-search-row {
  display: block;
  padding: var(--space-3) var(--space-4);
  border-bottom: 1px solid var(--color-border);
  text-decoration: none;
  color: inherit;
  transition: background var(--transition-fast);
}

.meetings-search-row:last-child {
  border-bottom: none;
}

.meetings-search-row:hover {
  background: var(--color-primary-light);
  text-decoration: none;
  color: inherit;
}

.meetings-search-row--muted {
  opacity: 0.6;
}

.meetings-search-header {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
}

.meetings-search-name {
  font-family: var(--font-display);
  font-weight: 700;
  font-size: var(--font-size-sm);
  text-transform: uppercase;
  letter-spacing: 0.02em;
  color: var(--color-teal);
}

.meetings-search-date {
  font-family: var(--font-data);
  font-size: var(--font-size-xs);
  color: var(--color-text-secondary);
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.meetings-search-headline {
  font-family: var(--font-body);
  font-size: var(--font-size-sm);
  font-style: italic;
  color: var(--color-text);
  margin: var(--space-1) 0 0;
  line-height: var(--line-height-normal);
}

.meetings-search-empty {
  text-align: center;
  padding: var(--space-8) var(--space-4);
  color: var(--color-text-secondary);
}

.meetings-search-empty p:first-child {
  font-size: var(--font-size-base);
  margin-bottom: var(--space-2);
}

.meetings-search-hint {
  font-size: var(--font-size-sm);
  color: var(--color-text-muted);
}

.meetings-show-more {
  text-align: center;
  padding: var(--space-4) 0;
}

/* --- Responsive --- */

@media (max-width: 600px) {
  .meetings-upcoming-card {
    /* Keep horizontal layout but let detail text wrap tighter */
  }

  .meetings-date-slab {
    min-width: 3.5rem;
    padding: 0.5rem 0.65rem;
  }

  .meetings-date-day {
    font-size: var(--font-size-xl);
  }

  .meetings-search-form {
    flex-direction: column;
  }

  .meetings-search-input {
    max-width: none;
  }
}
```

- [ ] **Step 3: Verify in browser**

Check all three zones with the dev server running:
- Coming Up date slabs: terra-cotta for council, teal for others
- Date slab text: month/day/dow stacked correctly
- Topic pills render with appropriate colors
- What Happened cards: headlines italic, muted treatment for no-summary
- Search: results in grouped-row style, hover highlights
- Mobile: check at 400px width — slabs shrink, search form stacks

- [ ] **Step 4: Commit**

```bash
git add app/assets/stylesheets/application.css
git commit -m "feat(meetings): atomic-era CSS for all three index zones"
```

---

### Task 7: Integration test and polish

**Files:**
- Modify: `test/controllers/meetings_controller_test.rb`

- [ ] **Step 1: Add view-level integration tests**

Add to `test/controllers/meetings_controller_test.rb`:

```ruby
test "index renders section headers" do
  # Create an upcoming meeting so Coming Up section appears
  Meeting.create!(
    body_name: "City Council Meeting",
    meeting_type: "Regular",
    starts_at: 3.days.from_now,
    status: "upcoming",
    detail_page_url: "http://example.com/upcoming-render"
  )
  get meetings_url
  assert_response :success
  assert_select ".section-label", text: "Coming Up"
  assert_select ".section-label", text: "What Happened"
  assert_select ".section-label", text: "Find a Meeting"
end

test "index hides coming up when no upcoming meetings" do
  get meetings_url
  assert_response :success
  refute_select ".section-label", text: "Coming Up"
end

test "index renders headline in recent card" do
  MeetingSummary.create!(
    meeting: @meeting,
    summary_type: "minutes_recap",
    generation_data: { "headline" => "Big news from council" }
  )
  get meetings_url
  assert_response :success
  assert_select ".meetings-recent-headline", text: /Big news from council/
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
```

- [ ] **Step 2: Run full test suite**

Run: `bin/rails test test/controllers/meetings_controller_test.rb`
Expected: All tests pass.

- [ ] **Step 3: Run RuboCop**

Run: `bin/rubocop app/controllers/meetings_controller.rb app/models/meeting.rb app/helpers/meetings_helper.rb app/views/meetings/`
Expected: No offenses. Fix any that appear.

- [ ] **Step 4: Run full CI**

Run: `bin/ci`
Expected: Clean pass.

- [ ] **Step 5: Final browser check**

With `bin/dev` running, check:
- The full page flow from top to bottom
- Click into a meeting from each zone (upcoming card, recent card, search result) — all link correctly
- Mobile layout at 400px
- Empty states: no upcoming meetings, search with no results

- [ ] **Step 6: Commit**

```bash
git add test/controllers/meetings_controller_test.rb
git commit -m "test(meetings): integration tests for index page zones and search"
```

---

## Summary

| Task | What it builds | Est. size |
|------|----------------|-----------|
| 1 | Controller with three collections + helpers | Small |
| 2 | Multi-field search on Meeting model | Medium |
| 3 | Coming Up zone (date slab partial + view) | Small |
| 4 | What Happened zone (headline card partial + view) | Small |
| 5 | Find a Meeting zone (search form + result partial) | Small |
| 6 | All CSS for three zones | Medium |
| 7 | Integration tests + polish | Small |
