# Topic Show Page: Consistent Layout Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rewrite the topic show page with a fixed inverted-pyramid section order, always-visible sections with empty states, and structured JSON rendering from `generation_data`.

**Architecture:** The topic show page renders all 6 sections unconditionally. Briefing content comes from `TopicBriefing.generation_data` (pass 1 JSON) instead of pass 2 markdown fields. Markdown fields are fallbacks for briefings without `generation_data`. New timeline CSS for the Record section. New warm callout for What to Watch.

**Tech Stack:** Rails ERB views, CSS custom properties, Minitest integration tests

**Design doc:** `docs/plans/2026-03-01-topic-show-consistent-layout-design.md`

---

### Task 1: Add helper methods for structured generation_data rendering

**Files:**
- Modify: `app/helpers/topics_helper.rb`
- Test: `test/helpers/topics_helper_test.rb`

**Step 1: Write the failing tests**

Add to `test/helpers/topics_helper_test.rb`:

```ruby
test "briefing_what_to_watch extracts from generation_data" do
  briefing = OpenStruct.new(generation_data: {
    "editorial_analysis" => { "what_to_watch" => "Watch for a vote on the budget." }
  })
  assert_equal "Watch for a vote on the budget.", briefing_what_to_watch(briefing)
end

test "briefing_what_to_watch returns nil when generation_data is nil" do
  briefing = OpenStruct.new(generation_data: nil)
  assert_nil briefing_what_to_watch(briefing)
end

test "briefing_what_to_watch returns nil for nil briefing" do
  assert_nil briefing_what_to_watch(nil)
end

test "briefing_current_state extracts from generation_data" do
  briefing = OpenStruct.new(generation_data: {
    "editorial_analysis" => { "current_state" => "The council approved the plan." }
  })
  assert_equal "The council approved the plan.", briefing_current_state(briefing)
end

test "briefing_current_state falls back to editorial_content" do
  briefing = OpenStruct.new(generation_data: nil, editorial_content: "Fallback content.")
  assert_equal "Fallback content.", briefing_current_state(briefing)
end

test "briefing_process_concerns extracts from generation_data" do
  briefing = OpenStruct.new(generation_data: {
    "editorial_analysis" => { "process_concerns" => ["No public input.", "Rushed timeline."] }
  })
  assert_equal ["No public input.", "Rushed timeline."], briefing_process_concerns(briefing)
end

test "briefing_process_concerns returns empty array when missing" do
  briefing = OpenStruct.new(generation_data: { "editorial_analysis" => {} })
  assert_equal [], briefing_process_concerns(briefing)
end

test "briefing_factual_record extracts structured entries from generation_data" do
  briefing = OpenStruct.new(generation_data: {
    "factual_record" => [
      { "date" => "2025-09-02", "event" => "Council approved plan.", "meeting" => "City Council, Sep 2" },
      { "date" => "2025-11-05", "event" => "Item appeared on agenda.", "meeting" => "Public Works, Nov 5" }
    ]
  })
  result = briefing_factual_record(briefing)
  assert_equal 2, result.size
  assert_equal "2025-09-02", result.first["date"]
end

test "briefing_factual_record returns empty array when generation_data is nil" do
  briefing = OpenStruct.new(generation_data: nil)
  assert_equal [], briefing_factual_record(briefing)
end

test "briefing_headline_text extracts from generation_data with fallback" do
  briefing = OpenStruct.new(generation_data: { "headline" => "From JSON" }, headline: "From field")
  assert_equal "From JSON", briefing_headline_text(briefing)
end

test "briefing_headline_text falls back to headline field" do
  briefing = OpenStruct.new(generation_data: nil, headline: "From field")
  assert_equal "From field", briefing_headline_text(briefing)
end

test "format_record_date formats ISO date as month day year" do
  assert_equal "Sep 2, 2025", format_record_date("2025-09-02")
  assert_equal "Nov 15, 2025", format_record_date("2025-11-15")
end

test "format_record_date returns original string for unparseable dates" do
  assert_equal "not a date", format_record_date("not a date")
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/helpers/topics_helper_test.rb -v`
Expected: FAIL — undefined methods

**Step 3: Write the helper methods**

Add to `app/helpers/topics_helper.rb` (inside the module, before the `private` section or at the end):

