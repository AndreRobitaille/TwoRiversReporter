# Topic Navigation: Standardize Click-Through Behavior

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Give residents a natural path from meeting pages to topic history, and filter homepage topic pills by importance.

**Architecture:** Two changes to existing server-rendered views. Change 1 adds a new section to meetings/show with controller data prep. Change 2 modifies the homepage meeting row partial's topic filtering logic. Both are view-layer changes with minimal controller work.

**Tech Stack:** Rails ERB views, existing CSS design system, Minitest

---

## Design Reference

See `docs/plans/2026-02-28-topic-navigation-design.md` (this file, top section) for full design rationale.

### Change 1: "Issues in This Meeting" section (meeting show page)

**Placement:** After Documents section, before "Back to Meetings" link.

Two subsections:
- **Ongoing**: Topics with 2+ `TopicAppearance` records. Intro: "These issues have come up across multiple meetings. Click any for the full picture."
- **New This Meeting**: Topics with exactly 1 appearance. Intro: "These issues came up for the first time."

Reuses `topics/_topic_card` partial. Skip empty subsections. Skip entire section if no approved topics.

### Change 2: Meeting row topic pills (homepage)

Show all approved topics with `resident_impact_score >= 2`. No cap, no overflow, no "No topics yet" text.

---

## Task 1: Controller — Load and partition meeting topics

**Files:**
- Modify: `app/controllers/meetings_controller.rb:12-14`
- Test: `test/controllers/meetings_controller_test.rb` (create new)

**Step 1: Write the failing test**

Create `test/controllers/meetings_controller_test.rb`:

```ruby
require "test_helper"

class MeetingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @meeting = Meeting.create!(
      body_name: "City Council",
      meeting_type: "Regular",
      starts_at: 3.days.ago,
      status: "minutes_posted",
      detail_page_url: "http://example.com/meeting-nav-test"
    )

    # Ongoing topic (2+ appearances)
    @ongoing_topic = Topic.create!(
      name: "downtown tif district",
      status: "approved",
      lifecycle_status: "active",
      last_activity_at: 2.days.ago
    )
    item1 = AgendaItem.create!(meeting: @meeting, title: "TIF Discussion")
    AgendaItemTopic.create!(topic: @ongoing_topic, agenda_item: item1)
    TopicAppearance.create!(
      topic: @ongoing_topic, meeting: @meeting, agenda_item: item1,
      appeared_at: @meeting.starts_at, body_name: "City Council",
      evidence_type: "agenda_item"
    )
    # Second appearance on another meeting
    other_meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 30.days.ago, status: "minutes_posted",
      detail_page_url: "http://example.com/old-meeting-nav"
    )
    TopicAppearance.create!(
      topic: @ongoing_topic, meeting: other_meeting,
      appeared_at: other_meeting.starts_at, body_name: "City Council",
      evidence_type: "agenda_item"
    )

    # New topic (1 appearance)
    @new_topic = Topic.create!(
      name: "new sidewalk project",
      status: "approved",
      lifecycle_status: "active",
      last_activity_at: 2.days.ago
    )
    item2 = AgendaItem.create!(meeting: @meeting, title: "Sidewalk Plan")
    AgendaItemTopic.create!(topic: @new_topic, agenda_item: item2)
    TopicAppearance.create!(
      topic: @new_topic, meeting: @meeting, agenda_item: item2,
      appeared_at: @meeting.starts_at, body_name: "City Council",
      evidence_type: "agenda_item"
    )

    # Blocked topic (should be excluded)
    @blocked_topic = Topic.create!(
      name: "blocked issue",
      status: "blocked",
      lifecycle_status: "active"
    )
    item3 = AgendaItem.create!(meeting: @meeting, title: "Blocked Item")
    AgendaItemTopic.create!(topic: @blocked_topic, agenda_item: item3)
  end

  test "show assigns ongoing and new topics" do
    get meeting_url(@meeting)
    assert_response :success

    assert assigns(:ongoing_topics).include?(@ongoing_topic)
    assert assigns(:new_topics).include?(@new_topic)
  end

  test "show excludes non-approved topics" do
    get meeting_url(@meeting)
    assert_response :success

    all_topics = assigns(:ongoing_topics) + assigns(:new_topics)
    refute all_topics.include?(@blocked_topic)
  end

  test "show renders issues section with ongoing and new subsections" do
    get meeting_url(@meeting)
    assert_response :success

    assert_select "h2", text: "Issues in This Meeting"
    assert_select "h3", text: "Ongoing"
    assert_select "h3", text: "New This Meeting"
  end

  test "show hides issues section when no approved topics" do
    AgendaItemTopic.destroy_all
    get meeting_url(@meeting)
    assert_response :success

    assert_select "h2", text: "Issues in This Meeting", count: 0
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/meetings_controller_test.rb -v`
Expected: FAIL — `assigns(:ongoing_topics)` is nil, section HTML missing

**Step 3: Write the controller logic**

In `app/controllers/meetings_controller.rb`, replace the `show` action:

```ruby
def show
  @meeting = Meeting.find(params[:id])

  approved_topics = @meeting.topics.approved
    .includes(:topic_appearances, :topic_briefing)
    .distinct

  @ongoing_topics, @new_topics = approved_topics.partition do |topic|
    topic.topic_appearances.size > 1
  end
end
```

**Step 4: Run test to verify controller logic passes (HTML tests still fail)**

Run: `bin/rails test test/controllers/meetings_controller_test.rb -n "/assigns/" -v`
Expected: PASS for assigns tests, FAIL for HTML tests (view not updated yet)

**Step 5: Commit**

```
feat: load and partition meeting topics in MeetingsController#show
```

