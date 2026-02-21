# Homepage & Topics Index Affordances — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove government jargon, add visible tap affordances, fix information hierarchy, and add a meeting lifecycle badge + 3-hour buffer to the homepage and topics index pages.

**Architecture:** View/CSS changes to 6 templates, helper additions to `topics_helper.rb` and `meetings_helper.rb`, one controller constant + query adjustment in `home_controller.rb`. No model changes, no new routes.

**Tech Stack:** Rails ERB views, plain CSS with existing design tokens, Minitest integration tests.

**Design doc:** `docs/plans/2026-02-21-homepage-topics-index-affordances-design.md`

---

### Task 1: Meeting status badge helper + tests

**Files:**
- Modify: `app/helpers/meetings_helper.rb`
- Create: `test/helpers/meetings_helper_test.rb`

**Step 1: Write the failing tests**

Create `test/helpers/meetings_helper_test.rb`:

```ruby
require "test_helper"
require "ostruct"

class MeetingsHelperTest < ActionView::TestCase
  test "meeting_status_badge returns nil for upcoming meeting with no documents" do
    meeting = OpenStruct.new(document_status: :none, starts_at: 2.days.from_now, meeting_summaries: [])
    assert_nil meeting_status_badge(meeting)
  end

  test "meeting_status_badge returns agenda posted for upcoming meeting with agenda" do
    meeting = OpenStruct.new(document_status: :agenda, starts_at: 2.days.from_now, meeting_summaries: [])
    result = meeting_status_badge(meeting)
    assert_includes result, "Agenda posted"
  end

  test "meeting_status_badge returns documents available for upcoming meeting with packet" do
    meeting = OpenStruct.new(document_status: :packet, starts_at: 2.days.from_now, meeting_summaries: [])
    result = meeting_status_badge(meeting)
    assert_includes result, "Documents available"
  end

  test "meeting_status_badge returns awaiting minutes for past meeting without minutes" do
    meeting = OpenStruct.new(document_status: :none, starts_at: 2.days.ago, meeting_summaries: [])
    result = meeting_status_badge(meeting)
    assert_includes result, "Awaiting minutes"
  end

  test "meeting_status_badge returns awaiting minutes for past meeting with only packet" do
    meeting = OpenStruct.new(document_status: :packet, starts_at: 2.days.ago, meeting_summaries: [])
    result = meeting_status_badge(meeting)
    assert_includes result, "Awaiting minutes"
  end

  test "meeting_status_badge returns minutes available for past meeting with minutes" do
    meeting = OpenStruct.new(document_status: :minutes, starts_at: 2.days.ago, meeting_summaries: [])
    result = meeting_status_badge(meeting)
    assert_includes result, "Minutes available"
  end

  test "meeting_status_badge adds summary badge when summaries exist" do
    summary = OpenStruct.new
    meeting = OpenStruct.new(document_status: :minutes, starts_at: 2.days.ago, meeting_summaries: [summary])
    result = meeting_status_badge(meeting)
    assert_includes result, "Summary"
  end

  test "meeting_status_badge treats meeting within buffer as upcoming" do
    # A meeting that started 2 hours ago (within the 3-hour buffer) is still "upcoming"
    meeting = OpenStruct.new(document_status: :agenda, starts_at: 2.hours.ago, meeting_summaries: [])
    result = meeting_status_badge(meeting)
    assert_includes result, "Agenda posted"
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/helpers/meetings_helper_test.rb`
Expected: FAIL — undefined method `meeting_status_badge`.

**Step 3: Implement the helper**

Replace the contents of `app/helpers/meetings_helper.rb` with:

```ruby
module MeetingsHelper
  MEETING_BUFFER = 3.hours

  def meeting_status_badge(meeting)
    upcoming = meeting.starts_at > Time.current - MEETING_BUFFER
    badges = []

    if upcoming
      case meeting.document_status
      when :agenda
        badges << tag.span("Agenda posted", class: "badge badge--info")
      when :packet
        badges << tag.span("Documents available", class: "badge badge--info")
      end
    else
      if meeting.document_status == :minutes
        badges << tag.span("Minutes available", class: "badge badge--success")
      else
        badges << tag.span("Awaiting minutes", class: "badge badge--warning")
      end
    end

    if meeting.meeting_summaries.any?
      badges << tag.span("Summary", class: "badge badge--success")
    end

    return nil if badges.empty?
    safe_join(badges, " ")
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/helpers/meetings_helper_test.rb`
Expected: All PASS.

