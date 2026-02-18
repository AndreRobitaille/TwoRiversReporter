# Homepage Redesign: Resident-First Topic Cards — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the abstract "Worth Watching" / "Recent Signals" homepage cards with resident-focused "Coming Up" and "What Happened" cards showing AI-generated headlines ranked by resident impact scoring.

**Architecture:** Add `resident_impact_score` and `resident_impact_overridden_at` columns to `topics`. Extend `analyze_topic_summary` to produce a `headline` and `resident_impact` score per topic. `SummarizeMeetingJob` propagates the score to the topic (respecting admin override with 180-day expiry). Homepage controller queries by impact score; views render headline + topic name.

**Tech Stack:** Rails migration, Minitest (TDD), OpenAI prompt modification, ERB views

**Design doc:** `docs/plans/2026-02-17-homepage-resident-first-redesign.md` (this file — design in appendix below)

---

## Task 1: Migration — Add resident impact columns to topics

**Files:**
- Create: `db/migrate/XXXXXX_add_resident_impact_to_topics.rb`
- Modified after migrate: `db/schema.rb`

**Step 1: Generate migration**

```bash
bin/rails generate migration AddResidentImpactToTopics resident_impact_score:integer resident_impact_overridden_at:datetime
```

**Step 2: Edit migration to add index and constraint**

The generated migration should look like:

```ruby
class AddResidentImpactToTopics < ActiveRecord::Migration[8.1]
  def change
    add_column :topics, :resident_impact_score, :integer
    add_column :topics, :resident_impact_overridden_at, :datetime
    add_index :topics, :resident_impact_score
  end
end
```

**Step 3: Run migration**

```bash
bin/rails db:migrate
```

Expected: Migration succeeds, `db/schema.rb` updated with new columns.

**Step 4: Commit**

```bash
git add db/migrate/*_add_resident_impact_to_topics.rb db/schema.rb
git commit -m "Add resident_impact_score and override timestamp to topics"
```

---

## Task 2: Topic model — validation and override logic

**Files:**
- Modify: `app/models/topic.rb`
- Test: `test/models/topic_test.rb`

**Step 1: Write the failing tests**

Add to `test/models/topic_test.rb`:

```ruby
test "validates resident_impact_score range 1-5" do
  topic = Topic.new(name: "Test", status: "proposed", resident_impact_score: 6)
  assert_not topic.valid?
  assert_includes topic.errors[:resident_impact_score], "must be less than or equal to 5"

  topic.resident_impact_score = 0
  assert_not topic.valid?
  assert_includes topic.errors[:resident_impact_score], "must be greater than or equal to 1"

  topic.resident_impact_score = 3
  assert topic.valid?
end

test "allows nil resident_impact_score" do
  topic = Topic.new(name: "Test", status: "proposed", resident_impact_score: nil)
  assert topic.valid?
end

test "resident_impact_admin_locked? returns true within 180 days" do
  topic = Topic.create!(name: "Test", status: "proposed",
    resident_impact_score: 4,
    resident_impact_overridden_at: 10.days.ago)
  assert topic.resident_impact_admin_locked?
end

test "resident_impact_admin_locked? returns false after 180 days" do
  topic = Topic.create!(name: "Test", status: "proposed",
    resident_impact_score: 4,
    resident_impact_overridden_at: 181.days.ago)
  assert_not topic.resident_impact_admin_locked?
end

test "resident_impact_admin_locked? returns false when no override" do
  topic = Topic.create!(name: "Test", status: "proposed", resident_impact_score: 3)
  assert_not topic.resident_impact_admin_locked?
end

test "update_resident_impact_from_ai skips when admin locked" do
  topic = Topic.create!(name: "Test", status: "proposed",
    resident_impact_score: 5,
    resident_impact_overridden_at: 10.days.ago)
  topic.update_resident_impact_from_ai(2)
  assert_equal 5, topic.reload.resident_impact_score
end

test "update_resident_impact_from_ai updates when not locked" do
  topic = Topic.create!(name: "Test", status: "proposed",
    resident_impact_score: 2,
    resident_impact_overridden_at: nil)
  topic.update_resident_impact_from_ai(4)
  assert_equal 4, topic.reload.resident_impact_score
end

test "update_resident_impact_from_ai updates when override expired" do
  topic = Topic.create!(name: "Test", status: "proposed",
    resident_impact_score: 5,
    resident_impact_overridden_at: 200.days.ago)
  topic.update_resident_impact_from_ai(3)
  assert_equal 3, topic.reload.resident_impact_score
end
```