```ruby
def briefing_what_to_watch(briefing)
  briefing&.generation_data&.dig("editorial_analysis", "what_to_watch")
end

def briefing_current_state(briefing)
  briefing&.generation_data&.dig("editorial_analysis", "current_state") ||
    briefing&.editorial_content
end

def briefing_process_concerns(briefing)
  briefing&.generation_data&.dig("editorial_analysis", "process_concerns") || []
end

def briefing_factual_record(briefing)
  briefing&.generation_data&.dig("factual_record") || []
end

def briefing_headline_text(briefing)
  briefing&.generation_data&.dig("headline") || briefing&.headline
end

def format_record_date(date_string)
  Date.parse(date_string).strftime("%b %-d, %Y")
rescue Date::Error, TypeError
  date_string.to_s
end
```

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/helpers/topics_helper_test.rb -v`
Expected: All PASS

**Step 5: Commit**

```
git add app/helpers/topics_helper.rb test/helpers/topics_helper_test.rb
git commit -m "feat: add helper methods for structured briefing rendering"
```

---

### Task 2: Add timeline and what-to-watch CSS

**Files:**
- Modify: `app/assets/stylesheets/application.css`

**Step 1: Add the new CSS rules**

Add after the existing `.topic-record-list li:last-child` block (around line 1935) in the `/* === Topic Show Page === */` section:

```css
/* What to Watch — warm callout card */
.topic-watch-callout {
  background: var(--color-accent-warm-bg);
  border: 1px solid color-mix(in srgb, var(--color-accent-warm) 25%, var(--color-border));
  border-left: 4px solid var(--color-accent-warm);
  border-radius: var(--radius-lg);
  padding: var(--space-5) var(--space-6);
}

.topic-watch-callout p {
  margin: 0;
  line-height: var(--line-height-relaxed);
}

/* Process Concerns — secondary callout */
.topic-concerns-callout {
  background: var(--color-surface-raised);
  border: 1px solid var(--color-border);
  border-left: 3px solid var(--color-text-muted);
  border-radius: var(--radius-lg);
  padding: var(--space-4) var(--space-5);
  margin-top: var(--space-4);
}

.topic-concerns-callout .concerns-label {
  font-size: var(--font-size-sm);
  font-weight: var(--font-weight-semibold);
  color: var(--color-text-secondary);
  margin-bottom: var(--space-2);
}

.topic-concerns-callout ul {
  margin: 0;
  padding-left: var(--space-5);
}

.topic-concerns-callout li {
  font-size: var(--font-size-sm);
  line-height: var(--line-height-normal);
  color: var(--color-text-secondary);
  margin-bottom: var(--space-1);
}

.topic-concerns-callout li:last-child {
  margin-bottom: 0;
}

/* Record Timeline */
.topic-timeline {
  position: relative;
  padding-left: var(--space-1);
}

.topic-timeline-entry {
  display: grid;
  grid-template-columns: 5.5rem 1fr;
  gap: var(--space-4);
  padding-bottom: var(--space-6);
  position: relative;
}

.topic-timeline-entry:last-child {
  padding-bottom: 0;
}

/* Vertical connecting line */
.topic-timeline-entry:not(:last-child)::before {
  content: "";
  position: absolute;
  left: 2.75rem;
  top: 1.5rem;
  bottom: 0;
  width: 2px;
  background: var(--color-border);
}

.topic-timeline-date {
  font-size: var(--font-size-sm);
  font-weight: var(--font-weight-semibold);
  color: var(--color-text-secondary);
  text-align: right;
  line-height: var(--line-height-tight);
  padding-top: 2px;
}

.topic-timeline-content {
  line-height: var(--line-height-normal);
}

.topic-timeline-meeting {
  display: block;
  font-size: var(--font-size-xs);
  color: var(--color-text-muted);
  margin-top: var(--space-1);
}

/* Section empty states — inline with sections */
.section-empty {
  color: var(--color-text-muted);
  font-size: var(--font-size-sm);
  padding: var(--space-4) 0;
}
```

**Step 2: Verify CSS loads without errors**

Run: `bin/rails runner "puts 'CSS file exists: ' + File.exist?('app/assets/stylesheets/application.css').to_s"`
Expected: `CSS file exists: true`

**Step 3: Commit**

```
git add app/assets/stylesheets/application.css
git commit -m "feat: add timeline and what-to-watch CSS for topic show page"
```

---

### Task 3: Rewrite topic show view with fixed section order

**Files:**
- Modify: `app/views/topics/show.html.erb`

**Step 1: Rewrite the view**

Replace the entire contents of `app/views/topics/show.html.erb` with:

```erb
<% content_for(:title) { "#{@topic.name} - Topics - Two Rivers Matters" } %>