**Step 5: Commit**

```bash
git add app/helpers/meetings_helper.rb test/helpers/meetings_helper_test.rb
git commit -m "feat: add meeting_status_badge helper with resident-friendly labels

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 2: Rename signal badge labels in topics helper

**Files:**
- Modify: `app/helpers/topics_helper.rb:27-32`
- Modify: `test/helpers/topics_helper_test.rb`

**Step 1: Write the failing tests**

Add to the end of `test/helpers/topics_helper_test.rb` (before the final `end`):

```ruby
test "highlight_signal_label returns Delayed for deferral_signal" do
  assert_equal "Delayed", highlight_signal_label("deferral_signal")
end

test "highlight_signal_label returns No longer on agenda for disappearance_signal" do
  assert_equal "No longer on agenda", highlight_signal_label("disappearance_signal")
end

test "highlight_signal_label returns Moved to new committee for cross_body_progression" do
  assert_equal "Moved to new committee", highlight_signal_label("cross_body_progression")
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/helpers/topics_helper_test.rb -n "/highlight_signal_label/"`
Expected: FAIL — current labels are "Deferral Observed", "Disappeared", "Moved Bodies".

**Step 3: Update the HIGHLIGHT_LABELS constant**

In `app/helpers/topics_helper.rb`, replace lines 27-32:

```ruby
  HIGHLIGHT_LABELS = {
    "agenda_recurrence" => "Resurfaced",
    "deferral_signal" => "Deferral Observed",
    "cross_body_progression" => "Moved Bodies",
    "disappearance_signal" => "Disappeared"
  }.freeze
```

With:

```ruby
  HIGHLIGHT_LABELS = {
    "agenda_recurrence" => "Resurfaced",
    "deferral_signal" => "Delayed",
    "cross_body_progression" => "Moved to new committee",
    "disappearance_signal" => "No longer on agenda"
  }.freeze
```

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/helpers/topics_helper_test.rb`
Expected: All PASS.

**Step 5: Commit**

```bash
git add app/helpers/topics_helper.rb test/helpers/topics_helper_test.rb
git commit -m "fix: rename signal badges to resident-friendly labels

Deferral Observed → Delayed, Moved Bodies → Moved to new committee,
Disappeared → No longer on agenda.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 3: Topic card — add button, promote description, demote badge, dejargon

**Files:**
- Modify: `app/views/topics/_topic_card.html.erb`

**Step 1: Rewrite the topic card**

Replace the entire contents of `app/views/topics/_topic_card.html.erb` with:

```erb
<% signals = highlight_signals[topic.id] %>
<%= link_to topic_path(topic), class: ["card card--clickable", ("card--highlighted" if signals)].compact.join(" ") do %>
  <div class="card-header">
    <h3 class="card-title"><%= topic.name %></h3>
  </div>
  <div class="card-body">
    <% if topic.description.present? %>
      <p class="text-secondary mb-2"><%= truncate(topic.description, length: 80) %></p>
    <% end %>
    <div class="flex justify-between items-center text-secondary text-sm">
      <span>Discussed <%= topic.try(:agenda_item_count_cache) || topic.agenda_items.count %> times</span>
      <span class="flex items-center gap-2">
        <% if topic.last_activity_at %>
          Updated <%= time_ago_in_words(topic.last_activity_at) %> ago
        <% end %>
        <%= topic_lifecycle_badge(topic.lifecycle_status) if topic.lifecycle_status %>
      </span>
    </div>
    <% if signals %>
      <div class="card-signals">
        <% signals.each do |label| %>
          <span class="badge badge--outline"><%= label %></span>
        <% end %>
      </div>
    <% end %>
    <div class="mt-3">
      <span class="btn btn--secondary btn--sm">View topic →</span>
    </div>
  </div>