**Step 2: Run tests to verify they fail**

```bash
bin/rails test test/models/topic_test.rb
```

Expected: Failures — methods don't exist, validation not present.

**Step 3: Implement in `app/models/topic.rb`**

Add validation (near the existing `importance` validation, around line 19):

```ruby
validates :resident_impact_score, numericality: {
  only_integer: true,
  greater_than_or_equal_to: 1,
  less_than_or_equal_to: 5
}, allow_nil: true
```

Add methods (above `private`, around line 42):

```ruby
RESIDENT_IMPACT_OVERRIDE_WINDOW = 180.days

def resident_impact_admin_locked?
  resident_impact_overridden_at.present? &&
    resident_impact_overridden_at > RESIDENT_IMPACT_OVERRIDE_WINDOW.ago
end

def update_resident_impact_from_ai(score)
  return if resident_impact_admin_locked?

  update(resident_impact_score: score)
end
```

**Step 4: Run tests to verify they pass**

```bash
bin/rails test test/models/topic_test.rb
```

Expected: All pass.

**Step 5: Commit**

```bash
git add app/models/topic.rb test/models/topic_test.rb
git commit -m "Add resident impact score validation and admin override logic to Topic"
```

---

## Task 3: AI prompt — add headline and resident impact to analyze_topic_summary

**Files:**
- Modify: `app/services/ai/open_ai_service.rb:197-269` (the `analyze_topic_summary` method)

**Step 1: Add headline and resident_impact to the extraction spec**

In `app/services/ai/open_ai_service.rb`, find the `<extraction_spec>` section inside `analyze_topic_summary` (around line 227). Add these two fields to the JSON schema, after `"verification_notes"`:

```json
"headline": "One plain-language sentence a resident would understand without context. Focus on what happened or what is coming, not on committee process.",
"resident_impact": {
  "score": 3,
  "rationale": "Brief explanation of why this matters to Two Rivers residents"
}
```

**Step 2: Add scoring guidance**

After the `</resident_reported_rules>` closing tag (around line 225), add a new guidance block:

```
<headline_rules>
- Write one plain-language sentence that a Two Rivers resident would understand without context.
- Focus on what happened or what is coming, not on committee process or institutional mechanics.
- Be specific: "Council approves $2.1M senior center contract in 5-2 vote" not "Senior center topic discussed."
</headline_rules>

<resident_impact_rules>
- Score resident impact 1-5 based on how directly this affects the daily lives, property, finances, community identity, or public services of Two Rivers residents.
- 1: Routine procedural item, no direct resident impact.
- 2: Minor administrative matter with indirect effects.
- 3: Moderate impact — affects a specific group or neighborhood.
- 4: Significant impact — affects most residents (taxes, major infrastructure, services).
- 5: Major impact — community-wide financial, identity, or quality-of-life change.
- Consider: public comment volume, financial impact on residents, physical changes to the community, threats to community identity or services, and whether residents have expressed concern.
- Two Rivers is a small post-industrial city. Residents care about property taxes, development changes, community services, and whether their leaders are listening.
</resident_impact_rules>
```

**Step 3: Verify prompt compiles (no syntax errors)**

```bash
bin/rails runner "Ai::OpenAiService.new; puts 'OK'"
```

Expected: `OK` (no load errors).

**Step 4: Commit**