<%# === 1. Header (always present) === %>
<div class="page-header">
  <h1 class="page-title"><%= @topic.name %></h1>
  <% if @topic.description.present? %>
    <p class="page-subtitle"><%= @topic.description %></p>
  <% end %>
  <div class="flex items-center gap-2 mt-2">
    <% if @topic.lifecycle_status %>
      <%= topic_lifecycle_badge(@topic.lifecycle_status) %>
    <% end %>
    <% if @briefing %>
      <%= briefing_freshness_badge(@briefing) %>
    <% end %>
  </div>
</div>

<%# === 2. What to Watch (warm callout) === %>
<section class="topic-watch section">
  <h2 class="section-title">What to Watch</h2>
  <% watch_text = briefing_what_to_watch(@briefing) %>
  <% if watch_text.present? %>
    <div class="topic-watch-callout">
      <p><%= render_inline_markdown(watch_text) %></p>
    </div>
  <% else %>
    <p class="section-empty">No analysis available yet for this topic.</p>
  <% end %>
</section>

<%# === 3. Coming Up (meeting cards) === %>
<section class="topic-upcoming section topic-section">
  <h2 class="section-title">Coming Up</h2>
  <% if @upcoming.any? %>
    <div class="card-grid">
      <% @upcoming.each do |appearance| %>
        <%= link_to meeting_path(appearance.meeting), class: "card card-link card-link--upcoming" do %>
          <div class="card-body">
            <div class="text-sm text-secondary mb-1">
              <%= appearance.meeting.body_name %>
            </div>
            <div class="font-bold mb-1">
              <%= appearance.meeting.starts_at.strftime("%A, %B %-d at %-I:%M %p") %>
            </div>
            <% if appearance.meeting.location.present? %>
              <div class="text-sm text-secondary mb-2">
                <%= appearance.meeting.location %>
              </div>
            <% end %>
            <% if appearance.agenda_item %>
              <div class="mb-2">
                <%= appearance.agenda_item.title %>
              </div>
              <% if public_comment_meeting?(appearance.agenda_item) %>
                <span class="badge badge--info mb-2">Public comment period</span>
              <% end %>
            <% end %>
            <div class="mt-3">
              <span class="btn btn--secondary btn--sm">View meeting →</span>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
  <% else %>
    <p class="section-empty">No upcoming meetings scheduled for this topic.</p>
  <% end %>
</section>

<%# === 4. The Story (editorial) === %>
<section class="topic-story section topic-section">
  <h2 class="section-title">The Story</h2>
  <% story_text = briefing_current_state(@briefing) %>
  <% if story_text.present? %>
    <div class="card">
      <div class="card-body briefing-editorial-content">
        <%= sanitize(render_briefing_editorial(story_text)) %>
      </div>
    </div>
    <% concerns = briefing_process_concerns(@briefing) %>
    <% if concerns.any? %>
      <div class="topic-concerns-callout">
        <div class="concerns-label">Worth noting</div>
        <ul>
          <% concerns.each do |concern| %>
            <li><%= concern %></li>
          <% end %>
        </ul>
      </div>
    <% end %>
  <% else %>
    <p class="section-empty">This topic is being tracked but hasn't been fully analyzed yet. Check back after the next meeting.</p>
  <% end %>
</section>

<%# === 5. Key Decisions (votes) === %>
<section class="topic-decisions section topic-section">
  <h2 class="section-title">Key Decisions</h2>
  <% if @decisions.any? %>
    <% @decisions.each do |motion| %>
      <div class="topic-decision-item">
        <div class="flex justify-between items-center mb-1">
          <span class="font-bold"><%= motion.meeting.body_name %></span>
          <span class="text-sm text-secondary">
            <%= motion.meeting.starts_at.strftime("%B %-d, %Y") %>
          </span>
        </div>
        <div class="mb-2"><%= motion.description %></div>
        <div class="mb-2">
          <span class="badge <%= case motion.outcome&.downcase
            when 'passed', 'adopted', 'approved' then 'badge--success'
            when 'failed', 'defeated' then 'badge--danger'
            else 'badge--default'
          end %>">
            <%= motion_outcome_text(motion) %>
          </span>
        </div>
        <% if motion.votes.any? %>
          <div class="votes-label text-sm font-medium text-secondary">How they voted</div>
          <div class="votes-grid">
            <% motion.votes.each do |vote| %>
              <div class="vote-card vote-card--<%= vote.value %> text-sm">
                <span class="font-bold"><%= vote.member.name %></span>
                <span class="vote-value--<%= vote.value %>"><%= vote.value.titleize %></span>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    <% end %>
  <% else %>
    <p class="section-empty">No votes or motions recorded for this topic.</p>
  <% end %>
