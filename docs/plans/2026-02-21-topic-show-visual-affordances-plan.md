# Topic Show Page Visual Affordances — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add visual affordances to the topic show page so residents instantly know what's clickable, what to pay attention to, and how sections differ — without relying on hover states (50%+ mobile).

**Architecture:** CSS-and-view-only changes. Modify `show.html.erb` for markup changes (clickable cards, button CTAs, vote labels). Modify `application.css` to replace the topic show page CSS block with richer styles. No model, controller, or helper changes.

**Tech Stack:** ERB views, plain CSS with existing design tokens, existing `.btn` and `.badge` utility classes.

**Design doc:** `docs/plans/2026-02-21-topic-show-visual-affordances-design.md`

---

### Task 1: Update existing tests for new markup

The view changes will alter some DOM structure (cards become links, text links become buttons). Update tests to match.

**Files:**
- Modify: `test/controllers/topics_controller_test.rb:279-371`

**Step 1: Update the upcoming appearances test**

The Coming Up cards will be wrapped in `<a>` tags instead of `<div>` tags. The test at line 298 checks for `.topic-upcoming` which stays the same, so no change needed for that assertion. But add a new test that verifies cards are links.

Add this test after the "show loads upcoming appearances for future meetings" test (after line 299):

```ruby
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
```

Add this test to verify "View meeting" in recent activity is a button:

```ruby
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
```

Add this test to verify vote grid has a label:

```ruby
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
```

Add this test to verify back link is a button:

```ruby
test "show has back to topics button" do
  get topic_url(@active_topic)
  assert_response :success
  assert_select "a.btn", text: /Back to Topics/
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/topics_controller_test.rb -n "/show/"`
Expected: 4 new tests FAIL (missing `.card-link`, `.btn` on activity links, `.votes-label`, `.btn` on back link).

**Step 3: Commit**

```bash
git add test/controllers/topics_controller_test.rb
git commit -m "test: add visual affordance assertions for topic show page (#63)"
```

---

### Task 2: Update the view — Coming Up cards as links

**Files:**
- Modify: `app/views/topics/show.html.erb:15-43`

**Step 1: Replace Coming Up card markup**

Replace lines 15-43 of `app/views/topics/show.html.erb` (the card-grid and its contents) with:

```erb
    <div class="card-grid">
      <% @upcoming.each do |appearance| %>
        <%= link_to meeting_path(appearance.meeting), class: "card card-link card-link--upcoming" do %>
          <div class="card-body">
            <div class="text-sm text-secondary mb-1">
              <%= appearance.meeting.body_name %>
            </div>
            <div class="font-weight-bold mb-1">
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
            <div class="card-link-arrow">
              <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <polyline points="9 18 15 12 9 6"></polyline>
              </svg>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
```