<% end %>
```

Key changes:
- Removed `style="text-decoration: none; color: inherit;"` inline style (handled by CSS)
- Lifecycle badge moved from card header to metadata row bottom-right
- Description promoted from `text-sm text-secondary` to `text-secondary` (normal size)
- "N agenda items" → "Discussed N times"
- Added "View topic →" button at bottom

**Step 2: Run tests**

Run: `bin/rails test test/controllers/topics_controller_test.rb -n "/index/"`
Expected: All PASS (tests check for `.card` and topic names, not for specific inner markup).

**Step 3: Commit**

```bash
git add app/views/topics/_topic_card.html.erb
git commit -m "feat: improve topic cards — button CTA, promoted description, dejargon

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 4: Topics index page — copy and archive link

**Files:**
- Modify: `app/views/topics/index.html.erb`

**Step 1: Update page copy and archive link**

In `app/views/topics/index.html.erb`:

Replace line 5:
```erb
  <p class="page-subtitle">Topics currently under discussion in Two Rivers</p>
```
With:
```erb
  <p class="page-subtitle">What Two Rivers city government is working on</p>
```

Replace line 17:
```erb
        <p class="text-secondary mb-0">High-impact topics with recent activity.</p>
```
With:
```erb
        <p class="text-secondary mb-0">The biggest issues right now</p>
```

Replace the archive link block (lines 57-62):
```erb
<div class="text-center mt-8 mb-8">
  <p class="text-secondary text-sm">
    Looking for older or resolved topics?
    <%= link_to "Explore the full archive", topics_explore_path %>.
  </p>
</div>
```
With:
```erb
<div class="text-center mt-8 mb-8">
  <p class="text-secondary mb-3">Looking for older or resolved topics?</p>
  <%= link_to "Explore the full archive →", topics_explore_path, class: "btn btn--secondary" %>
</div>
```

**Step 2: Run tests**

Run: `bin/rails test test/controllers/topics_controller_test.rb -n "/index/"`
Expected: All PASS.

**Step 3: Commit**

```bash
git add app/views/topics/index.html.erb
git commit -m "feat: improve topics index copy and promote archive link

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 5: Topics index CSS — card--clickable text reset

**Files:**
- Modify: `app/assets/stylesheets/application.css:520-522`

**Step 1: Add text-decoration and color reset to `.card--clickable`**

Replace the `.card--clickable` block (lines 520-522):

```css
.card--clickable {
  cursor: pointer;
}
```

With:

```css
.card--clickable {
  cursor: pointer;
  text-decoration: none;
  color: inherit;
}

.card--clickable:hover {
  text-decoration: none;
  color: inherit;
}
```

Note: there's already a `.card--clickable:hover` rule at line 524. Merge the new properties into it. The full replacement for lines 520-526 is:

```css
.card--clickable {
  cursor: pointer;
  text-decoration: none;
  color: inherit;
}

.card--clickable:hover {
  border-color: var(--color-primary);
  text-decoration: none;
  color: inherit;
}
```

**Step 2: Run tests**

Run: `bin/rails test test/controllers/topics_controller_test.rb`
Expected: All PASS.

**Step 3: Commit**

```bash
git add app/assets/stylesheets/application.css
git commit -m "style: move card--clickable link reset from inline to CSS

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 6: Homepage — topic headline items as visible links

**Files:**
- Modify: `app/views/home/_topic_headline_item.html.erb`
- Modify: `app/assets/stylesheets/application.css` (topic headline styles)

**Step 1: Update the headline item partial**

Replace the entire contents of `app/views/home/_topic_headline_item.html.erb` with:

```erb
<%= link_to topic_path(topic), class: "topic-headline-item" do %>
  <span class="topic-headline-item__name"><%= topic.name %> →</span>
  <% headline = @headlines[topic.id] %>
  <% if headline %>
    <p class="topic-headline-item__headline"><%= headline %></p>
  <% elsif topic.description.present? %>
    <p class="topic-headline-item__headline"><%= truncate(topic.description, length: 120) %></p>
  <% end %>
<% end %>
```

Key change: added ` →` after the topic name.

**Step 2: Update the topic headline CSS**

In `app/assets/stylesheets/application.css`, find the `.topic-headline-item__name` rule (around line 1732). Replace:

```css
.topic-headline-item__name {
  font-weight: 600;
  display: block;
}
```

With:

```css
.topic-headline-item__name {
  font-weight: 600;
  display: block;
  color: var(--color-accent);
  text-decoration: underline;
  text-decoration-thickness: 1px;
  text-underline-offset: 2px;
}
```

**Step 3: Run tests**

Run: `bin/rails test test/controllers/home_controller_test.rb`
Expected: All PASS.

**Step 4: Commit**

```bash
git add app/views/home/_topic_headline_item.html.erb app/assets/stylesheets/application.css
git commit -m "feat: style homepage topic headlines as visible links with arrows

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 7: Homepage — card footers, empty state

**Files:**
- Modify: `app/views/home/index.html.erb`

**Step 1: Upgrade card footer links to buttons**

In `app/views/home/index.html.erb`, replace line 26:
```erb
        <%= link_to "All topics &#8594;".html_safe, topics_path, class: "text-sm" %>
```
With:
```erb
        <%= link_to "All topics →", topics_path, class: "btn btn--secondary btn--sm" %>
```

Replace line 42 (same change in the What Happened card):
```erb
        <%= link_to "All topics &#8594;".html_safe, topics_path, class: "text-sm" %>
```
With:
```erb
        <%= link_to "All topics →", topics_path, class: "btn btn--secondary btn--sm" %>
```

**Step 2: Add empty state when no topic cards**

After the card-grid closing `</div>` (line 46) and before the `<% if @coming_up.any? || @what_happened.any? %>` conditional (line 48), add:

```erb
<% unless @coming_up.any? || @what_happened.any? %>
  <div class="empty-state mb-8">
    <p class="mb-0">No hot topics right now. Check the meetings below to see what's scheduled.</p>
  </div>
<% end %>
```

**Step 3: Run tests**

Run: `bin/rails test test/controllers/home_controller_test.rb`
Expected: All PASS.

**Step 4: Commit**

```bash
git add app/views/home/index.html.erb
git commit -m "feat: upgrade card footer buttons and add topic empty state

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 8: Meeting table — dejargon headers, single status badge, column simplification

**Files:**
- Modify: `app/views/home/_meeting_week_group.html.erb`
- Modify: `app/views/home/_meeting_row.html.erb`

**Step 1: Update the table headers**

Replace the contents of `app/views/home/_meeting_week_group.html.erb` with:

```erb
<div class="week-group">
  <h3 class="week-group__label"><%= group[:label] %></h3>

  <div class="table-wrapper">
    <table>
      <thead>
        <tr>
          <th>Date</th>
          <th>Committee</th>
          <th class="meeting-topics-col">Topics</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        <% group[:meetings].each do |meeting| %>
          <%= render "meeting_row", meeting: meeting %>
        <% end %>
      </tbody>
    </table>
  </div>
</div>
```

Key changes: "Body" → "Committee", removed "Info" column, added `.meeting-topics-col` class for mobile hiding.

**Step 2: Update the meeting row**

Replace the entire contents of `app/views/home/_meeting_row.html.erb` with:

```erb
<tr>
  <td>
    <strong><%= meeting.starts_at&.strftime("%b %-d") %></strong>
    <div class="text-muted text-sm"><%= meeting.starts_at&.strftime("%l:%M %p") %></div>
    <% if (status_html = meeting_status_badge(meeting)) %>
      <div class="mt-1"><%= status_html %></div>
    <% end %>
  </td>
  <td><%= meeting.body_name %></td>
  <td class="meeting-topics-col">
    <% topics = meeting.agenda_items.flat_map(&:topics).uniq %>
    <% if topics.any? %>
      <div class="flex flex-wrap gap-1">
        <% topics.first(3).each do |topic| %>
          <%= link_to topic.name, topic_path(topic), class: "tag tag--topic" %>
        <% end %>
        <% if topics.size > 3 %>
          <span class="text-muted text-xs">+<%= topics.size - 3 %> more</span>
        <% end %>
      </div>
    <% else %>
      <span class="text-muted text-sm">No topics yet</span>
    <% end %>
  </td>
  <td class="text-right">
    <%= link_to "View", meeting_path(meeting), class: "btn btn--secondary btn--sm" %>
  </td>
</tr>
```

