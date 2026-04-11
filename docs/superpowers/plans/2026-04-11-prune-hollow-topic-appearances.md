# Prune Hollow Topic Appearances Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop treating recurring standing-agenda-slot appearances (e.g., "SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED") as evidence of civic activity, by detaching hollow `AgendaItemTopic` rows after meeting summarization and cleaning up existing phantom topics via a one-time backfill.

**Architecture:** Add an `activity_level` field to `analyze_meeting_content` output. A new `PruneHollowAppearancesJob` runs at the end of `SummarizeMeetingJob`, detaches hollow appearances using the field plus existing motion/public-hearing signals, and demotes affected topics (block if 0 appearances remain, dormant if 1, re-run briefing if 2+). A companion rake task applies a rule-based heuristic (no AI regeneration) to clean up historical data.

**Tech Stack:** Rails 8.1, Ruby 4.0, Minitest, Solid Queue. Prompts live in the `PromptTemplate` DB table with single-source-of-truth in `lib/prompt_template_data.rb`, synced via `bin/rails prompt_templates:populate`.

**Spec:** `docs/superpowers/specs/2026-04-11-prune-hollow-topic-appearances-design.md`

---

## File Structure

**New files:**

| Path | Responsibility |
|---|---|
| `app/jobs/prune_hollow_appearances_job.rb` | Going-forward job that detaches hollow AgendaItemTopic rows, destroys their TopicAppearances, and demotes affected topics |
| `test/jobs/prune_hollow_appearances_job_test.rb` | Unit tests for the job — hollowness rules, demotion thresholds, admin override protection |

**Modified files:**

| Path | What changes |
|---|---|
| `lib/prompt_template_data.rb` | Add `activity_level` field to `analyze_meeting_content` output schema plus classification guidance in the guidelines section |
| `app/jobs/summarize_meeting_job.rb` | Enqueue `PruneHollowAppearancesJob.perform_later(meeting_id)` after all summaries are written |
| `test/jobs/summarize_meeting_job_test.rb` | Assert the prune job is enqueued |
| `lib/tasks/topics.rake` | Append `prune_hollow_appearances` rake task for one-time backfill |
| `test/lib/tasks/topics_rake_test.rb` | New test file for the rake task (directory does not currently exist — create it) |
| `CLAUDE.md` | Add note about pruning step in the Topic→Homepage Cards pipeline |
| `docs/DEVELOPMENT_PLAN.md` | Update ingestion pipeline diagram to mention pruning |

---

## Task 1: Update `analyze_meeting_content` Prompt

**Files:**
- Modify: `lib/prompt_template_data.rb:928-1094`

Add an `activity_level` field to the `item_details` output schema, add classification guidance to the guidelines section, and update the guidelines bullet for "Item details" to reference the new field.

- [ ] **Step 1: Edit the guidelines block in `lib/prompt_template_data.rb`**

Open `lib/prompt_template_data.rb` and find the `analyze_meeting_content` entry (around line 928). In the `<guidelines>` block, find the "Item details" bullet and replace it with the expanded version below. The old line to replace reads:

```
        - Item details: Cover substantive agenda items only. Each gets 2-4
          sentences of editorial summary explaining what happened and why it
          matters. Include public_hearing note for items with formal public
          input (Wisconsin law three-calls). Include decision and vote tally
          where applicable. Anchor citations to page numbers.
```

Replace it with:

```
        - Item details: Cover substantive agenda items only. Each gets 2-4
          sentences of editorial summary explaining what happened and why it
          matters. Include public_hearing note for items with formal public
          input (Wisconsin law three-calls). Include decision and vote tally
          where applicable. Anchor citations to page numbers.
        - Each item_details entry must include an activity_level field with
          one of three values:
          - "decision" — a motion, vote, formal action, approval, adoption,
            binding commitment, or public hearing occurred on this item.
          - "discussion" — substantive conversation, deliberation, or public
            input occurred, OR the item has clear forward-looking implications
            (a commitment to follow up, a policy question still to resolve,
            a deadline or dependency residents should track) even if no
            formal vote took place. This is the normal category for informal
            subcommittee work.
          - "status_update" — routine informational report only: numbers
            reported, operations status, "nothing new," acknowledgments with
            no decisions and no forward-looking significance. Items a resident
            could safely skip.
          When in doubt, choose "discussion". Use "status_update" only when
          there is genuinely nothing for a resident to act on, follow, or
          care about.
```

- [ ] **Step 2: Update the output_schema in the same entry**

In the same `analyze_meeting_content` entry, find the `<output_schema>` JSON example. Replace the `item_details` array shape so each entry includes `activity_level`. The old block reads:

```
          "item_details": [
            {
              "agenda_item_title": "Title as it appears on the agenda",
              "summary": "2-4 sentences: what happened, why it matters, editorial context.",
              "public_hearing": "Description of public hearing input, or null",
              "decision": "Passed|Failed|Tabled|Referred|null",
              "vote": "7-0 or null",
              "citations": ["Page X"]
            }
          ]
```

Replace it with:

```
          "item_details": [
            {
              "agenda_item_title": "Title as it appears on the agenda",
              "summary": "2-4 sentences: what happened, why it matters, editorial context.",
              "public_hearing": "Description of public hearing input, or null",
              "decision": "Passed|Failed|Tabled|Referred|null",
              "vote": "7-0 or null",
              "activity_level": "decision|discussion|status_update",
              "citations": ["Page X"]
            }
          ]
```

- [ ] **Step 3: Sync the live DB template in the dev environment**

Run the populate task so the new text lands in the local Postgres `prompt_templates` row:

```bash
bin/rails prompt_templates:populate
```

Expected output: a line `Updated 'analyze_meeting_content'` among others.

- [ ] **Step 4: Verify the prompt in the DB contains the new content**