</section>

<%# === 6. Record (timeline) === %>
<section class="topic-record section topic-section">
  <h2 class="section-title">Record</h2>
  <% record_entries = briefing_factual_record(@briefing) %>
  <% if record_entries.any? %>
    <div class="topic-timeline">
      <% record_entries.each do |entry| %>
        <div class="topic-timeline-entry">
          <div class="topic-timeline-date">
            <%= format_record_date(entry["date"]) %>
          </div>
          <div class="topic-timeline-content">
            <%= entry["event"] %>
            <span class="topic-timeline-meeting"><%= entry["meeting"] %></span>
          </div>
        </div>
      <% end %>
    </div>
  <% else %>
    <p class="section-empty">No meeting activity recorded for this topic yet.</p>
  <% end %>
</section>

<%# === Footer === %>
<div class="mt-8">
  <%= link_to "← Back to Topics", topics_path, class: "btn btn--secondary" %>
</div>
```

**Step 2: Verify the page renders for a topic with full briefing data**

Run: `bin/rails runner "t = Topic.joins(:topic_briefing).where(status: 'approved').first; puts \"Visit: /topics/#{t.id}\" if t"`
Then visually verify (or rely on integration tests in Task 4).

**Step 3: Commit**

```
git add app/views/topics/show.html.erb
git commit -m "feat: rewrite topic show page with inverted pyramid layout and empty states"
```

---

### Task 4: Update integration tests for new layout

**Files:**
- Modify: `test/controllers/topics_controller_test.rb`

The existing tests check for CSS classes that have changed. Update them to match the new view structure.

**Step 1: Update failing tests**

Replace the topic show page tests (from `# --- Topic show page tests ---` onward, keeping all index tests unchanged). The key changes:

- `.topic-upcoming` is now always present (remove `count: 0` assertion)
- `.topic-briefing-headline` no longer exists (replaced by header badges)
- `.topic-briefing-editorial` → `.topic-story`
- `.topic-briefing-record` → `.topic-record`
- `.topic-empty-state` removed (each section has its own empty state)
- Sections are always present; empty state text replaces `count: 0` assertions

```ruby
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

test "show always renders all six sections" do
  get topic_url(@active_topic)
  assert_response :success
  assert_select ".topic-watch", 1
  assert_select ".topic-upcoming", 1
  assert_select ".topic-story", 1
  assert_select ".topic-decisions", 1
  assert_select ".topic-record", 1
end

test "show displays empty state for what to watch when no briefing" do
  get topic_url(@active_topic)
  assert_response :success
  assert_select ".topic-watch .section-empty", text: /No analysis available/
end

test "show displays empty state for coming up when no future meetings" do
  get topic_url(@active_topic)
  assert_response :success
  assert_select ".topic-upcoming .section-empty", text: /No upcoming meetings/
end

test "show displays empty state for story when no briefing" do
  get topic_url(@active_topic)
  assert_response :success
  assert_select ".topic-story .section-empty", text: /hasn't been fully analyzed/
end

test "show displays empty state for key decisions when no motions" do
  get topic_url(@active_topic)
  assert_response :success
  assert_select ".topic-decisions .section-empty", text: /No votes or motions/
end

test "show displays empty state for record when no generation data" do
  get topic_url(@active_topic)
  assert_response :success
  assert_select ".topic-record .section-empty", text: /No meeting activity/
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
  assert_select ".topic-watch-callout", text: /Watch for implementation timeline/
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
        "process_concerns" => ["Rushed through without public comment."],
        "pattern_observations" => []
      },
      "factual_record" => [],
      "resident_impact" => { "score" => 4, "rationale" => "Tax impact." }
    },
    generation_tier: "full"
  )

  get topic_url(@active_topic)
  assert_response :success
  assert_select ".topic-story .briefing-editorial-content", text: /voted 5-2/
  assert_select ".topic-concerns-callout li", text: /Rushed through/
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
  assert_select ".topic-story .briefing-editorial-content", text: /Fallback editorial/
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
  assert_select ".topic-timeline-meeting", text: /City Council, Sep 2/
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
  assert_select ".topic-upcoming a.card-link", minimum: 1
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
  assert_select ".topic-decisions .topic-decision-item", minimum: 1
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
  assert_select "a.btn", text: /Back to Topics/
end

test "show displays lifecycle badge" do
  get topic_url(@active_topic)
  assert_response :success
  assert_select ".badge", text: "Active"
end
```