Key changes:
- Removed the entire "Info" `<td>` with its multi-badge content
- Added `meeting_status_badge(meeting)` below the date
- Added `.meeting-topics-col` class to topics `<td>` for mobile hiding

**Step 3: Run tests**

Run: `bin/rails test test/controllers/home_controller_test.rb`
Expected: All PASS.

**Step 4: Commit**

```bash
git add app/views/home/_meeting_week_group.html.erb app/views/home/_meeting_row.html.erb
git commit -m "feat: simplify meeting table — single status badge, dejargoned headers

Body → Committee, removed Info column, added lifecycle status badge.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 9: CSS — mobile column hiding

**Files:**
- Modify: `app/assets/stylesheets/application.css`

**Step 1: Add mobile responsive rule**

Add the following CSS at the end of the file (after the topic show page block):

```css
/* === Meeting Table — Mobile === */

@media (max-width: 768px) {
  .meeting-topics-col {
    display: none;
  }
}
```

**Step 2: Run tests**

Run: `bin/rails test test/controllers/home_controller_test.rb`
Expected: All PASS.

**Step 3: Commit**

```bash
git add app/assets/stylesheets/application.css
git commit -m "style: hide meeting topics column on mobile

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 10: Controller — 3-hour meeting buffer

**Files:**
- Modify: `app/controllers/home_controller.rb`
- Modify: `test/controllers/home_controller_test.rb`

**Step 1: Write the failing test**

Add to `test/controllers/home_controller_test.rb` (before the final `end`):

```ruby
test "meeting within 3-hour buffer stays in upcoming section" do
  # Create a meeting that started 2 hours ago (within 3-hour buffer)
  recent_meeting = Meeting.create!(
    body_name: "Zoning Board",
    meeting_type: "Regular",
    starts_at: 2.hours.ago,
    status: "upcoming",
    detail_page_url: "http://example.com/recent-buffer"
  )

  get root_url
  assert_response :success

  # The meeting should appear in upcoming, not recently completed
  # Check that it's in the upcoming section by looking at the section structure
  assert_select "section" do |sections|
    upcoming_section = sections.find { |s| s.text.include?("Upcoming Meetings") }
    assert upcoming_section.text.include?("Zoning Board"), "Expected Zoning Board in upcoming section"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/home_controller_test.rb -n "/buffer/"`
Expected: FAIL — meeting shows in recently completed because `starts_at` is in the past.

**Step 3: Add the buffer constant and update queries**

In `app/controllers/home_controller.rb`, add the constant after line 7:

```ruby
  MEETING_BUFFER = 3.hours
```

Replace line 74 in `upcoming_meetings_grouped`:
```ruby
    meetings = Meeting.in_window(Time.current, UPCOMING_WINDOW.from_now)
```
With:
```ruby
    meetings = Meeting.in_window(Time.current - MEETING_BUFFER, UPCOMING_WINDOW.from_now)
```

Replace line 83 in `recent_meetings_grouped`:
```ruby
    meetings = Meeting.in_window(RECENT_WINDOW.ago, Time.current)
```
With:
```ruby
    meetings = Meeting.in_window(RECENT_WINDOW.ago, Time.current - MEETING_BUFFER)
```

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/controllers/home_controller_test.rb`
Expected: All PASS.

**Step 5: Commit**

```bash
git add app/controllers/home_controller.rb test/controllers/home_controller_test.rb
git commit -m "feat: add 3-hour buffer before meetings move to recently completed

A 6pm meeting stays in Upcoming until ~9pm.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 11: Final verification — full test suite, lint, CI

**Step 1: Run full test suite**

Run: `bin/rails test`
Expected: All PASS (except the pre-existing admin_topic_flows_test failure).

**Step 2: Run linter**

Run: `bin/rubocop`
Expected: No new offenses.

**Step 3: Run CI**

Run: `bin/ci`
Expected: PASS.

**Step 4: Fix any issues**

Address failures if any.

**Step 5: Commit fixes if needed**

```bash
git add -A
git commit -m "fix: address lint issues from homepage/topics affordance pass

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

(Skip if nothing to fix.)