```bash
bin/rails runner 'puts PromptTemplate.find_by(key: "analyze_meeting_content").instructions.include?("activity_level")'
```

Expected output: `true`

- [ ] **Step 5: Commit**

```bash
git add lib/prompt_template_data.rb
git commit -m "$(cat <<'EOF'
feat(prompts): add activity_level field to analyze_meeting_content

Classifies each item_details entry as decision | discussion |
status_update so the downstream pruning job can detach hollow
standing-slot appearances ("SOLID WASTE: UPDATES AND ACTION, AS
NEEDED" etc.) without blocking slots that might one day contain
a real vote.

Refs: docs/superpowers/specs/2026-04-11-prune-hollow-topic-appearances-design.md
EOF
)"
```

---

## Task 2: `PruneHollowAppearancesJob` — Detection and Pruning

**Files:**
- Create: `app/jobs/prune_hollow_appearances_job.rb`
- Create: `test/jobs/prune_hollow_appearances_job_test.rb`

This task builds the job skeleton, title-normalization helper, hollowness detection, and the actual destruction of `AgendaItemTopic` + `TopicAppearance` rows. Topic demotion is deferred to Task 3.

- [ ] **Step 1: Write the failing tests**

Create `test/jobs/prune_hollow_appearances_job_test.rb` with the following content:

```ruby
require "test_helper"

class PruneHollowAppearancesJobTest < ActiveJob::TestCase
  def create_meeting_with_item(title:)
    meeting = Meeting.create!(
      body_name: "Public Utilities Committee",
      starts_at: 1.day.ago,
      detail_page_url: "http://example.com/m#{SecureRandom.hex(4)}"
    )
    item = meeting.agenda_items.create!(title: title, order_index: 1)
    [meeting, item]
  end

  def create_summary(meeting, item_details:)
    meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: { "item_details" => item_details }
    )
  end

  def link_topic(item, topic_name:)
    topic = Topic.create!(name: topic_name, status: "approved")
    AgendaItemTopic.create!(agenda_item: item, topic: topic)
    topic
  end

  test "prunes appearance when activity_level is status_update with null vote/decision/public_hearing" do
    meeting, item = create_meeting_with_item(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
    create_summary(meeting, item_details: [
      {
        "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
        "summary" => "Leaf totals exceeded prior year, no decisions made.",
        "activity_level" => "status_update",
        "vote" => nil,
        "decision" => nil,
        "public_hearing" => nil,
        "citations" => ["Page 4"]
      }
    ])
    topic = link_topic(item, topic_name: "garbage and recycling service changes")

    assert_equal 1, topic.topic_appearances.count
    assert_equal 1, topic.agenda_item_topics.count

    PruneHollowAppearancesJob.perform_now(meeting.id)

    assert_equal 0, topic.reload.topic_appearances.count
    assert_equal 0, topic.agenda_item_topics.count
  end

  test "preserves appearance when activity_level is discussion" do
    meeting, item = create_meeting_with_item(title: "8. WATER UTILITY: DIRECTOR UPDATE")
    create_summary(meeting, item_details: [
      {
        "agenda_item_title" => "8. WATER UTILITY: DIRECTOR UPDATE",
        "summary" => "Lead service line inspection push tied to 2027 deadline.",
        "activity_level" => "discussion",
        "vote" => nil,
        "decision" => nil,
        "public_hearing" => nil,
        "citations" => ["Page 3"]
      }
    ])
    topic = link_topic(item, topic_name: "lead service line replacement")

    PruneHollowAppearancesJob.perform_now(meeting.id)

    assert_equal 1, topic.reload.agenda_item_topics.count
  end

  test "preserves appearance when a motion is linked even if activity_level is status_update" do
    meeting, item = create_meeting_with_item(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
    create_summary(meeting, item_details: [
      {
        "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
        "summary" => "Routine update.",
        "activity_level" => "status_update",
        "vote" => nil,
        "decision" => nil,
        "public_hearing" => nil,
        "citations" => ["Page 4"]
      }
    ])
    topic = link_topic(item, topic_name: "garbage and recycling service changes")

    # A real motion was linked — the prune job must respect it even if
    # the AI mis-labeled the activity_level.
    Motion.create!(
      meeting: meeting,
      agenda_item: item,
      motion_text: "Move to approve new solid waste rate schedule",
      outcome: "passed"
    )

    PruneHollowAppearancesJob.perform_now(meeting.id)

    assert_equal 1, topic.reload.agenda_item_topics.count
  end

  test "preserves appearance when public_hearing is non-null" do
    meeting, item = create_meeting_with_item(title: "5. PUBLIC HEARING ON RATE INCREASE")
    create_summary(meeting, item_details: [
      {
        "agenda_item_title" => "5. PUBLIC HEARING ON RATE INCREASE",
        "summary" => "Two residents spoke about proposed increase.",
        "activity_level" => "status_update",
        "vote" => nil,
        "decision" => nil,
        "public_hearing" => "Two residents testified against the rate increase.",
        "citations" => ["Page 2"]
      }
    ])
    topic = link_topic(item, topic_name: "utility rates")

    PruneHollowAppearancesJob.perform_now(meeting.id)

    assert_equal 1, topic.reload.agenda_item_topics.count
  end

  test "prunes when agenda item has no matching item_details entry (procedural) on new-format summary" do
    meeting, item = create_meeting_with_item(title: "12. ADJOURNMENT")
    # New-format summary: has at least one entry with activity_level.
    # The procedural adjournment item isn't in item_details at all.
    create_summary(meeting, item_details: [
      {
        "agenda_item_title" => "7. OTHER ITEM",
        "summary" => "Something real happened.",
        "activity_level" => "discussion",
        "vote" => nil,
        "decision" => nil,
        "public_hearing" => nil,
        "citations" => ["Page 1"]
      }
    ])
    topic = link_topic(item, topic_name: "adjournment")

    PruneHollowAppearancesJob.perform_now(meeting.id)

    assert_equal 0, topic.reload.agenda_item_topics.count
  end

  test "skips entirely when summary is old-format (no entry has activity_level)" do
    meeting, item = create_meeting_with_item(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
    # Old-format summary: no entry has activity_level. Job should be a no-op.
    create_summary(meeting, item_details: [
      {
        "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
        "summary" => "Routine update.",
        "vote" => nil,
        "decision" => nil,
        "public_hearing" => nil,
        "citations" => ["Page 4"]
      }
    ])
    topic = link_topic(item, topic_name: "garbage and recycling service changes")

    PruneHollowAppearancesJob.perform_now(meeting.id)

    assert_equal 1, topic.reload.agenda_item_topics.count
  end

  test "returns early when meeting has no summary" do
    meeting, item = create_meeting_with_item(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
    topic = link_topic(item, topic_name: "garbage and recycling service changes")

    assert_nothing_raised do
      PruneHollowAppearancesJob.perform_now(meeting.id)
    end
    assert_equal 1, topic.reload.agenda_item_topics.count
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bin/rails test test/jobs/prune_hollow_appearances_job_test.rb
```