```bash
git add app/services/ai/open_ai_service.rb
git commit -m "Add headline and resident impact scoring to topic analysis prompt"
```

---

## Task 4: SummarizeMeetingJob — propagate impact score to topic

**Files:**
- Modify: `app/jobs/summarize_meeting_job.rb:48-77` (the `generate_topic_summaries` method)
- Test: `test/jobs/summarize_meeting_job_test.rb`

**Step 1: Write the failing test**

Add a new test to `test/jobs/summarize_meeting_job_test.rb`. Read the existing tests first to follow the pattern (they stub `Ai::OpenAiService`). Add:

```ruby
test "propagates resident_impact_score from AI analysis to topic" do
  analysis_json = {
    "topic_name" => "Test Topic",
    "lifecycle_status" => "active",
    "factual_record" => [],
    "headline" => "Council considers selling the old factory site",
    "resident_impact" => { "score" => 4, "rationale" => "Affects downtown development" }
  }.to_json

  ai_service = Minitest::Mock.new
  ai_service.expect(:analyze_topic_summary, analysis_json, [Hash])
  ai_service.expect(:render_topic_summary, "## Summary", [String])

  retrieval_service = Minitest::Mock.new
  retrieval_service.expect(:retrieve_topic_context, [], [Hash])
  retrieval_service.expect(:format_topic_context, "", [[]])

  # Stub new to return mocks
  Ai::OpenAiService.stub(:new, ai_service) do
    RetrievalService.stub(:new, retrieval_service) do
      SummarizeMeetingJob.perform_now(@meeting.id)
    end
  end

  @topic.reload
  assert_equal 4, @topic.resident_impact_score
end

test "does not overwrite admin-locked resident_impact_score" do
  @topic.update!(resident_impact_score: 5, resident_impact_overridden_at: 10.days.ago)

  analysis_json = {
    "topic_name" => "Test Topic",
    "lifecycle_status" => "active",
    "factual_record" => [],
    "headline" => "Test headline",
    "resident_impact" => { "score" => 2, "rationale" => "Minor" }
  }.to_json

  ai_service = Minitest::Mock.new
  ai_service.expect(:analyze_topic_summary, analysis_json, [Hash])
  ai_service.expect(:render_topic_summary, "## Summary", [String])

  retrieval_service = Minitest::Mock.new
  retrieval_service.expect(:retrieve_topic_context, [], [Hash])
  retrieval_service.expect(:format_topic_context, "", [[]])

  Ai::OpenAiService.stub(:new, ai_service) do
    RetrievalService.stub(:new, retrieval_service) do
      SummarizeMeetingJob.perform_now(@meeting.id)
    end
  end

  @topic.reload
  assert_equal 5, @topic.resident_impact_score
end
```

Note: These tests depend on the existing test setup in the file. Read the `setup` block to determine the correct instance variable names (`@meeting`, `@topic`) and adjust accordingly.

**Step 2: Run tests to verify they fail**

```bash
bin/rails test test/jobs/summarize_meeting_job_test.rb
```

**Step 3: Implement score propagation**

In `app/jobs/summarize_meeting_job.rb`, in the `generate_topic_summaries` method, after `save_topic_summary` (around line 76), add:

```ruby
# Propagate resident impact score to topic
if analysis_json["resident_impact"].is_a?(Hash)
  score = analysis_json["resident_impact"]["score"].to_i
  topic.update_resident_impact_from_ai(score) if score.between?(1, 5)
end
```

**Step 4: Run tests to verify they pass**

```bash
bin/rails test test/jobs/summarize_meeting_job_test.rb
```

**Step 5: Commit**

```bash
git add app/jobs/summarize_meeting_job.rb test/jobs/summarize_meeting_job_test.rb
git commit -m "Propagate AI resident impact score to topic during summarization"
```

---

## Task 5: Homepage controller — replace Worth Watching / Recent Signals queries