**Step 2: Run the show-page tests**

Run: `bin/rails test test/controllers/topics_controller_test.rb -v`
Expected: All PASS

**Step 3: Commit**

```
git add test/controllers/topics_controller_test.rb
git commit -m "test: update topic show page tests for consistent layout"
```

---

### Task 5: Update section title CSS selectors

**Files:**
- Modify: `app/assets/stylesheets/application.css`

The existing CSS targets section titles by old class names. Update the selector list.

**Step 1: Update the selector**

Find this block (around line 1770):

```css
.topic-upcoming .section-title,
.topic-briefing-editorial .section-title,
.topic-briefing-record .section-title,
.topic-decisions .section-title {
```

Replace with:

```css
.topic-watch .section-title,
.topic-upcoming .section-title,
.topic-story .section-title,
.topic-decisions .section-title,
.topic-record .section-title {
```

**Step 2: Remove now-unused CSS rules**

Remove these blocks that are no longer referenced by the new view:
- `.briefing-headline-text` (headline moved to header area)
- `.briefing-editorial-content` rules can stay (still used by `.topic-story`)
- `.topic-record-list` and `.topic-record-list li` rules (replaced by `.topic-timeline`)
- `.topic-empty-state` if it existed as a separate class

**Step 3: Run full test suite**

Run: `bin/rails test -v`
Expected: All PASS

**Step 4: Commit**

```
git add app/assets/stylesheets/application.css
git commit -m "fix: update CSS selectors for renamed topic show sections"
```

---

### Task 6: Visual QA and dark mode verification

**Files:**
- Possibly modify: `app/assets/stylesheets/application.css` (dark mode overrides)

**Step 1: Check dark mode variables for new classes**

Search the CSS for the dark mode section (`@media (prefers-color-scheme: dark)` or `[data-theme="dark"]`) and verify the new classes (`.topic-watch-callout`, `.topic-timeline`, `.topic-concerns-callout`, `.section-empty`) inherit properly or need explicit dark mode overrides.

The warm accent colors (`--color-accent-warm-bg`, etc.) should already have dark mode values. Timeline uses `--color-border` and `--color-text-secondary` which should adapt. Verify by checking if the dark mode section overrides these variables.

**Step 2: Add dark mode overrides if needed**

If `.topic-watch-callout` background is too bright in dark mode, it should use the same dark mode warm bg token. Check if `--color-accent-warm-bg` is overridden in dark mode already.

**Step 3: Run full test suite one final time**

Run: `bin/rails test -v`
Expected: All PASS

**Step 4: Run lint**

Run: `bin/rubocop`
Expected: No new offenses

**Step 5: Commit any dark mode fixes**

```
git add app/assets/stylesheets/application.css
git commit -m "fix: dark mode adjustments for topic show page sections"
```

---

### Task 7: Clean up unused helper methods and old CSS

**Files:**
- Possibly modify: `app/helpers/topics_helper.rb`
- Possibly modify: `app/assets/stylesheets/application.css`

**Step 1: Check if old helpers are still used**

The old `render_briefing_record` method may still be referenced elsewhere (meeting show page uses `render_topic_summary_content`, not `render_briefing_record`). Check:

Run: `grep -r "render_briefing_record\|render_briefing_editorial" app/views/ --include="*.erb"`

If only referenced in `topics/show.html.erb` (which no longer calls `render_briefing_record` directly but still calls `render_briefing_editorial` for the story section fallback), keep both methods. The `render_briefing_editorial` method is still used in the view for formatting `current_state` text.

**Step 2: Remove truly unused code only**

Only remove code confirmed unused. Do NOT remove `render_briefing_editorial` — it's still used in the story section. Do NOT remove `render_inline_markdown` — used by what-to-watch callout.

**Step 3: Run tests**

Run: `bin/rails test -v`
Expected: All PASS

**Step 4: Commit if any cleanup was done**

```
git add app/helpers/topics_helper.rb app/assets/stylesheets/application.css
git commit -m "chore: remove unused topic show page helpers and CSS"
```