Expected: FAIL with `NameError: uninitialized constant PruneHollowAppearancesJob` or similar.

- [ ] **Step 3: Create the job file**

Create `app/jobs/prune_hollow_appearances_job.rb`:

```ruby
# Detaches hollow AgendaItemTopic rows after meeting summarization.
#
# A "hollow" appearance is one where the agenda item had no real civic
# activity — a standing update slot that the AI classified as a
# "status_update" with no vote, decision, or public hearing, and no
# linked motion. The typical offender is "SOLID WASTE UTILITY: UPDATES
# AND ACTION, AS NEEDED" — a monthly placeholder at Public Utilities
# Committee that rarely contains real decisions.
#
# Only operates on new-format summaries that have the `activity_level`
# field on at least one item_details entry. Old summaries are handled
# by the one-time backfill rake task (topics:prune_hollow_appearances).
#
# Topic demotion rules live in Task 3 of the plan — this file initially
# handles detection and pruning only. The demote_topic method is a
# placeholder that gets filled in during Task 3.
class PruneHollowAppearancesJob < ApplicationJob
  queue_as :default

  def perform(meeting_id)
    meeting = Meeting.find_by(id: meeting_id)
    return unless meeting

    summary = meeting.meeting_summaries.order(created_at: :desc).first
    return unless summary&.generation_data.is_a?(Hash)

    item_details = summary.generation_data["item_details"]
    return unless item_details.is_a?(Array)

    new_format = item_details.any? { |e| e.is_a?(Hash) && e.key?("activity_level") }
    return unless new_format

    agenda_items = meeting.agenda_items.to_a
    entry_map = build_entry_map(agenda_items, item_details)

    affected_topic_ids = Set.new

    agenda_items.each do |ai|
      next unless hollow?(ai, entry_map[ai.id])

      AgendaItemTopic.where(agenda_item_id: ai.id).find_each do |ait|
        topic_id = ait.topic_id
        ait.destroy!
        TopicAppearance.where(topic_id: topic_id, agenda_item_id: ai.id).destroy_all
        affected_topic_ids << topic_id
      end
    end

    affected_topic_ids.each do |topic_id|
      topic = Topic.find_by(id: topic_id)
      next unless topic
      demote_topic(topic)
    end
  end

  private

  # Returns a hash mapping agenda_item_id => item_details entry (or nil).
  # Match by normalized title — drop leading numbering, trailing
  # "AS NEEDED" / "IF APPLICABLE", downcase, squish.
  def build_entry_map(agenda_items, item_details)
    normalized_entries = item_details.filter_map do |entry|
      next nil unless entry.is_a?(Hash)
      title = entry["agenda_item_title"]
      next nil unless title.is_a?(String)
      [normalize_title(title), entry]
    end

    agenda_items.each_with_object({}) do |ai, map|
      target = normalize_title(ai.title.to_s)
      match = normalized_entries.find { |norm, _e| norm == target }
      map[ai.id] = match&.last
    end
  end

  def normalize_title(title)
    return "" if title.nil? || title.strip.empty?
    title.to_s
      .gsub(/\A\s*\d+[a-z]?\.?\s*/i, "")
      .gsub(/\s*,?\s*as needed\s*\z/i, "")
      .gsub(/\s*,?\s*if applicable\s*\z/i, "")
      .gsub(/\s+/, " ")
      .downcase
      .strip
  end

  def hollow?(agenda_item, entry)
    return false if Motion.where(agenda_item_id: agenda_item.id).exists?

    # Procedural filter: missing entry on a new-format summary means the
    # AI filtered this item as procedural — eligible for pruning.
    return true if entry.nil?

    entry["activity_level"] == "status_update" &&
      entry["vote"].nil? &&
      entry["decision"].nil? &&
      entry["public_hearing"].nil?
  end

  # Placeholder — real implementation lands in Task 3.
  def demote_topic(topic)
    # intentionally empty for Task 2
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
bin/rails test test/jobs/prune_hollow_appearances_job_test.rb
```

Expected: all 7 tests pass.

If any test fails, debug before moving on. Common issues: `Motion` model may require a different set of attributes; check `bin/rails runner "puts Motion.column_names"` and adjust the test's `Motion.create!` call.

- [ ] **Step 5: Commit**

```bash
git add app/jobs/prune_hollow_appearances_job.rb test/jobs/prune_hollow_appearances_job_test.rb
git commit -m "$(cat <<'EOF'
feat(jobs): PruneHollowAppearancesJob detection and pruning

Detects hollow topic appearances on new-format meeting summaries
using activity_level=status_update + null vote/decision/public_hearing
+ no linked motion. Destroys the AgendaItemTopic and its TopicAppearance
row. Topic demotion is handled in the next commit.

Refs: docs/superpowers/specs/2026-04-11-prune-hollow-topic-appearances-design.md
EOF
)"
```