**Files:**
- Modify: `app/controllers/home_controller.rb`
- Test: `test/controllers/home_controller_test.rb`

**Step 1: Write the failing tests**

Replace the existing "worth watching" and "recent signals" tests in `test/controllers/home_controller_test.rb`. Keep the setup block but update `@active_topic` and `@recurring_topic` to include `resident_impact_score`. Add new tests:

```ruby
test "coming up card shows high-impact topics with upcoming appearances" do
  @active_topic.update!(resident_impact_score: 4)

  # Give it a headline via topic summary
  meeting = @future_meeting
  TopicSummary.create!(
    topic: @active_topic, meeting: meeting,
    content: "## Summary", summary_type: "topic_digest",
    generation_data: { "headline" => "TIF district expansion under review" }
  )

  get root_url
  assert_response :success
  assert_match "Coming Up", response.body
  assert_match "TIF district expansion under review", response.body
end

test "coming up card hidden when no qualifying topics" do
  # No topics with impact >= 3
  get root_url
  assert_response :success
  assert_no_match "Coming Up", response.body
end

test "what happened card shows recent high-impact decisions" do
  @recurring_topic.update!(resident_impact_score: 3)

  # Create a recent motion
  agenda_item = AgendaItem.create!(meeting: @past_meeting, title: "Rate Vote")
  AgendaItemTopic.create!(topic: @recurring_topic, agenda_item: agenda_item)
  Motion.create!(
    agenda_item: agenda_item, meeting: @past_meeting,
    description: "Approve rate increase", outcome: "approved"
  )

  TopicSummary.create!(
    topic: @recurring_topic, meeting: @past_meeting,
    content: "## Summary", summary_type: "topic_digest",
    generation_data: { "headline" => "Water rates increased 8% for all residents" }
  )

  get root_url
  assert_response :success
  assert_match "What Happened", response.body
  assert_match "Water rates increased 8% for all residents", response.body
end

test "what happened card hidden when no qualifying topics" do
  get root_url
  assert_response :success
  assert_no_match "What Happened", response.body
end
```

Also update the existing empty-state test to match new card names (remove assertions for old "No active topics" and "No recent topic activity" text).

**Step 2: Run tests to verify they fail**

```bash
bin/rails test test/controllers/home_controller_test.rb
```

**Step 3: Rewrite the controller methods**

Replace `build_worth_watching` and `build_recent_signals` in `app/controllers/home_controller.rb` with:

```ruby
COMING_UP_MIN_IMPACT = 3
WHAT_HAPPENED_MIN_IMPACT = 2
WHAT_HAPPENED_WINDOW = 30.days

def build_coming_up
  upcoming_topic_ids = TopicAppearance
    .joins(:meeting)
    .where(meetings: { starts_at: Time.current.. })
    .select(:topic_id).distinct

  topics = Topic.approved
    .where(id: upcoming_topic_ids)
    .where("resident_impact_score >= ?", COMING_UP_MIN_IMPACT)
    .order(resident_impact_score: :desc)
    .limit(CARD_LIMIT)

  attach_headlines(topics)
end

def build_what_happened
  # Topics with recent motions
  motion_topic_ids = Topic.approved
    .joins(agenda_items: :motions)
    .where(motions: { created_at: WHAT_HAPPENED_WINDOW.ago.. })
    .select("topics.id").distinct

  # Topics with recent status events
  event_topic_ids = Topic.approved
    .joins(:topic_status_events)
    .where(topic_status_events: { occurred_at: WHAT_HAPPENED_WINDOW.ago.. })
    .select("topics.id").distinct

  topics = Topic.approved
    .where(id: motion_topic_ids)
    .or(Topic.approved.where(id: event_topic_ids))
    .where("resident_impact_score >= ?", WHAT_HAPPENED_MIN_IMPACT)
    .order(resident_impact_score: :desc, last_activity_at: :desc)
    .limit(CARD_LIMIT)

  attach_headlines(topics)
end

def attach_headlines(topics)
  return [] if topics.empty?

  # Get the most recent headline for each topic from generation_data
  topic_ids = topics.map(&:id)
  latest_summaries = TopicSummary
    .where(topic_id: topic_ids, summary_type: "topic_digest")
    .order(created_at: :desc)
    .select("DISTINCT ON (topic_id) topic_id, generation_data")

  @headlines = latest_summaries.each_with_object({}) do |summary, hash|
    headline = summary.generation_data&.dig("headline")
    hash[summary.topic_id] = headline if headline.present?
  end

  topics
end
```