---

## Task 2: View — Render "Issues in This Meeting" section

**Files:**
- Modify: `app/views/meetings/show.html.erb:211` (before the back link)
- Test: `test/controllers/meetings_controller_test.rb` (HTML assertions from Task 1)

**Step 1: Add the section to meetings/show.html.erb**

Insert before the `<%= link_to meetings_path, class: "back-link" do %>` block (line 213). The section goes between the Documents `</section>` and the back link:

```erb
<% if @ongoing_topics.present? || @new_topics.present? %>
  <section class="section">
    <h2>Issues in This Meeting</h2>

    <% if @ongoing_topics.present? %>
      <div class="mb-8">
        <h3>Ongoing</h3>
        <p class="text-sm text-secondary mb-4">These issues have come up across multiple meetings. Click any for the full picture.</p>
        <div class="card-grid">
          <% @ongoing_topics.each do |topic| %>
            <%= render "topics/topic_card", topic: topic %>
          <% end %>
        </div>
      </div>
    <% end %>

    <% if @new_topics.present? %>
      <div>
        <h3>New This Meeting</h3>
        <p class="text-sm text-secondary mb-4">These issues came up for the first time.</p>
        <div class="card-grid">
          <% @new_topics.each do |topic| %>
            <%= render "topics/topic_card", topic: topic %>
          <% end %>
        </div>
      </div>
    <% end %>
  </section>
<% end %>
```

**Step 2: Run all meetings controller tests**

Run: `bin/rails test test/controllers/meetings_controller_test.rb -v`
Expected: ALL PASS

**Step 3: Commit**

```
feat: add "Issues in This Meeting" section to meeting show page
```

---

## Task 3: Homepage — Filter meeting row topic pills by impact

**Files:**
- Modify: `app/views/home/_meeting_row.html.erb:10-23`
- Test: `test/controllers/home_controller_test.rb` (add new test, update existing)

**Step 1: Write the failing test**

Add to `test/controllers/home_controller_test.rb`:

```ruby
test "meeting row shows only topics with impact >= 2" do
  low_impact_topic = Topic.create!(
    name: "minor procedure change",
    status: "approved",
    lifecycle_status: "active",
    resident_impact_score: 1
  )
  high_impact_topic = Topic.create!(
    name: "major road closure",
    status: "approved",
    lifecycle_status: "active",
    resident_impact_score: 3
  )

  item_low = AgendaItem.create!(meeting: @future_meeting, title: "Procedure")
  AgendaItemTopic.create!(topic: low_impact_topic, agenda_item: item_low)

  item_high = AgendaItem.create!(meeting: @future_meeting, title: "Road Work")
  AgendaItemTopic.create!(topic: high_impact_topic, agenda_item: item_high)

  get root_url
  assert_response :success

  assert_select ".tag--topic", text: "major road closure"
  assert_select ".tag--topic", text: "minor procedure change", count: 0
end

test "meeting row shows no pills when no topics meet impact threshold" do
  # All existing topics have nil impact score
  get root_url
  assert_response :success

  # No "No topics yet" text should appear
  assert_select ".meeting-topics-col .text-muted", count: 0
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/home_controller_test.rb -n "/impact|no pills/" -v`
Expected: FAIL — low-impact topic still renders, "No topics yet" still present

**Step 3: Update the partial**

Replace lines 10-23 of `app/views/home/_meeting_row.html.erb`:

```erb
  <td class="meeting-topics-col">
    <% topics = meeting.agenda_items.flat_map(&:topics).uniq.select { |t| t.approved? && (t.resident_impact_score || 0) >= 2 } %>
    <% if topics.any? %>
      <div class="flex flex-wrap gap-1">
        <% topics.each do |topic| %>
          <%= link_to topic.name, topic_path(topic), class: "tag tag--topic" %>
        <% end %>
      </div>
    <% end %>
  </td>
```

Key changes:
- Filter: only approved topics with `resident_impact_score >= 2`
- No `.first(3)` cap
- No "+X more" overflow
- No "No topics yet" fallback — empty cell if nothing qualifies

**Step 4: Run all home controller tests**

Run: `bin/rails test test/controllers/home_controller_test.rb -v`
Expected: ALL PASS

Note: The existing test `"shows topic tags on meeting rows"` (line 156) creates `@active_topic` with no `resident_impact_score` (nil), so it will now fail. Update it:

```ruby
test "shows topic tags on meeting rows" do
  @active_topic.update!(resident_impact_score: 3)
  get root_url
  assert_response :success

  assert_select ".tag", text: "downtown tif district"
end
```

**Step 5: Commit**

```
feat: filter homepage topic pills by impact score, remove cap and overflow
```

---

## Task 4: Update existing test + verify full suite

**Files:**
- Modify: `test/controllers/home_controller_test.rb:156-161` (if not already fixed in Task 3)

**Step 1: Run the full test suite**

Run: `bin/rails test -v`
Expected: ALL PASS

**Step 2: Run lint**

Run: `bin/rubocop`
Expected: No new offenses

**Step 3: Commit any remaining test fixes**

```
test: update home controller tests for impact-filtered topic pills
```

---

## Task 5: Update development plan + docs

**Files:**
- Modify: `docs/topic-first-migration-plan.md:72` (check off item 6)
- Modify: `docs/DEVELOPMENT_PLAN.md` (if needed)

**Step 1: Mark item 6 complete in migration plan**

Change line 72 from:
```
6) Topic navigation: standardize click-through behavior.
```
to:
```
6) [x] Topic navigation: standardize click-through behavior.
```

**Step 2: Commit**

```
docs: mark topic navigation as complete in migration plan
```