---

## Task 3: `PruneHollowAppearancesJob` — Topic Demotion and Audit

**Files:**
- Modify: `app/jobs/prune_hollow_appearances_job.rb` (fill in `demote_topic` + helpers)
- Modify: `test/jobs/prune_hollow_appearances_job_test.rb` (add demotion tests)

- [ ] **Step 1: Add failing demotion tests**

Append the following tests to `test/jobs/prune_hollow_appearances_job_test.rb` at the end of the class (before the final `end`):

```ruby
  test "demotes topic to blocked + dormant when pruning drops it to 0 appearances" do
    meeting, item = create_meeting_with_item(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
    create_summary(meeting, item_details: [
      {
        "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
        "summary" => "Nothing substantive.",
        "activity_level" => "status_update",
        "vote" => nil, "decision" => nil, "public_hearing" => nil,
        "citations" => []
      }
    ])
    topic = link_topic(item, topic_name: "phantom topic alpha")

    PruneHollowAppearancesJob.perform_now(meeting.id)

    topic.reload
    assert_equal "blocked", topic.status
    assert_equal "dormant", topic.lifecycle_status

    event = topic.topic_status_events.order(:created_at).last
    refute_nil event, "expected a TopicStatusEvent audit row"
    assert_equal "hollow_appearance_prune", event.evidence_type
    assert_equal "dormant", event.lifecycle_status
  end

  test "demotes topic to dormant when pruning drops it to 1 appearance" do
    meeting_a, item_a = create_meeting_with_item(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
    meeting_b, item_b = create_meeting_with_item(title: "5. REAL SUBSTANTIVE ITEM")

    create_summary(meeting_a, item_details: [
      {
        "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
        "summary" => "Nothing substantive.",
        "activity_level" => "status_update",
        "vote" => nil, "decision" => nil, "public_hearing" => nil,
        "citations" => []
      }
    ])

    topic = Topic.create!(name: "phantom topic beta", status: "approved", lifecycle_status: "active")
    AgendaItemTopic.create!(agenda_item: item_a, topic: topic)
    AgendaItemTopic.create!(agenda_item: item_b, topic: topic)

    assert_equal 2, topic.reload.topic_appearances.count

    PruneHollowAppearancesJob.perform_now(meeting_a.id)

    topic.reload
    assert_equal 1, topic.topic_appearances.count
    assert_equal "approved", topic.status
    assert_equal "dormant", topic.lifecycle_status
  end

  test "leaves topic intact and enqueues briefing when pruning drops it to 2+ appearances" do
    meeting_a, item_a = create_meeting_with_item(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
    meeting_b, item_b = create_meeting_with_item(title: "5. REAL ITEM ONE")
    meeting_c, item_c = create_meeting_with_item(title: "6. REAL ITEM TWO")

    create_summary(meeting_a, item_details: [
      {
        "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
        "summary" => "Nothing substantive.",
        "activity_level" => "status_update",
        "vote" => nil, "decision" => nil, "public_hearing" => nil,
        "citations" => []
      }
    ])

    topic = Topic.create!(name: "mixed topic", status: "approved", lifecycle_status: "active")
    AgendaItemTopic.create!(agenda_item: item_a, topic: topic)
    AgendaItemTopic.create!(agenda_item: item_b, topic: topic)
    AgendaItemTopic.create!(agenda_item: item_c, topic: topic)

    assert_enqueued_with(job: Topics::GenerateTopicBriefingJob) do
      PruneHollowAppearancesJob.perform_now(meeting_a.id)
    end

    topic.reload
    assert_equal 2, topic.topic_appearances.count
    assert_equal "approved", topic.status
    assert_equal "active", topic.lifecycle_status
  end

  test "does not enqueue briefing when resident_impact is admin-locked" do
    meeting_a, item_a = create_meeting_with_item(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
    meeting_b, item_b = create_meeting_with_item(title: "5. REAL ITEM ONE")
    meeting_c, item_c = create_meeting_with_item(title: "6. REAL ITEM TWO")

    create_summary(meeting_a, item_details: [
      {
        "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
        "summary" => "Nothing substantive.",
        "activity_level" => "status_update",
        "vote" => nil, "decision" => nil, "public_hearing" => nil,
        "citations" => []
      }
    ])

    topic = Topic.create!(
      name: "admin locked topic",
      status: "approved",
      lifecycle_status: "active",
      resident_impact_score: 5,
      resident_impact_overridden_at: 1.day.ago
    )
    AgendaItemTopic.create!(agenda_item: item_a, topic: topic)
    AgendaItemTopic.create!(agenda_item: item_b, topic: topic)
    AgendaItemTopic.create!(agenda_item: item_c, topic: topic)

    assert_no_enqueued_jobs(only: Topics::GenerateTopicBriefingJob) do
      PruneHollowAppearancesJob.perform_now(meeting_a.id)
    end

    topic.reload
    assert_equal 2, topic.topic_appearances.count
  end
```

- [ ] **Step 2: Run the new tests and verify they fail**

```bash
bin/rails test test/jobs/prune_hollow_appearances_job_test.rb -n "/demotes|leaves|admin-locked/"
```

Expected: 4 failures (status/lifecycle assertions fail because `demote_topic` is still a placeholder).

- [ ] **Step 3: Implement `demote_topic` and helpers in the job**

Open `app/jobs/prune_hollow_appearances_job.rb` and replace the placeholder `demote_topic` method with the following:

```ruby
  def demote_topic(topic)
    remaining = topic.topic_appearances.count

    case remaining
    when 0
      topic.update!(status: "blocked", lifecycle_status: "dormant")
      record_status_event(topic, lifecycle_status: "dormant",
                          notes: "Blocked — 0 appearances remaining after hollow-appearance pruning.")
    when 1
      topic.update!(lifecycle_status: "dormant")
      record_status_event(topic, lifecycle_status: "dormant",
                          notes: "Demoted — only 1 appearance remaining after hollow-appearance pruning.")
    else
      unless topic.resident_impact_admin_locked?
        Topics::GenerateTopicBriefingJob.perform_later(topic_id: topic.id)
      end
    end
  end

  def record_status_event(topic, lifecycle_status:, notes:)
    TopicStatusEvent.create!(
      topic: topic,
      lifecycle_status: lifecycle_status,
      occurred_at: Time.current,
      evidence_type: "hollow_appearance_prune",
      notes: notes
    )
  end
```

- [ ] **Step 4: Run the full job test file and verify all tests pass**

```bash
bin/rails test test/jobs/prune_hollow_appearances_job_test.rb
```

Expected: 11 tests pass (7 from Task 2 + 4 new ones).

- [ ] **Step 5: Commit**

```bash
git add app/jobs/prune_hollow_appearances_job.rb test/jobs/prune_hollow_appearances_job_test.rb
git commit -m "$(cat <<'EOF'
feat(jobs): PruneHollowAppearancesJob topic demotion rules

After pruning, topics with 0 appearances are blocked + dormant,
topics with 1 appearance are dormant (still approved), and topics
with 2+ appearances get a GenerateTopicBriefingJob enqueued to
re-rate resident_impact_score against the cleaned set. Admin-
overridden scores are protected inside the 180-day window. Every
demotion writes a TopicStatusEvent audit row.

Refs: docs/superpowers/specs/2026-04-11-prune-hollow-topic-appearances-design.md
EOF
)"
```

---

## Task 4: Wire Prune Job into `SummarizeMeetingJob`

**Files:**
- Modify: `app/jobs/summarize_meeting_job.rb:4-17`
- Modify: `test/jobs/summarize_meeting_job_test.rb`

- [ ] **Step 1: Add a failing test for the enqueue**

Open `test/jobs/summarize_meeting_job_test.rb` and append a new test at the end of the class (before the final `end`):

```ruby
  test "enqueues PruneHollowAppearancesJob after summarization" do
    doc = @meeting.meeting_documents.create!(
      document_type: "minutes_pdf",
      source_url: "http://example.com/minutes.pdf",
      extracted_text: "Page 1: routine content."
    )

    generation_data = {
      "headline" => "Routine",
      "highlights" => [],
      "public_input" => [],
      "item_details" => []
    }

    mock_ai = Minitest::Mock.new
    mock_ai.expect :prepare_kb_context, "" do |arg| arg.is_a?(Array) end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |_t, _k, type| type == "minutes" end
    mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg| arg.is_a?(Hash) end
    mock_ai.expect :render_topic_summary, "## Summary" do |arg| arg.is_a?(String) end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        assert_enqueued_with(job: PruneHollowAppearancesJob, args: [@meeting.id]) do
          SummarizeMeetingJob.perform_now(@meeting.id)
        end
      end
    end
  end
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
bin/rails test test/jobs/summarize_meeting_job_test.rb -n "/enqueues PruneHollowAppearancesJob/"
```

Expected: FAIL — "No enqueued job found with {job: PruneHollowAppearancesJob, args: [...]}".

- [ ] **Step 3: Modify `SummarizeMeetingJob#perform`**

Open `app/jobs/summarize_meeting_job.rb` and change the `perform` method (lines 4-17) to enqueue the prune job after all other work. Replace:

```ruby
  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)
    ai_service = ::Ai::OpenAiService.new
    retrieval_service = RetrievalService.new

    # 1. Meeting-Level Summary (Minutes or Packet)
    generate_meeting_summary(meeting, ai_service, retrieval_service)

    # 2. Topic-Level Summaries
    generate_topic_summaries(meeting, ai_service, retrieval_service)

    # 3. Knowledge Extraction (downstream, never blocks summarization)
    ExtractKnowledgeJob.perform_later(meeting.id)
  end
```

with:

```ruby
  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)
    ai_service = ::Ai::OpenAiService.new
    retrieval_service = RetrievalService.new

    # 1. Meeting-Level Summary (Minutes or Packet)
    generate_meeting_summary(meeting, ai_service, retrieval_service)

    # 2. Topic-Level Summaries
    generate_topic_summaries(meeting, ai_service, retrieval_service)

    # 3. Prune hollow topic appearances based on the new summary's
    #    activity_level signal. Runs before knowledge extraction so
    #    downstream jobs see the cleaned-up appearance set.
    PruneHollowAppearancesJob.perform_later(meeting.id)

    # 4. Knowledge Extraction (downstream, never blocks summarization)
    ExtractKnowledgeJob.perform_later(meeting.id)
  end
```

- [ ] **Step 4: Run the new test and verify it passes**

```bash
bin/rails test test/jobs/summarize_meeting_job_test.rb -n "/enqueues PruneHollowAppearancesJob/"
```

Expected: PASS.

- [ ] **Step 5: Run the full summarize test file to verify nothing broke**

```bash
bin/rails test test/jobs/summarize_meeting_job_test.rb
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/jobs/summarize_meeting_job.rb test/jobs/summarize_meeting_job_test.rb
git commit -m "$(cat <<'EOF'
feat(jobs): wire PruneHollowAppearancesJob into SummarizeMeetingJob

Enqueued after meeting + topic summaries are persisted, before
ExtractKnowledgeJob. This ensures downstream consumers see the
pruned appearance set.

Refs: docs/superpowers/specs/2026-04-11-prune-hollow-topic-appearances-design.md
EOF
)"
```

---

