# Topic Show Page Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the topic show page's raw timeline dump with a resident-friendly layout: header, coming up, summary, recent activity, and key decisions.

**Architecture:** Controller-and-view-only change. Replace `@appearances`/`@status_events`/`@timeline_items` in `TopicsController#show` with four focused ivars (`@upcoming`, `@summary`, `@recent_activity`, `@decisions`). Rewrite `show.html.erb` into five sections using existing card/section CSS classes. Add a helper for rendering motion outcomes as compact text. Add a small CSS block for new topic-show-specific styles.

**Tech Stack:** Rails controller, ERB views, Minitest integration tests, existing CSS design system (cards, badges, sections).

**Design doc:** `docs/plans/2026-02-21-topic-show-redesign-design.md`

---

### Task 1: Controller — replace show action data loading

**Files:**
- Modify: `app/controllers/topics_controller.rb:38-55`
- Test: `test/controllers/topics_controller_test.rb`

**Step 1: Write the failing tests**

Add these tests at the end of `test/controllers/topics_controller_test.rb` (before the final `end`):

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
    summary_type: "topic_digest", generation_data: {}
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
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/topics_controller_test.rb -n "/show/"`
Expected: Multiple failures — missing CSS classes in the current view.

**Step 3: Rewrite the controller show action**

Replace lines 38–55 of `app/controllers/topics_controller.rb` with:

```ruby
def show
  @topic = Topic.publicly_visible.find(params[:id])

  # Upcoming: future meetings where this topic is on the agenda
  @upcoming = @topic.topic_appearances
                    .includes(meeting: [], agenda_item: [])
                    .joins(:meeting)
                    .where("meetings.starts_at > ?", Time.current)
                    .order("meetings.starts_at ASC")

  # Most recent topic summary
  @summary = @topic.topic_summaries.order(created_at: :desc).first

  # Recent activity: last 3 past appearances with an agenda item
  @recent_activity = @topic.topic_appearances
                          .includes(agenda_item: { motions: :votes }, meeting: [])
                          .joins(:meeting)
                          .where("meetings.starts_at <= ?", Time.current)
                          .where.not(agenda_item_id: nil)
                          .order(appeared_at: :desc)
                          .limit(3)

  # Key decisions: all motions linked to this topic's agenda items
  @decisions = Motion.joins(agenda_item: :agenda_item_topics)
                     .where(agenda_item_topics: { topic_id: @topic.id })
                     .includes(:meeting, :votes => :member)
                     .order("meetings.starts_at DESC")
rescue ActiveRecord::RecordNotFound
  redirect_to topics_path, alert: "Topic not found."
end
```

**Step 4: Run tests to verify controller loads correctly**

Run: `bin/rails test test/controllers/topics_controller_test.rb -n "/show/"`
Expected: Tests that check for CSS classes will still fail (view not updated yet), but no 500 errors from controller.

**Step 5: Commit**

```bash
git add app/controllers/topics_controller.rb test/controllers/topics_controller_test.rb
git commit -m "refactor: replace topic show timeline loading with section-based ivars"
```

---

### Task 2: Helper — add motion outcome formatter

**Files:**
- Modify: `app/helpers/topics_helper.rb`
- Test: `test/helpers/topics_helper_test.rb`

**Step 1: Write the failing test**

Create `test/helpers/topics_helper_test.rb` if it doesn't exist, or add to it:

```ruby
require "test_helper"