Update `index` to use the new method names:

```ruby
def index
  @coming_up = build_coming_up
  @what_happened = build_what_happened
  @upcoming_meeting_groups = upcoming_meetings_grouped
  @recent_meeting_groups = recent_meetings_grouped
end
```

Remove the `HighlightSignals` concern include if it's only used by the old cards (check if meeting tables use it too — if not, remove it).

**Step 4: Run tests to verify they pass**

```bash
bin/rails test test/controllers/home_controller_test.rb
```

**Step 5: Commit**

```bash
git add app/controllers/home_controller.rb test/controllers/home_controller_test.rb
git commit -m "Replace homepage queries with resident impact-based Coming Up and What Happened"
```

---

## Task 6: Homepage views — replace card markup

**Files:**
- Modify: `app/views/home/index.html.erb`
- Create: `app/views/home/_coming_up_item.html.erb`
- Create: `app/views/home/_what_happened_item.html.erb`
- Delete: `app/views/home/_worth_watching_item.html.erb`
- Delete: `app/views/home/_recent_signal_item.html.erb`

**Step 1: Create the new partials**

`app/views/home/_coming_up_item.html.erb`:

```erb
<%= link_to topic_path(topic), class: "topic-headline-item" do %>
  <span class="topic-headline-item__name"><%= topic.name %></span>
  <% headline = @headlines[topic.id] %>
  <% if headline %>
    <p class="topic-headline-item__headline"><%= headline %></p>
  <% elsif topic.description.present? %>
    <p class="topic-headline-item__headline"><%= truncate(topic.description, length: 120) %></p>
  <% end %>
<% end %>
```

`app/views/home/_what_happened_item.html.erb`:

```erb
<%= link_to topic_path(topic), class: "topic-headline-item" do %>
  <span class="topic-headline-item__name"><%= topic.name %></span>
  <% headline = @headlines[topic.id] %>
  <% if headline %>
    <p class="topic-headline-item__headline"><%= headline %></p>
  <% elsif topic.description.present? %>
    <p class="topic-headline-item__headline"><%= truncate(topic.description, length: 120) %></p>
  <% end %>
<% end %>
```

**Step 2: Update `app/views/home/index.html.erb`**

Replace the topic signal cards section (lines 13–58) with:

```erb
<%# === Topic Headline Cards === %>
<div class="card-grid mb-8" style="grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));">
  <% if @coming_up.any? %>
    <div class="card card--warm">
      <div class="card-header">
        <h2 class="card-title">Coming Up</h2>
      </div>
      <div class="card-body">
        <% @coming_up.each do |topic| %>
          <%= render "coming_up_item", topic: topic %>
        <% end %>
      </div>
      <div class="card-footer">
        <%= link_to "All topics &#8594;".html_safe, topics_path, class: "text-sm" %>
      </div>
    </div>
  <% end %>

  <% if @what_happened.any? %>
    <div class="card card--cool">
      <div class="card-header">
        <h2 class="card-title">What Happened</h2>
      </div>
      <div class="card-body">
        <% @what_happened.each do |topic| %>
          <%= render "what_happened_item", topic: topic %>
        <% end %>
      </div>
      <div class="card-footer">
        <%= link_to "All topics &#8594;".html_safe, topics_path, class: "text-sm" %>
      </div>
    </div>
  <% end %>
</div>

<% if @coming_up.any? || @what_happened.any? %>
  <hr class="home-divider">
<% end %>
```