## Task 5: Backfill Rake Task

**Files:**
- Modify: `lib/tasks/topics.rake` (append `prune_hollow_appearances` task)
- Create: `test/lib/tasks/topics_prune_hollow_appearances_test.rb`

The backfill uses a rule-based heuristic on existing `item_details` structure because old summaries don't have `activity_level`. It targets standing-slot appearances (by title pattern or repeated-title detection) and confirms hollowness using null structured fields plus prose-length and motion-keyword checks.

- [ ] **Step 1: Write the failing test**

Create `test/lib/tasks/topics_prune_hollow_appearances_test.rb`:

```ruby
require "test_helper"
require "rake"

class TopicsPruneHollowAppearancesRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    @task = Rake::Task["topics:prune_hollow_appearances"]
    @task.reenable
    ENV.delete("DRY_RUN")
  end

  def create_meeting_with_item(title:)
    meeting = Meeting.create!(
      body_name: "Public Utilities Committee",
      starts_at: rand(1..200).days.ago,
      detail_page_url: "http://example.com/m#{SecureRandom.hex(4)}"
    )
    item = meeting.agenda_items.create!(title: title, order_index: 1)
    [meeting, item]
  end

  def create_old_format_summary(meeting, entry_title:, summary_text: "Routine status update with no decisions.")
    meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: {
        "item_details" => [
          {
            "agenda_item_title" => entry_title,
            "summary" => summary_text,
            "vote" => nil,
            "decision" => nil,
            "public_hearing" => nil,
            "citations" => []
          }
        ]
      }
    )
  end

  test "prunes appearances on standing-slot title matches for old-format summaries" do
    topic = Topic.create!(name: "garbage and recycling service changes", status: "approved", lifecycle_status: "active")

    3.times do
      meeting, item = create_meeting_with_item(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
      create_old_format_summary(meeting, entry_title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
      AgendaItemTopic.create!(agenda_item: item, topic: topic)
    end

    assert_equal 3, topic.reload.topic_appearances.count

    @task.invoke

    assert_equal 0, topic.reload.topic_appearances.count
    assert_equal "blocked", topic.status
    assert_equal "dormant", topic.lifecycle_status
  end

  test "preserves standing-slot appearance when a motion is linked" do
    topic = Topic.create!(name: "real garbage decision", status: "approved", lifecycle_status: "active")

    meeting, item = create_meeting_with_item(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
    create_old_format_summary(meeting, entry_title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
                              summary_text: "Committee voted to adopt a new fee schedule. Motion carried 4-0.")
    AgendaItemTopic.create!(agenda_item: item, topic: topic)
    Motion.create!(meeting: meeting, agenda_item: item, motion_text: "Approve fee schedule", outcome: "passed")

    @task.invoke

    assert_equal 1, topic.reload.topic_appearances.count
  end

  test "preserves non-standing-slot appearances" do
    topic = Topic.create!(name: "specific rezoning", status: "approved", lifecycle_status: "active")

    meeting, item = create_meeting_with_item(title: "5. REZONING OF 1234 MAIN STREET")
    create_old_format_summary(meeting, entry_title: "5. REZONING OF 1234 MAIN STREET")
    AgendaItemTopic.create!(agenda_item: item, topic: topic)

    @task.invoke

    assert_equal 1, topic.reload.topic_appearances.count
  end

  test "DRY_RUN mode does not modify the database" do
    topic = Topic.create!(name: "dry run topic", status: "approved", lifecycle_status: "active")

    3.times do
      meeting, item = create_meeting_with_item(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
      create_old_format_summary(meeting, entry_title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
      AgendaItemTopic.create!(agenda_item: item, topic: topic)
    end

    ENV["DRY_RUN"] = "1"
    begin
      @task.invoke
    ensure
      ENV.delete("DRY_RUN")
    end

    assert_equal 3, topic.reload.topic_appearances.count
    assert_equal "active", topic.lifecycle_status
  end

  test "auto-detects repeated titles as standing slots without explicit pattern match" do
    topic = Topic.create!(name: "repeated title topic", status: "approved", lifecycle_status: "active")

    # Title doesn't match the explicit standing-slot pattern list, but it
    # repeats 3+ times across the topic's appearances. Auto-detection
    # should kick in.
    3.times do
      meeting, item = create_meeting_with_item(title: "PARKING LOT MAINTENANCE REPORT")
      create_old_format_summary(meeting, entry_title: "PARKING LOT MAINTENANCE REPORT")
      AgendaItemTopic.create!(agenda_item: item, topic: topic)
    end

    @task.invoke

    assert_equal 0, topic.reload.topic_appearances.count
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bin/rails test test/lib/tasks/topics_prune_hollow_appearances_test.rb
```

Expected: FAIL — either "Don't know how to build task 'topics:prune_hollow_appearances'" or all tests fail because the task doesn't exist.

- [ ] **Step 3: Append the rake task**

Open `lib/tasks/topics.rake` and add a new task at the end of the `namespace :topics do` block (just before the final `end` on line 155). Insert:

```ruby
  desc "One-time backfill: detach hollow topic appearances from standing-slot agenda items"
  task prune_hollow_appearances: :environment do
    dry_run = ENV["DRY_RUN"].present?

    standing_patterns = [
      "updates and action",
      "director update",
      "director's report",
      "directors report",
      "administrator's report",
      "administrators report",
      "chief's report",
      "chiefs report",
      "any other items",
      "any other matters",
      "council communications",
      "communications",
      "citizens' comments",
      "open forum"
    ].freeze

    motion_keywords = %w[motion seconded carried adopted approved ayes nays resolution ordinance].freeze

    normalize = ->(title) {
      title.to_s
        .gsub(/\A\s*\d+[a-z]?\.?\s*/i, "")
        .gsub(/\s*,?\s*as needed\s*\z/i, "")
        .gsub(/\s*,?\s*if applicable\s*\z/i, "")
        .gsub(/\s+/, " ")
        .downcase
        .strip
    }

    matches_pattern = ->(title) {
      standing_patterns.any? { |pat| title.include?(pat) }
    }

    puts "[#{dry_run ? 'DRY RUN' : 'LIVE'}] Scanning AgendaItemTopic rows for hollow appearances..."

    # Pre-compute normalized-title frequency per topic for auto-detection
    title_counts_by_topic = Hash.new { |h, k| h[k] = Hash.new(0) }
    AgendaItemTopic.includes(:agenda_item).find_each do |ait|
      next unless ait.agenda_item
      norm = normalize.call(ait.agenda_item.title)
      title_counts_by_topic[ait.topic_id][norm] += 1
    end

    affected_topic_ids = Set.new
    pruned_count = 0

    AgendaItemTopic.includes(agenda_item: :meeting).find_each do |ait|
      item = ait.agenda_item
      next unless item

      norm = normalize.call(item.title)
      repeats = title_counts_by_topic[ait.topic_id][norm] >= 3
      candidate = matches_pattern.call(norm) || repeats
      next unless candidate

      # No motion linked
      next if Motion.where(agenda_item_id: item.id).exists?

      # Find matching item_details entry via the most recent summary
      meeting = item.meeting
      next unless meeting
      summary = meeting.meeting_summaries.order(created_at: :desc).first
      entry = nil
      if summary&.generation_data.is_a?(Hash)
        details = summary.generation_data["item_details"]
        if details.is_a?(Array)
          entry = details.find do |e|
            next false unless e.is_a?(Hash)
            e_title = e["agenda_item_title"]
            e_title.is_a?(String) && normalize.call(e_title) == norm
          end
        end
      end

      # If the entry exists, it must have null vote/decision/public_hearing
      if entry
        next unless entry["vote"].nil? && entry["decision"].nil? && entry["public_hearing"].nil?

        summary_text = entry["summary"].to_s
        next unless summary_text.length < 600
        lowered = summary_text.downcase
        next if motion_keywords.any? { |kw| lowered.include?(kw) } || lowered.include?("public hearing")
      end

      puts "  PRUNE: topic=#{ait.topic_id} meeting=#{meeting.id} item=\"#{item.title}\""
      next if dry_run

      topic_id = ait.topic_id
      ActiveRecord::Base.transaction do
        ait.destroy!
        TopicAppearance.where(topic_id: topic_id, agenda_item_id: item.id).destroy_all
      end
      affected_topic_ids << topic_id
      pruned_count += 1
    end

    puts "\nPruned #{pruned_count} appearances across #{affected_topic_ids.size} topics."
    next if dry_run

    affected_topic_ids.each do |topic_id|
      topic = Topic.find_by(id: topic_id)
      next unless topic

      remaining = topic.topic_appearances.count
      case remaining
      when 0
        topic.update!(status: "blocked", lifecycle_status: "dormant")
        TopicStatusEvent.create!(
          topic: topic,
          lifecycle_status: "dormant",
          occurred_at: Time.current,
          evidence_type: "hollow_appearance_backfill",
          notes: "Blocked — 0 appearances remaining after backfill pruning."
        )
        puts "  BLOCK: #{topic.name} (0 left)"
      when 1
        topic.update!(lifecycle_status: "dormant")
        TopicStatusEvent.create!(
          topic: topic,
          lifecycle_status: "dormant",
          occurred_at: Time.current,
          evidence_type: "hollow_appearance_backfill",
          notes: "Demoted — only 1 appearance remaining after backfill pruning."
        )
        puts "  DORMANT: #{topic.name} (1 left)"
      else
        unless topic.resident_impact_admin_locked?
          Topics::GenerateTopicBriefingJob.perform_later(topic_id: topic.id)
        end
        puts "  REBRIEF: #{topic.name} (#{remaining} left)"
      end
    end

    puts "\nDone."
  end
```

- [ ] **Step 4: Run the test and verify it passes**

```bash
bin/rails test test/lib/tasks/topics_prune_hollow_appearances_test.rb
```

Expected: all 5 tests pass.

- [ ] **Step 5: Sanity-check against real dev data with DRY_RUN**

```bash
DRY_RUN=1 bin/rails topics:prune_hollow_appearances
```

Expected: prints a list of PRUNE lines including several for topic 513's appearances (Solid Waste Utility rows), no database changes. Verify topic 513 is still intact:

```bash
bin/rails runner 'puts Topic.find(513).topic_appearances.count'
```

Expected: still 8 (unchanged — it was a dry run).

- [ ] **Step 6: Commit**

```bash
git add lib/tasks/topics.rake test/lib/tasks/topics_prune_hollow_appearances_test.rb
git commit -m "$(cat <<'EOF'
feat(tasks): topics:prune_hollow_appearances backfill rake task

One-time cleanup of historical hollow topic appearances. Uses a
rule-based heuristic on existing item_details structure (no AI
regeneration): standing-slot title pattern OR repeated-title
auto-detection, plus no-motion and null-structured-field confirmation
with a prose-length + motion-keyword safety check. Supports DRY_RUN=1
for preview. Applies the same 0/1/2+ demotion rules as the
going-forward job and uses evidence_type "hollow_appearance_backfill"
for audit events.

Refs: docs/superpowers/specs/2026-04-11-prune-hollow-topic-appearances-design.md
EOF
)"
```

---

## Task 6: Documentation Updates

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/DEVELOPMENT_PLAN.md`

- [ ] **Step 1: Update CLAUDE.md pipeline description**

Open `CLAUDE.md` and find the "Pipeline: Topic → Homepage Cards" section in the memory-style notes. It currently lists the flow ending at `HomeController`. Insert a line after the `SummarizeMeetingJob` step describing the prune job.

Find:

```
  → SummarizeMeetingJob → sets resident_impact_score on Topic
  → GenerateTopicBriefingJob → headline + upcoming_headline
  → HomeController: approved + impact thresholds → cards