Key changes:
- `<div class="card">` becomes `<%= link_to ..., class: "card card-link card-link--upcoming" %>`
- "View meeting details" text link removed (whole card is the link now)
- Arrow chevron SVG added at bottom-right
- `<div>` badge wrapper changed to `<span>` (can't nest div inside `<a>`)

**Step 2: Run tests**

Run: `bin/rails test test/controllers/topics_controller_test.rb -n "/show upcoming/"`
Expected: Both upcoming tests PASS.

**Step 3: Commit**

```bash
git add app/views/topics/show.html.erb
git commit -m "feat: make Coming Up cards fully clickable links (#63)"
```

---

### Task 3: Update the view — Recent Activity cards and button CTAs

**Files:**
- Modify: `app/views/topics/show.html.erb:66-93` (the recent activity section body)

**Step 1: Replace Recent Activity markup**

Replace the `@recent_activity.each` block (lines 66-93) with:

```erb
    <div class="topic-activity-list">
      <% @recent_activity.each do |appearance| %>
        <div class="topic-activity-item">
          <div class="flex justify-between items-center">
            <span class="font-weight-bold"><%= appearance.meeting.body_name %></span>
            <span class="text-sm text-secondary">
              <%= appearance.appeared_at.strftime("%B %-d, %Y") %>
            </span>
          </div>
          <% if appearance.agenda_item %>
            <% appearance.agenda_item.motions.each do |motion| %>
              <div class="mt-2">
                <span class="badge <%= case motion.outcome&.downcase
                  when 'passed', 'adopted', 'approved' then 'badge--success'
                  when 'failed', 'defeated' then 'badge--danger'
                  else 'badge--default'
                end %>">
                  <%= motion_outcome_text(motion) %>
                </span>
              </div>
            <% end %>
            <div class="mt-1 text-sm text-secondary"><%= appearance.agenda_item.title %></div>
          <% end %>
          <div class="mt-3">
            <%= link_to "View meeting \u2192", meeting_path(appearance.meeting),
                class: "btn btn--secondary btn--sm" %>
          </div>
        </div>
      <% end %>
    </div>
```

Key changes:
- Wrapped in `.topic-activity-list` container for gap spacing
- Motion outcome badge promoted ABOVE agenda item title (most important info first)
- Agenda item title demoted to secondary text
- "View meeting" is now `btn btn--secondary btn--sm` with arrow character
- `mt-3` spacing before button gives it visual separation

**Step 2: Run tests**

Run: `bin/rails test test/controllers/topics_controller_test.rb -n "/show recent/"`
Expected: PASS.

**Step 3: Commit**

```bash
git add app/views/topics/show.html.erb
git commit -m "feat: upgrade Recent Activity with card layout and button CTAs (#63)"
```

---

### Task 4: Update the view — Key Decisions vote label and vote styling

**Files:**
- Modify: `app/views/topics/show.html.erb:119-128` (the votes-grid block inside decisions)

**Step 1: Replace the votes block**

Replace the votes block (the `<% if motion.votes.any? %>` through its `<% end %>`) with:

```erb
        <% if motion.votes.any? %>
          <div class="votes-label text-sm font-weight-medium text-secondary">How they voted</div>
          <div class="votes-grid">
            <% motion.votes.each do |vote| %>
              <div class="vote-card vote-card--<%= vote.value %> text-sm">
                <span class="font-weight-bold"><%= vote.member.name %></span>
                <span class="vote-value--<%= vote.value %>"><%= vote.value.titleize %></span>
              </div>
            <% end %>
          </div>
        <% end %>
```

Key changes:
- Added `.votes-label` with "How they voted" plain-language header
- Added `vote-card--<vote_value>` class for left-border coloring
- Removed the colon between name and vote value (cleaner with the border doing the work)

**Step 2: Run tests**

Run: `bin/rails test test/controllers/topics_controller_test.rb -n "/show key decisions/"`
Expected: PASS.

**Step 3: Commit**

```bash
git add app/views/topics/show.html.erb
git commit -m "feat: add vote labels and colored vote cards in Key Decisions (#63)"
```

---

### Task 5: Update the view — Section borders and footer button

**Files:**
- Modify: `app/views/topics/show.html.erb`

**Step 1: Add `topic-section` class to all sections after Coming Up**

Add `topic-section` as an additional class to sections 3, 4, and 5 (What's Happening, Recent Activity, Key Decisions). This class will add a top border to visually separate sections.

For "What's Happening" (line 52), change:
```erb
  <section class="topic-summary section">
```
to:
```erb
  <section class="topic-summary section topic-section">
```

For "Recent Activity" (line 64), change:
```erb
  <section class="topic-recent-activity section">
```
to:
```erb
  <section class="topic-recent-activity section topic-section">
```

For "Key Decisions" (line 99), change:
```erb
  <section class="topic-decisions section">
```
to:
```erb
  <section class="topic-decisions section topic-section">
```

**Step 2: Replace the footer (lines 141-150)**

Replace:
```erb
<%# === Footer === %>
<div class="mt-6">
  <%= link_to topics_path, class: "back-link" do %>
    <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <line x1="19" y1="12" x2="5" y2="12"></line>
      <polyline points="12 19 5 12 12 5"></polyline>
    </svg>
    Back to Topics
  <% end %>
</div>
```

With:
```erb
<%# === Footer === %>
<div class="mt-8">
  <%= link_to "\u2190 Back to Topics", topics_path, class: "btn btn--secondary" %>
</div>
```

Key changes:
- Arrow is now a unicode character instead of inline SVG (simpler, same effect)
- `back-link` class replaced with `btn btn--secondary` (obvious button)

**Step 3: Run tests**

Run: `bin/rails test test/controllers/topics_controller_test.rb -n "/show/"`
Expected: All PASS.

**Step 4: Commit**

```bash
git add app/views/topics/show.html.erb
git commit -m "feat: add section borders and button footer (#63)"
```

---

### Task 6: CSS — replace topic show styles

**Files:**
- Modify: `app/assets/stylesheets/application.css:1744-1777`

**Step 1: Replace the `/* === Topic Show Page === */` CSS block**

Replace lines 1744-1777 (the current topic show page CSS block) with:

```css
/* === Topic Show Page === */

/* Section dividers — top border on sections after the first */
.topic-section {
  padding-top: var(--space-8);
  border-top: 1px solid var(--color-border);
}

/* Section titles — subtle bottom border for clear start markers */
.topic-upcoming .section-title,
.topic-summary .section-title,
.topic-recent-activity .section-title,
.topic-decisions .section-title {
  padding-bottom: var(--space-3);
  border-bottom: 2px solid var(--color-primary);
  display: inline-block;
  margin-bottom: var(--space-6);
}

/* Coming Up — clickable card links */
.card-link {
  display: block;
  text-decoration: none;
  color: inherit;
  position: relative;
  cursor: pointer;
}

.card-link:hover {
  text-decoration: none;
  color: inherit;
  box-shadow: var(--shadow-md);
}

.card-link--upcoming {
  border-left: 4px solid var(--color-accent-warm);
}

.card-link-arrow {
  display: flex;
  justify-content: flex-end;
  color: var(--color-text-muted);
  margin-top: var(--space-2);
}

.card-link:hover .card-link-arrow {
  color: var(--color-primary);
}

/* Recent Activity — discrete cards with gap spacing */
.topic-activity-list {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
}

.topic-activity-item {
  padding: var(--space-4);
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
}

/* Key Decisions — items with bottom border */
.topic-decision-item {
  padding: var(--space-4);
  border-bottom: 1px solid var(--color-border);
}

.topic-decision-item:last-child {
  border-bottom: none;
}

/* Vote grid enhancements */
.votes-label {
  margin-top: var(--space-3);
  margin-bottom: var(--space-2);
}

.vote-card--yes {
  border-left: 3px solid var(--color-success);
}

.vote-card--no {
  border-left: 3px solid var(--color-danger);
}

.vote-card--abstain {
  border-left: 3px solid var(--color-text-muted);
}

/* Summary content */
.topic-summary-list {
  margin: 0;
  padding-left: var(--space-5);
}

.topic-summary-list li {
  margin-bottom: var(--space-2);
  line-height: 1.6;
}

.topic-summary-list li:last-child {
  margin-bottom: 0;
}
```

**Step 2: Run full test suite**

Run: `bin/rails test test/controllers/topics_controller_test.rb`
Expected: All PASS.

**Step 3: Commit**

```bash
git add app/assets/stylesheets/application.css
git commit -m "style: add visual affordance styles for topic show page (#63)"
```

---

### Task 7: Final verification — full test suite and lint

**Step 1: Run full test suite**

Run: `bin/rails test`
Expected: All PASS.

**Step 2: Run linter**

Run: `bin/rubocop`
Expected: No new offenses.

**Step 3: Run CI**

Run: `bin/ci`
Expected: PASS.

**Step 4: Fix any issues**

Address failures if any. Commit fixes.

**Step 5: Final commit if needed**

```bash
git add -A
git commit -m "fix: address lint issues from visual affordance pass (#63)"
```

(Skip if nothing to fix.)