**Step 3: Delete old partials**

```bash
rm app/views/home/_worth_watching_item.html.erb app/views/home/_recent_signal_item.html.erb
```

**Step 4: Add basic CSS for the new items**

In `app/assets/stylesheets/application.css`, add:

```css
.topic-headline-item {
  display: block;
  padding: var(--space-2) 0;
  text-decoration: none;
  color: inherit;
  border-bottom: 1px solid var(--color-border);
}

.topic-headline-item:last-child {
  border-bottom: none;
}

.topic-headline-item:hover {
  background-color: var(--color-surface-hover, rgba(0, 0, 0, 0.02));
}

.topic-headline-item__name {
  font-weight: 600;
  display: block;
}

.topic-headline-item__headline {
  margin: 0;
  font-size: 0.875rem;
  color: var(--color-text-secondary);
  line-height: 1.4;
}
```

**Step 5: Run controller tests to verify views render**

```bash
bin/rails test test/controllers/home_controller_test.rb
```

**Step 6: Commit**

```bash
git add app/views/home/ app/assets/stylesheets/application.css
git rm app/views/home/_worth_watching_item.html.erb app/views/home/_recent_signal_item.html.erb
git commit -m "Replace Worth Watching / Recent Signals cards with Coming Up / What Happened"
```

---

## Task 7: Admin UI — resident impact override

**Files:**
- Modify: `app/views/admin/topics/show.html.erb:64-67`
- Modify: `app/controllers/admin/topics_controller.rb:257`
- Test: `test/controllers/admin/topics_controller_test.rb`

**Step 1: Write the failing test**

Add to `test/controllers/admin/topics_controller_test.rb`:

```ruby
test "updating resident impact score sets override timestamp" do
  sign_in_admin
  topic = Topic.create!(name: "Test", status: "approved")

  patch admin_topic_path(topic), params: {
    topic: { resident_impact_score: "4" }
  }

  topic.reload
  assert_equal 4, topic.resident_impact_score
  assert_not_nil topic.resident_impact_overridden_at
  assert_in_delta Time.current, topic.resident_impact_overridden_at, 5.seconds
end
```

Note: Check the existing test file for the `sign_in_admin` helper pattern — it may be named differently. Adapt accordingly.

**Step 2: Run test to verify it fails**

```bash
bin/rails test test/controllers/admin/topics_controller_test.rb -n "/resident_impact/"
```

**Step 3: Implement**

In `app/controllers/admin/topics_controller.rb`:

Update `topic_params` (line 258) to permit the new field:

```ruby
def topic_params
  params.require(:topic).permit(:description, :importance, :name, :source_type, :source_notes, :resident_impact_score)
end
```

In the `update` action (around line 53), add logic to set the override timestamp when resident_impact_score changes:

```ruby
if @topic.will_save_change_to_attribute?(:resident_impact_score) && @topic.resident_impact_score.present?
  @topic.resident_impact_overridden_at = Time.current
end
```

Add this before the `if @topic.save` line.

**Step 4: Update admin topic show view**

In `app/views/admin/topics/show.html.erb`, replace the importance field (around line 65-67):

```erb
<div class="form-group">
  <%= f.label :importance, "Importance (0-10)" %>
  <%= f.number_field :importance, min: 0, max: 10, class: "form-input w-full" %>
</div>
```

with:

```erb
<div class="form-group">
  <%= f.label :importance, "Importance (0-10)" %>
  <%= f.number_field :importance, min: 0, max: 10, class: "form-input w-full" %>
</div>
<div class="form-group">
  <%= f.label :resident_impact_score, "Resident Impact (1-5)" %>
  <%= f.select :resident_impact_score,
    options_for_select(
      [["—", nil], ["1 - Routine", 1], ["2 - Minor", 2], ["3 - Moderate", 3], ["4 - Significant", 4], ["5 - Major", 5]],
      @topic.resident_impact_score
    ),
    {},
    class: "form-input w-full" %>
  <p class="text-xs text-secondary mt-1">
    <% if @topic.resident_impact_admin_locked? %>
      Set by admin (<%= time_ago_in_words(@topic.resident_impact_overridden_at) %> ago, expires in
      <%= distance_of_time_in_words(@topic.resident_impact_overridden_at + 180.days, Time.current) %>)
    <% elsif @topic.resident_impact_score.present? %>
      AI-assessed
    <% else %>
      Not yet scored
    <% end %>
  </p>
</div>
```

**Step 5: Run tests**

```bash
bin/rails test test/controllers/admin/topics_controller_test.rb
```

**Step 6: Commit**

```bash
git add app/controllers/admin/topics_controller.rb app/views/admin/topics/show.html.erb test/controllers/admin/topics_controller_test.rb
git commit -m "Add resident impact score override to admin topic UI"
```

---

## Task 8: Update homepage controller tests for new empty states

**Files:**
- Modify: `test/controllers/home_controller_test.rb`

**Step 1: Update the empty-state test**

The existing test checks for "No active topics with upcoming meetings" and "No recent topic activity detected" — these strings no longer exist. Update the test:

```ruby
test "renders successfully with no data" do
  TopicAppearance.destroy_all
  AgendaItemTopic.destroy_all
  AgendaItem.destroy_all
  TopicStatusEvent.destroy_all
  Meeting.destroy_all
  Topic.destroy_all

  get root_url
  assert_response :success

  # Cards should be hidden, not show empty states
  assert_no_match "Coming Up", response.body
  assert_no_match "What Happened", response.body
  assert_select "p", text: /No upcoming meetings scheduled/
  assert_select "p", text: /No recent meetings/
end
```

Remove or update any other tests referencing `@worth_watching_signals`, `@worth_watching_next_appearances`, `@recent_signals_map`, "Recent Signals", or "Worth Watching" — these no longer exist.

**Step 2: Run full test suite**

```bash
bin/rails test
```

Expected: All pass.

**Step 3: Commit**

```bash
git add test/controllers/home_controller_test.rb
git commit -m "Update homepage tests for Coming Up / What Happened cards"
```

---

## Task 9: Cleanup — remove HighlightSignals concern if unused

**Files:**
- Possibly remove: `app/controllers/concerns/highlight_signals.rb`
- Modify: `app/controllers/home_controller.rb` (remove `include HighlightSignals`)
- Check: `app/controllers/topics_controller.rb` for usage

**Step 1: Check if HighlightSignals is used anywhere else**

```bash
grep -r "HighlightSignals\|highlight_signals\|build_highlight_signals\|HIGHLIGHT_EVENT_TYPES" app/controllers/ app/views/
```

If only used by `HomeController` for the old cards, remove the include and the concern file. If `TopicsController` also uses it (for the topics index page signal badges), keep the concern but remove it from `HomeController`.

**Step 2: Remove or keep based on findings**

If removing:
```bash
rm app/controllers/concerns/highlight_signals.rb
```

Remove `include HighlightSignals` from `app/controllers/home_controller.rb`.

**Step 3: Run tests**

```bash
bin/rails test
```

**Step 4: Commit**

```bash
git add -A
git commit -m "Remove HighlightSignals concern from homepage controller"
```

---

## Task 10: Lint and CI check

**Step 1: Run RuboCop**

```bash
bin/rubocop
```

Fix any issues.

**Step 2: Run full CI**

```bash
bin/ci
```

Expected: Clean pass.

**Step 3: Run full test suite one more time**

```bash
bin/rails test
```

**Step 4: Final commit if any fixes**

```bash
git add -A
git commit -m "Fix lint issues from homepage redesign"
```

---

## Appendix: Design Document

See the full design rationale, resident impact philosophy, and data model details in the first half of this file (above the implementation plan).