```

Replace with:

```
  → SummarizeMeetingJob → sets resident_impact_score on Topic
  → PruneHollowAppearancesJob → detaches appearances on items the AI flagged activity_level=status_update (with null vote/decision/public_hearing) and no linked motion; re-runs briefing for topics with 2+ remaining appearances
  → GenerateTopicBriefingJob → headline + upcoming_headline
  → HomeController: approved + impact thresholds → cards
```

- [ ] **Step 2: Update DEVELOPMENT_PLAN.md ingestion flow if it contains a pipeline diagram**

Open `docs/DEVELOPMENT_PLAN.md` and search for any ASCII diagram or step list of the ingestion pipeline. If found, add `PruneHollowAppearancesJob` after `SummarizeMeetingJob`. If the pipeline diagram doesn't exist in that doc or is too abstract to warrant an edit, skip this step — `CLAUDE.md` is the canonical operational reference.

Run:

```bash
grep -n "SummarizeMeetingJob\|summariz" docs/DEVELOPMENT_PLAN.md || echo "no pipeline section found — skip"
```

If anything matches, edit the doc; otherwise skip.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md docs/DEVELOPMENT_PLAN.md
git commit -m "$(cat <<'EOF'
docs: describe hollow-appearance pruning in pipeline overview

Refs: docs/superpowers/specs/2026-04-11-prune-hollow-topic-appearances-design.md
EOF
)"
```

---

## Task 7: Full Test Run and Manual Smoke Check

- [ ] **Step 1: Run the full test suite**

```bash
bin/rails test
```

Expected: all tests pass. If anything unrelated to this work is failing, check whether it was already failing on master before this branch — if so, flag it and move on.

- [ ] **Step 2: Run RuboCop**

```bash
bin/rubocop
```

Expected: no offenses. Fix any style issues in the files this branch touches.

- [ ] **Step 3: Manual DRY_RUN in dev to preview the backfill**

```bash
DRY_RUN=1 bin/rails topics:prune_hollow_appearances 2>&1 | tee /tmp/prune_dry_run.log
```

Scan the output. Expected: the 8 topic-513 appearances and any similar standing-slot appearances show up as PRUNE lines. Nothing else (e.g., specific rezoning topics, named project topics) should be flagged.

- [ ] **Step 4: Live backfill run in dev**

Only proceed if the dry-run output looks right. Otherwise debug first.

```bash
bin/rails topics:prune_hollow_appearances 2>&1 | tee /tmp/prune_live.log
```

- [ ] **Step 5: Verify topic 513 is gone from the homepage query**

```bash
bin/rails runner '
t = Topic.find_by(id: 513)
if t
  puts "name: #{t.name}"
  puts "status: #{t.status}"
  puts "lifecycle: #{t.lifecycle_status}"
  puts "appearances: #{t.topic_appearances.count}"
  puts "impact: #{t.resident_impact_score}"
else
  puts "topic 513 not found"
end
'
```

Expected: topic 513 has 0 or 1 appearances remaining (depending on whether the July 2025 Council Communications appearance matches) and is either blocked+dormant or dormant.

- [ ] **Step 6: Boot the app and visually confirm the homepage**

```bash
bin/dev
```

Open `http://localhost:3000` in a browser. Expected: "garbage and recycling service changes" no longer appears in Top Stories or The Wire. Other topics surface naturally.

Stop the server with Ctrl-C when done.

- [ ] **Step 7: Final commit (if anything changed during the smoke check)**

Only needed if tests, cop, or smoke-check surfaced fixups. Otherwise skip.

```bash
git status
# If there are changes:
git add <files>
git commit -m "fix: smoke-check fixups for hollow appearance pruning"
```

---

## Deployment Notes (not part of plan execution)

After merging to `master` and deploying:

1. **Sync the prompt template on prod** — the app image ships with the new `lib/prompt_template_data.rb`, but the DB row is only updated by running the rake task:
   ```bash
   source .env && export TWO_RIVERS_REPORTER_DATABASE_PASSWORD
   bin/kamal app exec "bin/rails prompt_templates:populate"
   ```
2. **Run backfill on prod in dry-run first:**
   ```bash
   bin/kamal app exec "DRY_RUN=1 bin/rails topics:prune_hollow_appearances"
   ```
3. **Review the prod dry-run output**, then run for real:
   ```bash
   bin/kamal app exec "bin/rails topics:prune_hollow_appearances"
   ```
4. **Spot-check production homepage** at https://tworiversmatters.com.

## Self-Review Notes (plan author, not executor)

- Spec coverage: Part 1 (prompt tweak) → Task 1. Part 2 (going-forward job) → Tasks 2-3. Wiring → Task 4. Part 4 (backfill) → Task 5. Part 5 (score recomputation via GenerateTopicBriefingJob) → handled in demote_topic in Task 3. Edge cases (old-format skip, motion rescue, admin override, public hearing) → covered in Task 2/3 tests.
- Files referenced in later tasks exist (or are created) in earlier tasks: `PruneHollowAppearancesJob` created in Task 2, extended in Task 3, called in Task 4, referenced in Tasks 5/6/7.
- Method names consistent across tasks: `demote_topic`, `normalize_title`, `hollow?`, `build_entry_map`, `record_status_event`.
- Motion model: the plan assumes `Motion.create!(meeting:, agenda_item:, motion_text:, outcome:)` works. If this turns out to be wrong at Task 2 Step 4, the executor should check `bin/rails runner "puts Motion.column_names"` and adjust the test setup — the job logic uses only `Motion.where(agenda_item_id: ...).exists?`, which doesn't depend on any other column.