class TopicsHelperTest < ActionView::TestCase
  test "motion_outcome_text returns outcome with vote count" do
    motion = Minitest::Mock.new
    votes = [
      OpenStruct.new(value: "yes"),
      OpenStruct.new(value: "yes"),
      OpenStruct.new(value: "yes"),
      OpenStruct.new(value: "no"),
      OpenStruct.new(value: "no")
    ]
    motion.expect(:outcome, "Passed")
    motion.expect(:votes, votes)

    assert_equal "Passed 3-2", motion_outcome_text(motion)
  end

  test "motion_outcome_text returns just outcome when no votes" do
    motion = Minitest::Mock.new
    motion.expect(:outcome, "Adopted")
    motion.expect(:votes, [])

    assert_equal "Adopted", motion_outcome_text(motion)
  end

  test "motion_outcome_text handles unanimous votes" do
    motion = Minitest::Mock.new
    votes = [
      OpenStruct.new(value: "yes"),
      OpenStruct.new(value: "yes"),
      OpenStruct.new(value: "yes")
    ]
    motion.expect(:outcome, "Approved")
    motion.expect(:votes, votes)

    assert_equal "Approved 3-0", motion_outcome_text(motion)
  end

  test "public_comment_meeting? detects public hearing in title" do
    item = OpenStruct.new(title: "PUBLIC HEARING - Rezoning Request")
    assert public_comment_meeting?(item)
  end

  test "public_comment_meeting? detects public comment in title" do
    item = OpenStruct.new(title: "Public Comment Period")
    assert public_comment_meeting?(item)
  end

  test "public_comment_meeting? returns false for normal items" do
    item = OpenStruct.new(title: "Regular Business Item")
    refute public_comment_meeting?(item)
  end

  test "public_comment_meeting? returns false for nil title" do
    item = OpenStruct.new(title: nil)
    refute public_comment_meeting?(item)
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/helpers/topics_helper_test.rb`
Expected: FAIL — undefined methods `motion_outcome_text` and `public_comment_meeting?`.

**Step 3: Add helper methods**

Add to the end of `app/helpers/topics_helper.rb` (before the final `end`):

```ruby
def motion_outcome_text(motion)
  return motion.outcome if motion.votes.empty?

  yes_count = motion.votes.count { |v| v.value == "yes" }
  no_count = motion.votes.count { |v| v.value == "no" }
  "#{motion.outcome} #{yes_count}-#{no_count}"
end

def public_comment_meeting?(agenda_item)
  return false if agenda_item.title.blank?

  agenda_item.title.match?(/public (hearing|comment)/i)
end
```

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/helpers/topics_helper_test.rb`
Expected: All PASS.

**Step 5: Commit**

```bash
git add app/helpers/topics_helper.rb test/helpers/topics_helper_test.rb
git commit -m "feat: add motion_outcome_text and public_comment_meeting? helpers"
```

---

### Task 3: View — rewrite topic show page

**Files:**
- Modify: `app/views/topics/show.html.erb`

**Step 1: Rewrite the view**

Replace the entire contents of `app/views/topics/show.html.erb` with:

```erb
<% content_for(:title) { "#{@topic.name} - Topics - Two Rivers Reporter" } %>

<%# === 1. Header === %>
<div class="page-header">
  <h1 class="page-title"><%= @topic.name %></h1>
  <% if @topic.description.present? %>
    <p class="page-subtitle"><%= @topic.description %></p>
  <% end %>
</div>

<%# === 2. Coming Up === %>
<% if @upcoming.any? %>
  <section class="topic-upcoming section">
    <h2 class="section-title">Coming Up</h2>
    <div class="card-grid">
      <% @upcoming.each do |appearance| %>
        <div class="card">
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
                <div class="badge badge--info mb-2">Public comment period</div>
              <% end %>
            <% end %>
            <%= link_to "View meeting details", meeting_path(appearance.meeting),
                class: "text-sm" %>
          </div>
        </div>
      <% end %>
    </div>
    <p class="text-sm text-secondary mt-3">
      You can always contact your council members about this topic.
    </p>
  </section>
<% end %>

<%# === 3. What's Happening === %>
<% if @summary %>
  <section class="topic-summary section">
    <h2 class="section-title">What's Happening</h2>
    <div class="card">
      <div class="card-body topic-summary-content">
        <%= sanitize(render_topic_summary_content(@summary.content)) %>
      </div>
    </div>
  </section>
<% end %>

<%# === 4. Recent Activity === %>
<% if @recent_activity.any? %>
  <section class="topic-recent-activity section">
    <h2 class="section-title">Recent Activity</h2>
    <% @recent_activity.each do |appearance| %>
      <div class="topic-activity-item">
        <div class="flex justify-between items-center">
          <span class="font-weight-bold"><%= appearance.meeting.body_name %></span>
          <span class="text-sm text-secondary">
            <%= appearance.appeared_at.strftime("%B %-d, %Y") %>
          </span>
        </div>
        <% if appearance.agenda_item %>
          <div class="mt-1"><%= appearance.agenda_item.title %></div>
          <% appearance.agenda_item.motions.each do |motion| %>
            <div class="mt-1">
              <span class="badge <%= case motion.outcome&.downcase
                when 'passed', 'adopted', 'approved' then 'badge--success'
                when 'failed', 'defeated' then 'badge--danger'
                else 'badge--default'
              end %>">
                <%= motion_outcome_text(motion) %>
              </span>
            </div>
          <% end %>
        <% end %>
        <div class="mt-2">
          <%= link_to "View meeting", meeting_path(appearance.meeting),
              class: "text-sm" %>
        </div>
      </div>
    <% end %>
  </section>
<% end %>

<%# === 5. Key Decisions === %>
<% if @decisions.any? %>
  <section class="topic-decisions section">
    <h2 class="section-title">Key Decisions</h2>
    <% @decisions.each do |motion| %>
      <div class="topic-decision-item">
        <div class="flex justify-between items-center mb-1">
          <span class="font-weight-bold"><%= motion.meeting.body_name %></span>
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
          <div class="votes-grid">
            <% motion.votes.each do |vote| %>
              <div class="vote-card text-sm">
                <span class="font-weight-bold"><%= vote.member.name %></span>:
                <span class="vote-value--<%= vote.value %>"><%= vote.value.titleize %></span>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    <% end %>
  </section>
<% end %>

<%# === Empty state === %>
<% if @upcoming.empty? && @summary.nil? && @recent_activity.empty? && @decisions.empty? %>
  <div class="topic-empty-state empty-state">
    <p class="mb-0">No meeting activity recorded for this topic yet.</p>
  </div>
<% end %>

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

**Step 2: Add the summary content rendering helper**

This helper strips the internal markdown section headers (## Topic Name, **Factual Record**, **Institutional Framing**, **Civic Sentiment**) and renders the remaining content as simple HTML.

Add to `app/helpers/topics_helper.rb` (before the final `end`):

```ruby
# Renders TopicSummary markdown content as resident-friendly HTML.
# Strips internal section headers (## heading, **Factual Record**, etc.)
# and renders remaining bullet points as a simple list.
def render_topic_summary_content(markdown_content)
  return "" if markdown_content.blank?

  lines = markdown_content.lines.map(&:chomp)

  # Remove heading lines and internal section headers
  filtered = lines.reject do |line|
    line.match?(/\A##\s/) ||
      line.match?(/\A\*\*(Factual Record|Institutional Framing|Civic Sentiment|Continuity|Resident-reported)/i) ||
      line.strip.empty?
  end

  # Convert markdown bullets to HTML list items
  items = filtered.map do |line|
    text = line.sub(/\A\s*[-*]\s*/, "").strip
    next if text.empty?
    content_tag(:li, text)
  end.compact

  return "" if items.empty?
  content_tag(:ul, items.join.html_safe, class: "topic-summary-list")
end
```

**Step 3: Run the show tests to verify the view renders correctly**

Run: `bin/rails test test/controllers/topics_controller_test.rb -n "/show/"`
Expected: All show tests PASS.

**Step 4: Commit**

```bash
git add app/views/topics/show.html.erb app/helpers/topics_helper.rb
git commit -m "feat: rewrite topic show page with resident-friendly sections"
```

---

### Task 4: Add helper test for render_topic_summary_content

**Files:**
- Modify: `test/helpers/topics_helper_test.rb`

**Step 1: Add the tests**

Append these tests to the test class in `test/helpers/topics_helper_test.rb`:

```ruby
test "render_topic_summary_content strips section headers and renders list" do
  content = <<~MD
    ## Street Repair

    **Factual Record**
    - City approved $50k funding [Packet Page 5].
    - Work begins in spring.

    **Institutional Framing**
    - Presented as routine maintenance.

    **Civic Sentiment**
    - Residents expressed concern about delays.
  MD

  result = render_topic_summary_content(content)
  assert_includes result, "<li>"
  assert_includes result, "City approved $50k funding [Packet Page 5]."
  assert_includes result, "Residents expressed concern about delays."
  refute_includes result, "Factual Record"
  refute_includes result, "Institutional Framing"
  refute_includes result, "Street Repair"
end

test "render_topic_summary_content returns empty string for blank content" do
  assert_equal "", render_topic_summary_content(nil)
  assert_equal "", render_topic_summary_content("")
end

test "render_topic_summary_content handles content with only headers" do
  content = "## Topic Name\n\n**Factual Record**\n"
  assert_equal "", render_topic_summary_content(content)
end
```

**Step 2: Run tests to verify they pass**

Run: `bin/rails test test/helpers/topics_helper_test.rb`
Expected: All PASS.

**Step 3: Commit**

```bash
git add test/helpers/topics_helper_test.rb
git commit -m "test: add render_topic_summary_content helper tests"
```

---

### Task 5: CSS — add topic show page styles

**Files:**
- Modify: `app/assets/stylesheets/application.css`

**Step 1: Add styles**

Append the following CSS block to the end of `app/assets/stylesheets/application.css`:

```css
/* === Topic Show Page === */

.topic-activity-item {
  padding: var(--space-4);
  border-bottom: 1px solid var(--color-border);
}

.topic-activity-item:last-child {
  border-bottom: none;
}

.topic-decision-item {
  padding: var(--space-4);
  border-bottom: 1px solid var(--color-border);
}

.topic-decision-item:last-child {
  border-bottom: none;
}

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

**Step 2: Run the full test suite to verify nothing broke**

Run: `bin/rails test test/controllers/topics_controller_test.rb`
Expected: All PASS.

**Step 3: Commit**

```bash
git add app/assets/stylesheets/application.css
git commit -m "style: add topic show page section styles"
```

---

### Task 6: Run full test suite and lint

**Step 1: Run all tests**

Run: `bin/rails test`
Expected: All PASS.

**Step 2: Run linter**

Run: `bin/rubocop`
Expected: No new offenses.

**Step 3: Fix any issues found**

Address any test failures or lint issues from steps 1-2.

**Step 4: Run CI check**

Run: `bin/ci`
Expected: PASS.

**Step 5: Commit any fixes**

```bash
git add -A
git commit -m "fix: address lint and test issues from topic show redesign"
```

(Skip this commit if nothing to fix.)

---

### Task 7: Clean up unused timeline CSS (optional)

**Files:**
- Modify: `app/assets/stylesheets/application.css`

The old timeline CSS classes (`.timeline`, `.timeline-item`, `.timeline-group`, `.timeline-date-marker`, `.timeline-item--appearance`, `.timeline-item--status-event`) are no longer used by the topic show page. Check if any other views reference them.

**Step 1: Search for timeline class usage in views**

Run: `grep -r "timeline" app/views/`

If no results, remove the timeline CSS block from `application.css` (the block starting with `.timeline {` through `.timeline-item--status-event`).

**Step 2: Commit**

```bash
git add app/assets/stylesheets/application.css
git commit -m "chore: remove unused timeline CSS classes"
```

(Skip if timeline classes are used elsewhere.)
