# Topic Briefing Context Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix topic briefings that starve on agenda structure alone — plumb per-item meeting summary content into the briefing context, clean up orphan `TopicSummary` rows left by `PruneHollowAppearancesJob`, and add sanitation KB entries so pattern detection actually has something to detect.

**Architecture:** Three complementary fixes against the same symptom on topic 513 ("garbage and recycling service changes"):
1. **RC3 (prune job):** Extend `PruneHollowAppearancesJob#perform` to destroy `TopicSummary` rows when all of a (topic, meeting) pair's appearances are pruned. Prevents stale summaries polluting future briefings.
2. **RC1 (context plumbing):** Add a new `recent_item_details` key to `GenerateTopicBriefingJob#build_briefing_context` that pulls filtered `item_details` entries from each recent meeting's `MeetingSummary`. No new AI calls, no new model relationships — just plumbing. Update the `analyze_topic_briefing` prompt to reference the new field.
3. **RC2 (editorial KB):** Author 3-5 `KnowledgeSource` entries covering Two Rivers' sticker-based waste collection, known friction points, and wind-driven recycling litter. Done via admin UI.

**Tech Stack:** Rails 8.1, Ruby 4.0, PostgreSQL with pgvector, Minitest, Kamal 2.

**Reference:** GitHub issue #93. Source prune design spec: `docs/superpowers/specs/2026-04-11-prune-hollow-topic-appearances-design.md`.

---

## File Structure

**Create:**
- `app/services/topics/title_normalizer.rb` — Extracted normalize-title logic. One class method: `Topics::TitleNormalizer.normalize(title) -> String`.
- `app/services/topics/recent_item_details_builder.rb` — Builds the `recent_item_details` list for the briefing context. Isolated so it can be unit-tested without stubbing the AI service.
- `test/services/topics/title_normalizer_test.rb`
- `test/services/topics/recent_item_details_builder_test.rb`

**Modify:**
- `app/jobs/prune_hollow_appearances_job.rb` — RC3 orphan-TopicSummary cleanup. Swap private `normalize_title` for `Topics::TitleNormalizer`.
- `test/jobs/prune_hollow_appearances_job_test.rb` — Two new tests for orphan cleanup (plus one for multi-appearance preservation).
- `app/jobs/topics/generate_topic_briefing_job.rb` — RC1: use `RecentItemDetailsBuilder`, pass `recent_item_details` into the context hash.
- `test/jobs/topics/generate_topic_briefing_job_test.rb` — Assert new context key in the `analyze_topic_briefing` argument.
- `lib/prompt_template_data.rb` — RC1: update `"analyze_topic_briefing"` instructions to reference `recent_item_details`.

**Not touched:**
- `app/services/topics/summary_context_builder.rb` — Existing per-meeting topic summary context is a separate concern. The new plumbing is briefing-specific.
- `app/jobs/summarize_meeting_job.rb` — read-only reference. `generate_topic_summaries` already enqueues briefings correctly.
- `app/views/**` — the user-facing topic page is already reading from `TopicBriefing.generation_data["factual_record"]`. Fixing upstream content is enough; no view changes required.

---

## Task 1: Add RC3 orphan-TopicSummary cleanup test (red)

**Files:**
- Test: `test/jobs/prune_hollow_appearances_job_test.rb`

- [ ] **Step 1: Write the failing test for single-appearance-pruned-to-zero orphan cleanup**

Add this test at the end of `PruneHollowAppearancesJobTest`, just before the final `end`:

```ruby
test "destroys orphaned TopicSummary when all of a topic's appearances on a meeting are pruned" do
  meeting, item = create_meeting_with_item(title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
  create_summary(meeting, item_details: [
    {
      "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
      "summary" => "Leaf totals; nothing substantive.",
      "activity_level" => "status_update",
      "vote" => nil, "decision" => nil, "public_hearing" => nil,
      "citations" => []
    }
  ])
  topic = link_topic(item, topic_name: "garbage and recycling service changes")

  # Per-meeting topic digest created by SummarizeMeetingJob. When the
  # appearance is pruned this row is stale and must go with it.
  TopicSummary.create!(
    topic: topic,
    meeting: meeting,
    summary_type: "topic_digest",
    content: "stale digest",
    generation_data: { "factual_record" => [ { "statement" => "agenda included this topic" } ] }
  )

  assert_equal 1, TopicSummary.where(topic: topic, meeting: meeting).count

  PruneHollowAppearancesJob.perform_now(meeting.id)

  assert_equal 0, TopicAppearance.where(topic_id: topic.id, meeting_id: meeting.id).count
  assert_equal 0, TopicSummary.where(topic: topic, meeting: meeting).count,
    "stale TopicSummary should be destroyed alongside its pruned appearances"
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/jobs/prune_hollow_appearances_job_test.rb -n "/destroys orphaned TopicSummary/"`

Expected: FAIL with an assertion that the TopicSummary count is still 1 after the job runs.

- [ ] **Step 3: Write the second failing test: preservation when another appearance remains on the same meeting**

Add immediately after the previous test:

```ruby
test "preserves TopicSummary when topic still has another appearance on the same meeting" do
  meeting = Meeting.create!(
    body_name: "Public Utilities Committee",
    starts_at: 1.day.ago,
    detail_page_url: "http://example.com/m#{SecureRandom.hex(4)}"
  )
  hollow_item = meeting.agenda_items.create!(
    title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
    order_index: 1
  )
  substantive_item = meeting.agenda_items.create!(
    title: "11. Garbage & Recycling Discussion",
    order_index: 2
  )

  create_summary(meeting, item_details: [
    {
      "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
      "summary" => "Routine.",
      "activity_level" => "status_update",
      "vote" => nil, "decision" => nil, "public_hearing" => nil,
      "citations" => []
    },
    {
      "agenda_item_title" => "11. Garbage & Recycling Discussion",
      "summary" => "Committee reviewed proposed changes and deferred a vote.",
      "activity_level" => "discussion",
      "vote" => nil, "decision" => nil, "public_hearing" => nil,
      "citations" => []
    }
  ])

  topic = Topic.create!(name: "garbage and recycling service changes", status: "approved")
  AgendaItemTopic.create!(agenda_item: hollow_item, topic: topic)
  AgendaItemTopic.create!(agenda_item: substantive_item, topic: topic)

  TopicSummary.create!(
    topic: topic,
    meeting: meeting,
    summary_type: "topic_digest",
    content: "live digest",
    generation_data: { "factual_record" => [ { "statement" => "committee deferred" } ] }
  )

  assert_equal 2, TopicAppearance.where(topic_id: topic.id, meeting_id: meeting.id).count

  PruneHollowAppearancesJob.perform_now(meeting.id)

  assert_equal 1, TopicAppearance.where(topic_id: topic.id, meeting_id: meeting.id).count,
    "hollow appearance should be pruned"
  assert_equal 1, TopicSummary.where(topic: topic, meeting: meeting).count,
    "TopicSummary must survive because substantive appearance still exists"
end
```

- [ ] **Step 4: Run both tests and verify the first fails, the second currently passes (because the job never touches TopicSummary)**

Run: `bin/rails test test/jobs/prune_hollow_appearances_job_test.rb -n "/orphaned TopicSummary|preserves TopicSummary/"`

Expected: first test FAILs (`TopicSummary count is still 1`), second PASSes (no-op).

---

## Task 2: Implement RC3 orphan-TopicSummary cleanup

**Files:**
- Modify: `app/jobs/prune_hollow_appearances_job.rb:38-59`

- [ ] **Step 1: Insert the orphan-cleanup pass between the destroy loop and the demote loop**

In `app/jobs/prune_hollow_appearances_job.rb`, replace the body of `perform` from `agenda_items.each` through the end of the method with:

```ruby
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

    # After destroying hollow appearances, any TopicSummary for a
    # (topic, meeting) pair where no appearance remains is stale and
    # must be destroyed. Otherwise GenerateTopicBriefingJob keeps
    # feeding it as prior_meeting_analyses and the briefing regenerates
    # "appeared on the agenda" factual_record entries from pruned data.
    # If a topic has multiple appearances on the same meeting via
    # different agenda items and only some were pruned, the TopicSummary
    # must be preserved — use an existence check per (topic, meeting).
    affected_topic_ids.each do |topic_id|
      still_has_appearance = TopicAppearance
        .where(topic_id: topic_id, meeting_id: meeting.id)
        .exists?
      unless still_has_appearance
        TopicSummary.where(topic_id: topic_id, meeting_id: meeting.id).destroy_all
      end
    end

    affected_topic_ids.each do |topic_id|
      topic = Topic.find_by(id: topic_id)
      next unless topic
      demote_topic(topic, meeting_id)
    end
  end
```

- [ ] **Step 2: Run the two new tests and verify they pass**

Run: `bin/rails test test/jobs/prune_hollow_appearances_job_test.rb -n "/orphaned TopicSummary|preserves TopicSummary/"`

Expected: both PASS.

- [ ] **Step 3: Run the full prune job test file to confirm no regression**

Run: `bin/rails test test/jobs/prune_hollow_appearances_job_test.rb`

Expected: all existing tests still pass plus the 2 new ones.

- [ ] **Step 4: Commit**

```bash
git add app/jobs/prune_hollow_appearances_job.rb test/jobs/prune_hollow_appearances_job_test.rb
git commit -m "$(cat <<'EOF'
fix(jobs): destroy orphan TopicSummary rows when pruning hollow appearances

PruneHollowAppearancesJob was leaving stale TopicSummary rows behind when
it detached an AgendaItemTopic, causing GenerateTopicBriefingJob to keep
feeding pruned meeting data into prior_meeting_analyses. The briefing AI
then regenerated "appeared on the agenda" factual_record entries from
data that should no longer exist.

Adds a post-destroy pass that removes TopicSummary.where(topic, meeting)
when no TopicAppearance remains for that pair. Preserves summaries when
the topic still has other live appearances on the same meeting (a topic
can have multiple appearances via different agenda items).

Refs #93 (RC3).
EOF
)"
```

---

## Task 3: Extract Topics::TitleNormalizer shared helper

**Files:**
- Create: `app/services/topics/title_normalizer.rb`
- Create: `test/services/topics/title_normalizer_test.rb`
- Modify: `app/jobs/prune_hollow_appearances_job.rb:86-95`

- [ ] **Step 1: Write the failing test for Topics::TitleNormalizer**

Create `test/services/topics/title_normalizer_test.rb`:

```ruby
require "test_helper"

class Topics::TitleNormalizerTest < ActiveSupport::TestCase
  test "strips leading item numbering like '10.'" do
    assert_equal "solid waste utility updates and action",
      Topics::TitleNormalizer.normalize("10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
  end

  test "strips YY-NNN council numbering" do
    assert_equal "public hearing on zoning",
      Topics::TitleNormalizer.normalize("26-001 Public hearing on zoning")
  end

  test "strips trailing ', as needed'" do
    assert_equal "solid waste updates and action",
      Topics::TitleNormalizer.normalize("Solid Waste Updates and Action, As Needed")
  end

  test "strips trailing ', if applicable'" do
    assert_equal "optional walkthrough",
      Topics::TitleNormalizer.normalize("Optional Walkthrough, If Applicable")
  end

  test "collapses whitespace and downcases" do
    assert_equal "parking plan vote",
      Topics::TitleNormalizer.normalize("  Parking   Plan   Vote  ")
  end

  test "returns empty string for nil or blank input" do
    assert_equal "", Topics::TitleNormalizer.normalize(nil)
    assert_equal "", Topics::TitleNormalizer.normalize("")
    assert_equal "", Topics::TitleNormalizer.normalize("   ")
  end

  test "tolerates a non-string input by coercing to string" do
    assert_equal "7a", Topics::TitleNormalizer.normalize("7a.")
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/services/topics/title_normalizer_test.rb`

Expected: FAIL with `uninitialized constant Topics::TitleNormalizer`.

- [ ] **Step 3: Create `app/services/topics/title_normalizer.rb`**

```ruby
module Topics
  # Normalizes agenda item titles for fuzzy matching against
  # MeetingSummary item_details entries. Strips leading numbering
  # (including YY-NNN council ordinals), trailing "as needed"/
  # "if applicable" suffixes, collapses whitespace, downcases.
  #
  # Extracted from PruneHollowAppearancesJob so both that job and
  # Topics::RecentItemDetailsBuilder share a single title-matching
  # convention. Extending this regex is a backwards-incompatible
  # change to both consumers — verify via the full test suite.
  class TitleNormalizer
    def self.normalize(title)
      return "" if title.nil?
      str = title.to_s
      return "" if str.strip.empty?

      str
        .gsub(/\A\s*\d+(-\d+)?[a-z]?\.?\s*/i, "")
        .gsub(/\s*,?\s*as needed\s*\z/i, "")
        .gsub(/\s*,?\s*if applicable\s*\z/i, "")
        .gsub(/\s+/, " ")
        .downcase
        .strip
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/services/topics/title_normalizer_test.rb`

Expected: PASS (7 assertions).

- [ ] **Step 5: Swap PruneHollowAppearancesJob to use the shared helper**

In `app/jobs/prune_hollow_appearances_job.rb`:

1. Replace the private `normalize_title` method (lines 86–95) with a thin delegator so `build_entry_map` doesn't need to change:

```ruby
  def normalize_title(title)
    Topics::TitleNormalizer.normalize(title)
  end
```

(Keeping the private wrapper is deliberate — it avoids a line-by-line rewrite of `build_entry_map` and preserves a single extraction point in case the job ever needs a more specialized variant.)

- [ ] **Step 6: Run the prune job tests to confirm no regression**

Run: `bin/rails test test/jobs/prune_hollow_appearances_job_test.rb`

Expected: all tests PASS (including the YY-NNN normalization test, which is the sharpest canary).

- [ ] **Step 7: Commit**

```bash
git add app/services/topics/title_normalizer.rb test/services/topics/title_normalizer_test.rb app/jobs/prune_hollow_appearances_job.rb
git commit -m "$(cat <<'EOF'
refactor(topics): extract TitleNormalizer for agenda item matching

Both PruneHollowAppearancesJob (existing) and the upcoming
RecentItemDetailsBuilder need identical title normalization to match
agenda_items against MeetingSummary item_details entries. Extract to
Topics::TitleNormalizer with unit tests covering the YY-NNN council
numbering edge case.

No behavior change. Refs #93.
EOF
)"
```

---

## Task 4: Create Topics::RecentItemDetailsBuilder service (TDD)

**Files:**
- Create: `app/services/topics/recent_item_details_builder.rb`
- Create: `test/services/topics/recent_item_details_builder_test.rb`

- [ ] **Step 1: Write the failing test for the happy path**

Create `test/services/topics/recent_item_details_builder_test.rb`:

```ruby
require "test_helper"

class Topics::RecentItemDetailsBuilderTest < ActiveSupport::TestCase
  setup do
    @topic = Topic.create!(name: "garbage and recycling service changes", status: "approved")
    @meeting = Meeting.create!(
      body_name: "Public Utilities Committee",
      starts_at: 1.week.ago,
      detail_page_url: "http://example.com/puc-aug"
    )
    @linked_item = @meeting.agenda_items.create!(
      title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
      order_index: 1
    )
    AgendaItemTopic.create!(agenda_item: @linked_item, topic: @topic)
  end

  test "returns item_details entries for agenda items linked to the topic" do
    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: {
        "item_details" => [
          {
            "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
            "summary" => "Staff reported fake stickers showing up on refuse; committee declined to revisit the method.",
            "activity_level" => "discussion",
            "vote" => nil, "decision" => nil, "public_hearing" => nil,
            "citations" => [ "Page 4" ]
          }
        ]
      }
    )

    result = Topics::RecentItemDetailsBuilder.new(@topic, [ @meeting ]).build

    assert_equal 1, result.length
    entry = result.first
    assert_equal @meeting.starts_at.to_date.to_s, entry[:meeting_date]
    assert_equal "Public Utilities Committee", entry[:meeting_body]
    assert_equal "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED", entry[:agenda_item_title]
    assert_includes entry[:summary], "fake stickers"
    assert_equal "discussion", entry[:activity_level]
  end

  test "filters out item_details entries whose agenda_item is not linked to the topic" do
    unlinked_item = @meeting.agenda_items.create!(title: "5. WATER UTILITY UPDATE", order_index: 2)
    # unlinked_item has no AgendaItemTopic pointing at @topic

    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: {
        "item_details" => [
          {
            "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
            "summary" => "Fake stickers.",
            "activity_level" => "discussion"
          },
          {
            "agenda_item_title" => "5. WATER UTILITY UPDATE",
            "summary" => "Pump replacement underway.",
            "activity_level" => "status_update"
          }
        ]
      }
    )

    result = Topics::RecentItemDetailsBuilder.new(@topic, [ @meeting ]).build

    assert_equal 1, result.length
    assert_includes result.first[:summary], "Fake stickers"
    refute(result.any? { |r| r[:summary].to_s.include?("Pump replacement") },
      "water update should not leak into garbage topic context")
  end

  test "returns empty array when meeting has no summary" do
    assert_equal [], Topics::RecentItemDetailsBuilder.new(@topic, [ @meeting ]).build
  end

  test "returns empty array when summary generation_data has no item_details" do
    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: { "headline" => "no item details key" }
    )
    assert_equal [], Topics::RecentItemDetailsBuilder.new(@topic, [ @meeting ]).build
  end

  test "uses the most recent summary when multiple exist for the same meeting" do
    older = @meeting.meeting_summaries.create!(
      summary_type: "packet_analysis",
      generation_data: {
        "item_details" => [
          {
            "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
            "summary" => "preview guess",
            "activity_level" => "status_update"
          }
        ]
      }
    )
    older.update_columns(created_at: 2.days.ago)

    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: {
        "item_details" => [
          {
            "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
            "summary" => "real minutes content",
            "activity_level" => "discussion"
          }
        ]
      }
    )

    result = Topics::RecentItemDetailsBuilder.new(@topic, [ @meeting ]).build

    assert_equal 1, result.length
    assert_equal "real minutes content", result.first[:summary]
  end

  test "normalizes item titles before matching (handles numbering variance)" do
    # Agenda item title has no leading number; item_details has a prefix.
    @linked_item.update!(title: "Solid Waste Utility: Updates and Action")

    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: {
        "item_details" => [
          {
            "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
            "summary" => "real content",
            "activity_level" => "discussion"
          }
        ]
      }
    )

    result = Topics::RecentItemDetailsBuilder.new(@topic, [ @meeting ]).build
    assert_equal 1, result.length, "TitleNormalizer should strip numbering and 'as needed' to match"
  end

  test "handles multiple meetings and preserves chronological order" do
    earlier = Meeting.create!(
      body_name: "Public Utilities Committee",
      starts_at: 30.days.ago,
      detail_page_url: "http://example.com/puc-older"
    )
    earlier_item = earlier.agenda_items.create!(title: "SOLID WASTE UTILITY", order_index: 1)
    AgendaItemTopic.create!(agenda_item: earlier_item, topic: @topic)
    earlier.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: {
        "item_details" => [
          {
            "agenda_item_title" => "SOLID WASTE UTILITY",
            "summary" => "Older meeting content.",
            "activity_level" => "discussion"
          }
        ]
      }
    )

    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: {
        "item_details" => [
          {
            "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
            "summary" => "Newer meeting content.",
            "activity_level" => "discussion"
          }
        ]
      }
    )

    result = Topics::RecentItemDetailsBuilder.new(@topic, [ earlier, @meeting ]).build

    assert_equal 2, result.length
    # Order mirrors the input meetings array so the caller controls
    # chronology. See the fixture setup — earlier is passed first.
    assert_equal "Older meeting content.", result[0][:summary]
    assert_equal "Newer meeting content.", result[1][:summary]
  end
end
```

- [ ] **Step 2: Run the test file to verify it fails**

Run: `bin/rails test test/services/topics/recent_item_details_builder_test.rb`

Expected: FAIL with `uninitialized constant Topics::RecentItemDetailsBuilder`.

- [ ] **Step 3: Create `app/services/topics/recent_item_details_builder.rb`**

```ruby
module Topics
  # Builds a filtered list of per-item substantive content for a topic,
  # pulled from the most recent MeetingSummary on each provided meeting.
  #
  # Used by GenerateTopicBriefingJob to give the briefing AI access to
  # the actual content of agenda items linked to the topic — not just
  # agenda structure. This is the content that already lives in
  # MeetingSummary.generation_data["item_details"] and is shown on the
  # meeting page but never flowed into the topic-level briefing prompt.
  #
  # Matching is fuzzy on normalized titles via Topics::TitleNormalizer:
  # an item_details entry is included only if its agenda_item_title,
  # normalized, equals the normalized title of an AgendaItem on the
  # meeting that is linked to the target topic via AgendaItemTopic.
  #
  # Output shape per entry (Symbol keys — these flow into a Hash passed
  # to OpenAI, which serializes them as JSON):
  #   {
  #     meeting_date: "2025-08-04",
  #     meeting_body: "Public Utilities Committee",
  #     agenda_item_title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
  #     summary: "Staff reported fake stickers...",
  #     activity_level: "discussion",
  #     vote: nil,
  #     decision: nil,
  #     public_hearing: nil
  #   }
  class RecentItemDetailsBuilder
    def initialize(topic, meetings)
      @topic = topic
      @meetings = Array(meetings)
    end

    def build
      @meetings.flat_map { |meeting| entries_for(meeting) }
    end

    private

    def entries_for(meeting)
      summary = meeting.meeting_summaries.order(created_at: :desc).first
      return [] unless summary&.generation_data.is_a?(Hash)

      details = summary.generation_data["item_details"]
      return [] unless details.is_a?(Array)

      linked_normalized_titles = linked_title_set(meeting)
      return [] if linked_normalized_titles.empty?

      details.filter_map do |entry|
        next nil unless entry.is_a?(Hash)
        title = entry["agenda_item_title"]
        next nil unless title.is_a?(String)
        next nil unless linked_normalized_titles.include?(Topics::TitleNormalizer.normalize(title))

        {
          meeting_date: meeting.starts_at&.to_date&.to_s,
          meeting_body: meeting.body_name,
          agenda_item_title: title,
          summary: entry["summary"],
          activity_level: entry["activity_level"],
          vote: entry["vote"],
          decision: entry["decision"],
          public_hearing: entry["public_hearing"]
        }
      end
    end

    def linked_title_set(meeting)
      meeting.agenda_items
        .joins(:agenda_item_topics)
        .where(agenda_item_topics: { topic_id: @topic.id })
        .pluck(:title)
        .map { |t| Topics::TitleNormalizer.normalize(t) }
        .to_set
    end
  end
end
```

- [ ] **Step 4: Run the test file to verify it passes**

Run: `bin/rails test test/services/topics/recent_item_details_builder_test.rb`

Expected: all 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/topics/recent_item_details_builder.rb test/services/topics/recent_item_details_builder_test.rb
git commit -m "$(cat <<'EOF'
feat(topics): add RecentItemDetailsBuilder for briefing context

Isolates the logic that pulls per-item substantive content from
MeetingSummary.generation_data["item_details"] and filters it to the
agenda items linked to the target topic. Uses Topics::TitleNormalizer
for fuzzy matching against item titles (handles YY-NNN numbering,
"as needed" suffixes, whitespace variance).

Wired into GenerateTopicBriefingJob in the next commit. Refs #93 (RC1).
EOF
)"
```

---

## Task 5: Wire RecentItemDetailsBuilder into GenerateTopicBriefingJob (TDD)

**Files:**
- Modify: `app/jobs/topics/generate_topic_briefing_job.rb:29-73`
- Modify: `test/jobs/topics/generate_topic_briefing_job_test.rb`

- [ ] **Step 1: Write a failing test that asserts `recent_item_details` appears in the context**

Add this test at the end of `Topics::GenerateTopicBriefingJobTest`, just before the final `end`:

```ruby
test "context passed to analyze_topic_briefing includes recent_item_details from linked agenda items" do
  # Attach a MeetingSummary with item_details for the linked agenda item
  @meeting.meeting_summaries.create!(
    summary_type: "minutes_recap",
    generation_data: {
      "item_details" => [
        {
          "agenda_item_title" => "Parking Plan Vote",
          "summary" => "Council converted 8 downtown spots to 15-minute loading.",
          "activity_level" => "discussion",
          "vote" => "4-3",
          "decision" => nil,
          "public_hearing" => nil
        }
      ]
    }
  )

  captured_context = nil
  analysis_json = {
    "headline" => "h", "upcoming_headline" => nil,
    "editorial_analysis" => { "current_state" => "c" },
    "factual_record" => [],
    "resident_impact" => { "score" => 3, "rationale" => "r" }
  }.to_json

  mock_ai = Minitest::Mock.new
  mock_ai.expect :analyze_topic_briefing, analysis_json do |arg|
    captured_context = arg
    arg.is_a?(Hash)
  end
  mock_ai.expect :render_topic_briefing, {
    "editorial_content" => "e", "record_content" => "r"
  } do |_| true end

  retrieval_stub = Object.new
  def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
  def retrieval_stub.format_topic_context(*args); []; end

  RetrievalService.stub :new, retrieval_stub do
    Ai::OpenAiService.stub :new, mock_ai do
      Topics::GenerateTopicBriefingJob.perform_now(
        topic_id: @topic.id,
        meeting_id: @meeting.id
      )
    end
  end

  assert captured_context.key?(:recent_item_details),
    "briefing context must include :recent_item_details key"
  assert_kind_of Array, captured_context[:recent_item_details]
  assert_equal 1, captured_context[:recent_item_details].length
  entry = captured_context[:recent_item_details].first
  assert_equal "Parking Plan Vote", entry[:agenda_item_title]
  assert_includes entry[:summary], "15-minute loading"
  assert_equal "4-3", entry[:vote]

  mock_ai.verify
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/jobs/topics/generate_topic_briefing_job_test.rb -n "/recent_item_details/"`

Expected: FAIL with `captured_context does not have key :recent_item_details`.

- [ ] **Step 3: Modify `build_briefing_context` to populate `recent_item_details`**

In `app/jobs/topics/generate_topic_briefing_job.rb`, replace the `build_briefing_context` method (lines 29–73) with:

```ruby
    def build_briefing_context(topic, meeting, retrieval_service)
      prior_summaries = topic.topic_summaries
        .joins(:meeting)
        .order("meetings.starts_at ASC")
        .pluck(:generation_data)

      recent_meeting_ids = topic.topic_appearances
        .joins(:meeting)
        .order("meetings.starts_at DESC")
        .limit(RAW_CONTEXT_MEETING_LIMIT)
        .pluck(:meeting_id)

      recent_meetings = Meeting.where(id: recent_meeting_ids).order(starts_at: :desc)
      recent_raw_context = recent_meetings.flat_map do |m|
        builder = Topics::SummaryContextBuilder.new(topic, m)
        builder.build_context_json[:agenda_items]
      end

      # Pull per-item substantive content from each recent meeting's
      # MeetingSummary. Without this, the briefing AI sees only agenda
      # structure (item titles + empty `item.summary` fields) and
      # regenerates "appeared on the agenda" factual_record entries.
      # The content already exists in generation_data["item_details"];
      # we just filter to agenda items linked to this topic.
      recent_item_details = Topics::RecentItemDetailsBuilder
        .new(topic, recent_meetings.to_a)
        .build

      query = "#{topic.canonical_name} #{topic.topic_aliases.pluck(:name).join(' ')}"
      kb_chunks = retrieval_service.retrieve_topic_context(
        topic: topic, query_text: query, limit: 5, max_chars: 6000
      )
      formatted_kb = retrieval_service.format_topic_context(kb_chunks)

      {
        topic_metadata: {
          id: topic.id,
          canonical_name: topic.canonical_name,
          lifecycle_status: topic.lifecycle_status,
          first_seen_at: topic.first_seen_at&.iso8601,
          last_seen_at: topic.last_seen_at&.iso8601,
          aliases: topic.topic_aliases.pluck(:name)
        },
        prior_meeting_analyses: prior_summaries,
        recent_raw_context: recent_raw_context,
        recent_item_details: recent_item_details,
        knowledgebase_context: formatted_kb,
        continuity_context: {
          status_events: topic.topic_status_events.order(occurred_at: :desc).limit(5).map do |e|
            { event_type: e.evidence_type, notes: e.notes, date: e.occurred_at&.iso8601 }
          end,
          total_appearances: topic.topic_appearances.count
        },
        upcoming_context: build_upcoming_context(topic)
      }
    end
```

Note: I renamed the inner `meeting` block variable to `m` in `recent_raw_context` to avoid shadowing the outer `meeting` parameter — that shadowing was a pre-existing lint smell in the file but I'm only renaming it because I now need to re-use `recent_meetings` for the new builder call and want to keep the section readable.

- [ ] **Step 4: Run the new test**

Run: `bin/rails test test/jobs/topics/generate_topic_briefing_job_test.rb -n "/recent_item_details/"`

Expected: PASS.

- [ ] **Step 5: Run the full briefing job test file**

Run: `bin/rails test test/jobs/topics/generate_topic_briefing_job_test.rb`

Expected: all 6 tests PASS (5 existing + 1 new).

- [ ] **Step 6: Commit**

```bash
git add app/jobs/topics/generate_topic_briefing_job.rb test/jobs/topics/generate_topic_briefing_job_test.rb
git commit -m "$(cat <<'EOF'
feat(jobs): plumb recent_item_details into briefing context

GenerateTopicBriefingJob#build_briefing_context now calls
Topics::RecentItemDetailsBuilder and includes its output as a
recent_item_details key in the analyze_topic_briefing argument hash.

This exposes the per-item minutes content (fake stickers, resident
complaints, committee dispositions, etc.) that was already stored in
MeetingSummary.generation_data["item_details"] but never flowed to the
topic-level prompt. The briefing AI can now write specific
factual_record entries and detect patterns across meetings instead of
repeatedly reporting "appeared on the agenda".

Prompt template update in the next commit. Refs #93 (RC1).
EOF
)"
```

---

## Task 6: Update the analyze_topic_briefing prompt to reference recent_item_details

**Files:**
- Modify: `lib/prompt_template_data.rb:595-801` (the `"analyze_topic_briefing"` entry)

- [ ] **Step 1: Inspect the current prompt and locate the insertion point**

Open `lib/prompt_template_data.rb` and find the `"analyze_topic_briefing"` entry. Locate the `<constraints>` block and the `TOPIC CONTEXT (JSON):` line. The new guidance goes immediately after `<constraints>` and before `{{committee_context}}` so the AI reads it before seeing the context payload.

- [ ] **Step 2: Add a new `<data_sources>` block to the instructions**

In `lib/prompt_template_data.rb`, find this block:

```ruby
        - The audience voice rules in <headline_criteria> below apply ONLY to three fields:
          `headline`, `upcoming_headline`, and `editorial_analysis.current_state`.
          All other fields (`factual_record`, `civic_sentiment`, `pattern_observations`,
          `process_concerns`, `continuity_signals`, `resident_impact`, `ambiguities`,
          `verification_notes`) must remain neutral, evidence-bound, and observational.
          Do not let the audience voice bleed into those fields.
        </constraints>

        {{committee_context}}
```

Replace it with:

```ruby
        - The audience voice rules in <headline_criteria> below apply ONLY to three fields:
          `headline`, `upcoming_headline`, and `editorial_analysis.current_state`.
          All other fields (`factual_record`, `civic_sentiment`, `pattern_observations`,
          `process_concerns`, `continuity_signals`, `resident_impact`, `ambiguities`,
          `verification_notes`) must remain neutral, evidence-bound, and observational.
          Do not let the audience voice bleed into those fields.
        </constraints>

        <data_sources>
        The TOPIC CONTEXT below contains several data sources. Use them in this order of priority when writing `factual_record` entries, detecting patterns, and framing `editorial_analysis.current_state`:

        1. `recent_item_details` — The SUBSTANTIVE CONTENT of agenda items linked to this topic from the most recent meetings. Each entry has the actual summary of what was discussed, any activity_level classification, and any vote/decision/public_hearing fields. THIS IS THE PRIMARY SOURCE FOR SPECIFIC FACTS. When a recent_item_details entry contains a concrete incident (e.g., "resident complained about sticker purchase requirement", "Manitowoc Disposal reported fake stickers"), write a factual_record entry that names the specific incident. Do not default to "appeared on the agenda" phrasing when recent_item_details has real content.

        2. `prior_meeting_analyses` — Structured analyses from prior per-meeting TopicSummary rows. These are derivative; prefer recent_item_details when both describe the same meeting.

        3. `recent_raw_context` — Agenda structure (item titles, attachments, packet previews). Useful for meetings without item_details or for items that didn't make it into item_details. Lower priority than recent_item_details.

        4. `knowledgebase_context` — Background civic context (how the city works, history, atypical arrangements). Use this to FRAME patterns, not to report events.

        5. `continuity_context` — Lifecycle signals (status events, total appearance count). Supports pattern_observations and continuity_signals fields.

        6. `upcoming_context` — Scheduled future meetings. Drives `upcoming_headline`.

        When recent_item_details contradicts older prior_meeting_analyses (e.g., an older summary says "appeared on agenda" but recent_item_details says "committee discussed X"), trust recent_item_details. Older summaries may have been generated before this content was available.

        If recent_item_details is empty or contains no substantive content across multiple meetings, write a quiet, honest current_state that names what's on the agenda without manufacturing pattern framing.
        </data_sources>

        {{committee_context}}
```

- [ ] **Step 3: Run the prompt template validator**

Run: `bin/rails prompt_templates:validate`

Expected: no errors. (The task validates that all `{{placeholder}}` tokens referenced in each template exist in the interpolation call sites.)

- [ ] **Step 4: Populate the template into the local database**

Run: `bin/rails prompt_templates:populate`

Expected: output showing `analyze_topic_briefing` updated and a new `PromptVersion` row created for rollback.

- [ ] **Step 5: Sanity-check the prompt renders in admin UI**

If the dev server isn't already running, start it: `bin/dev &`

Then visit `http://localhost:3000/admin/prompt_templates` (login required — see `config/credentials.yml.enc` for admin seed). Open the `analyze_topic_briefing` template and confirm the new `<data_sources>` block is present and reads cleanly.

Stop the dev server if you started it for this step.

- [ ] **Step 6: Run the full test suite**

Run: `bin/rails test`

Expected: all tests pass. The prompt change does not affect any test because tests stub `Ai::OpenAiService` — but run the full suite as a sanity check for the larger set of changes.

- [ ] **Step 7: Run RuboCop**

Run: `bin/rubocop`

Expected: clean. Fix any style complaints before committing.

- [ ] **Step 8: Commit**

```bash
git add lib/prompt_template_data.rb
git commit -m "$(cat <<'EOF'
feat(prompts): teach analyze_topic_briefing about recent_item_details

Adds a <data_sources> block to the prompt instructions that names
recent_item_details as the primary source for specific factual claims
and explains the priority order across the six context keys. Tells
the AI to trust recent_item_details over older prior_meeting_analyses
when they contradict, and to write quiet honest current_state prose
when item_details is empty rather than manufacturing pattern framing.

This completes the context-plumbing half of RC1. The briefing AI can
now name fake stickers, resident complaints, and committee dispositions
by their specifics instead of "appeared on the agenda". Refs #93 (RC1).
EOF
)"
```

---

## Task 7: Deploy and run full CI locally before pushing

**Files:** (none — verification only)

- [ ] **Step 1: Run bin/ci locally**

Run: `bin/ci`

Expected: setup, rubocop, bundler-audit, importmap audit, brakeman all pass. Note CI does not run tests — do that separately.

- [ ] **Step 2: Run the full test suite**

Run: `bin/rails test`

Expected: all tests PASS. Fix any breakage before continuing.

- [ ] **Step 3: Push to master**

```bash
git push origin master
```

- [ ] **Step 4: Deploy to production**

```bash
source .env && export TWO_RIVERS_REPORTER_DATABASE_PASSWORD && bin/kamal deploy
```

Expected: deploy succeeds, kamal-proxy shows the new container healthy, `https://tworiversmatters.com` still loads.

- [ ] **Step 5: Populate the prompt template on production**

```bash
source .env && export TWO_RIVERS_REPORTER_DATABASE_PASSWORD && bin/kamal app exec "bin/rails prompt_templates:populate"
```

Expected: output confirms `analyze_topic_briefing` updated in prod DB and a new `PromptVersion` row created (that's the rollback row).

---

## Task 8: Production orphan-TopicSummary cleanup (one-shot)

**Files:** (none — runtime-only operation)

Context: The RC3 code fix only prevents new orphans. Existing orphans from the previous pruning run (topic 513 has ~3, others have some) are still in place and must be cleaned up manually once.

- [ ] **Step 1: Count orphans on production**

```bash
source .env && export TWO_RIVERS_REPORTER_DATABASE_PASSWORD && \
bin/kamal app exec "bin/rails runner 'orphans = TopicSummary.joins(%{LEFT JOIN topic_appearances ta ON ta.topic_id = topic_summaries.topic_id AND ta.meeting_id = topic_summaries.meeting_id}).where(%{ta.id IS NULL}); puts \"Orphan TopicSummary count: #{orphans.count}\"; puts \"Affected topic ids: #{orphans.pluck(:topic_id).uniq.sort.inspect}\"'"
```

Expected: prints an integer and an array of topic IDs. Record both — they drive Step 2 and 3. Sanity check: the count should be single-to-double digits (tens, not hundreds). If it's larger than expected, pause and re-read the query — it should only match rows whose (topic_id, meeting_id) has zero TopicAppearance rows left.

- [ ] **Step 2: Run the cleanup — capture affected topic IDs, then destroy**

```bash
source .env && export TWO_RIVERS_REPORTER_DATABASE_PASSWORD && \
bin/kamal app exec "bin/rails runner '
  orphans = TopicSummary
    .joins(%{LEFT JOIN topic_appearances ta ON ta.topic_id = topic_summaries.topic_id AND ta.meeting_id = topic_summaries.meeting_id})
    .where(%{ta.id IS NULL})

  affected = orphans.pluck(:topic_id).uniq
  puts \"Destroying #{orphans.count} orphan TopicSummary rows across #{affected.length} topics\"
  orphans.find_each(&:destroy!)
  puts \"Done. Affected topic IDs: #{affected.inspect}\"
'"
```

Expected: confirms the orphan count is destroyed and prints the affected topic IDs. Copy that ID list for Step 3.

- [ ] **Step 3: Re-run GenerateTopicBriefingJob for affected topics**

Using the affected IDs from Step 2 (replace `[513, 123, ...]` with the real list):

```bash
source .env && export TWO_RIVERS_REPORTER_DATABASE_PASSWORD && \
bin/kamal app exec "bin/rails runner '
  ids = [513, 123]  # REPLACE with the real affected_topic_ids from Step 2
  ids.each do |tid|
    topic = Topic.find_by(id: tid)
    next unless topic&.approved?
    appearance = topic.topic_appearances.order(appeared_at: :desc).first
    unless appearance
      puts \"Skipping topic #{tid}: no live appearances\"
      next
    end
    Topics::GenerateTopicBriefingJob.perform_later(topic_id: tid, meeting_id: appearance.meeting_id)
    puts \"Enqueued briefing for topic #{tid} (#{topic.canonical_name}) via meeting #{appearance.meeting_id}\"
  end
'"
```

Expected: one enqueue line per affected topic. Solid Queue will pick them up within a few seconds.

- [ ] **Step 4: Watch the job run and tail logs for failures**

```bash
source .env && export TWO_RIVERS_REPORTER_DATABASE_PASSWORD && bin/kamal logs --grep "GenerateTopicBriefingJob" --lines 200
```

Expected: each enqueued topic shows a `Performed` line within a minute or two. Any `Error` lines need investigation before continuing.

- [ ] **Step 5: Verify topic 513 specifically**

```bash
source .env && export TWO_RIVERS_REPORTER_DATABASE_PASSWORD && \
bin/kamal app exec "bin/rails runner '
  t = Topic.find(513)
  puts \"appearances: #{t.topic_appearances.count}\"
  puts \"topic_summaries: #{t.topic_summaries.count}\"
  puts \"impact: #{t.resident_impact_score}\"
  puts \"lifecycle: #{t.lifecycle_status}\"
  br = t.topic_briefing
  if br
    puts \"headline: #{br.headline.inspect}\"
    puts \"factual_record entries: #{(br.generation_data[%{factual_record}] || []).length}\"
    puts \"first 3 factual_record events:\"
    (br.generation_data[%{factual_record}] || []).first(3).each_with_index do |e, i|
      puts \"  [#{i}] #{e[%{date}]} — #{e[%{event}]}\"
    end
  end
'"
```

Expected (success signals):
- `topic_summaries` equals `DISTINCT meeting_id` count in appearances (no orphans)
- `factual_record` entries reference specific incidents (fake stickers / resident sticker complaint / leaf collection / grant paperwork) — not just "agenda included"
- `impact` may drop from 4 to 2-3 once the AI re-rates with real content; either is acceptable editorially

If the factual_record is still `appeared on the agenda` boilerplate, the prompt update didn't take — go back and verify `prompt_templates:populate` picked up the `<data_sources>` block (read the active template body via `PromptTemplate.find_by(key: 'analyze_topic_briefing').instructions` in the same runner context).

---

## Task 9: RC2 — Author sanitation KnowledgeSource entries (editorial, manual)

**Files:** (none — done via `/admin/knowledge_sources` UI)

Context: Three (optionally four) knowledge source entries covering Two Rivers' unusual waste collection arrangement. These are editorial assertions — do not code-generate them. The user authors them via the admin UI because they reflect civic framing judgments that aren't in the minutes or derivable from the minutes without human interpretation.

- [ ] **Step 1: Open the admin knowledge sources UI**

Visit `https://tworiversmatters.com/admin/knowledge_sources` (or local equivalent if editing locally first, then promoting to prod).

- [ ] **Step 2: Create "Two Rivers uses sticker-based pay-as-you-go trash collection"**

Title: `Two Rivers uses sticker-based pay-as-you-go trash collection`

Body:
```
Residents purchase stickers at local businesses and affix them to bags
for collection. This is unusual for a city of ~10k residents; most
Wisconsin cities this size use flat-fee bag or cart systems. The method
has been repeatedly evaluated during budget cycles and retained on cost
grounds — most recently confirmed during the 2024 budget preparation
process as the most affordable option for residents (per Public
Utilities Committee minutes, August 2025).
```

Link to topic 513 "garbage and recycling service changes". Save.

- [ ] **Step 3: Create "Sticker method has generated recurring friction with residents"**

Title: `Sticker method has generated recurring friction with residents`

Body:
```
Known friction points include: (a) fake stickers appearing on collected
refuse, flagged by Manitowoc Disposal and Two Rivers Police (August
2025); (b) resident complaints about local businesses requiring
additional purchases to obtain stickers (January 2026); (c) social-media
chatter periodically calling for a switch to automated collection. The
Public Utilities Committee has declined each time to revisit the method.
```

Link to topic 513. Save.

- [ ] **Step 4: Create "Open recycling bins are prone to wind-driven litter"**

Title: `Open recycling bins are prone to wind-driven litter`

Body:
```
Two Rivers is a Lake Michigan lakeshore city with significant prevailing
winds. Open recycling bins — particularly at public spaces and the
lakefront — are a recurring source of litter dispersal. Resident
complaints about beach garbage often trace back to this design
limitation.
```

Link to topic 513 and any beach/lakefront topic if one exists. Save.

- [ ] **Step 5: Wait for `IngestKnowledgeSourceJob` to build embeddings**

Each KnowledgeSource save enqueues an ingestion job that chunks the body and builds pgvector embeddings. Watch the job log:

```bash
source .env && export TWO_RIVERS_REPORTER_DATABASE_PASSWORD && bin/kamal logs --grep "IngestKnowledgeSourceJob" --lines 100
```

Expected: three `Performed` lines within a minute.

- [ ] **Step 6: Verify retrieval returns chunks for topic 513**

```bash
source .env && export TWO_RIVERS_REPORTER_DATABASE_PASSWORD && \
bin/kamal app exec "bin/rails runner '
  t = Topic.find(513)
  query = \"#{t.canonical_name} #{t.topic_aliases.pluck(:name).join(\" \")}\"
  rs = RetrievalService.new
  chunks = rs.retrieve_topic_context(topic: t, query_text: query, limit: 5, max_chars: 6000)
  puts \"chunk count: #{chunks.length}\"
  chunks.each_with_index do |c, i|
    puts \"[#{i}] #{c.respond_to?(:content) ? c.content.to_s.truncate(120) : c.inspect}\"
  end
'"
```

Expected: 3+ chunks, each an excerpt of the sticker/friction/bin entries. If the count is still 0, check that `KnowledgeSourceTopic` rows were created (the admin UI should have done this at save time — a nil count there means the topic link control wasn't used, go back to Steps 2–4 and add it).

- [ ] **Step 7: Re-run GenerateTopicBriefingJob for topic 513 one more time**

Now that both the code fix (Tasks 1–7) and the KB entries are in place, regenerate the briefing so it uses both:

```bash
source .env && export TWO_RIVERS_REPORTER_DATABASE_PASSWORD && \
bin/kamal app exec "bin/rails runner '
  t = Topic.find(513)
  appearance = t.topic_appearances.order(appeared_at: :desc).first
  Topics::GenerateTopicBriefingJob.perform_now(topic_id: 513, meeting_id: appearance.meeting_id)
  puts t.reload.topic_briefing.headline
  puts \"---\"
  puts (t.topic_briefing.generation_data[\"factual_record\"] || []).first(5).to_json
'"
```

Expected: headline and factual_record references at least one specific incident.

---

## Task 10: Final verification checklist

**Files:** (none — verification only)

- [ ] **Step 1: Full test suite clean**

Run locally: `bin/rails test test/jobs/ test/services/topics/`

Expected: all tests PASS, including:
- 2 new `PruneHollowAppearancesJob` orphan cleanup tests
- 7 `Topics::TitleNormalizer` tests
- 7 `Topics::RecentItemDetailsBuilder` tests
- 1 new `Topics::GenerateTopicBriefingJob` test

- [ ] **Step 2: RuboCop clean**

Run: `bin/rubocop`

Expected: no offenses.

- [ ] **Step 3: Topic 513 prod state sanity check**

```bash
source .env && export TWO_RIVERS_REPORTER_DATABASE_PASSWORD && \
bin/kamal app exec "bin/rails runner '
  t = Topic.find(513)
  meeting_count_via_appearances = t.topic_appearances.distinct.count(:meeting_id)
  summary_count = t.topic_summaries.count
  ks_count = KnowledgeSourceTopic.where(topic_id: 513).count
  puts \"appearances -> distinct meetings: #{meeting_count_via_appearances}\"
  puts \"topic_summaries: #{summary_count}\"
  puts \"linked knowledge sources: #{ks_count}\"
  raise \"orphans remain\" if summary_count > meeting_count_via_appearances
  puts \"OK: no orphans, #{ks_count} KB sources linked\"
'"
```

Expected: the script prints `OK: no orphans, 3 KB sources linked` (or more). Any `orphans remain` error means Task 8 didn't fully run — go back.

- [ ] **Step 4: Eyeball https://tworiversmatters.com/topics/513**

Expected:
- "The Story" section references specific incidents (fake stickers, resident complaint, or beach concerns) in prose.
- "Record" section shows a timeline with entries that name what happened at each meeting, not just "agenda included this topic".
- `resident_impact_score` is either still 4 (if editorially defensible) or has dropped to 2–3 as the AI re-rated with real content.
- Homepage either no longer features topic 513 in Top Stories, or features it for reasons that are obvious from the headline.

- [ ] **Step 5: Eyeball homepage https://tworiversmatters.com**

Expected: no topic cards with the "appeared on the agenda" shape. Top stories all reference specific incidents / dollar amounts / named items.

- [ ] **Step 6: Close issue #93 with a summary comment**

Once all checks pass, close the issue with a comment linking to the commits and summarizing the fix:

```bash
gh issue close 93 --comment "$(cat <<'EOF'
Shipped in commits:
- RC3 (orphan TopicSummary cleanup): <sha>
- RC3 refactor (Topics::TitleNormalizer extraction): <sha>
- RC1 (RecentItemDetailsBuilder service): <sha>
- RC1 (wire into GenerateTopicBriefingJob): <sha>
- RC1 (prompt update): <sha>

Post-deploy cleanup:
- Destroyed N orphan TopicSummary rows on prod
- Re-ran GenerateTopicBriefingJob for affected topics
- Authored 3 sanitation KnowledgeSource entries linked to topic 513

Verification: topic 513's factual_record now references fake stickers
and the January 2026 resident complaint. Impact re-rated from 4 to N.
EOF
)"
```

Replace `<sha>` and `N` with the real values.

---

## Out of scope (do not do in this plan)

- Splitting topic 513 via `topics:split_broad_topic`. The topic container is correct; the problem was upstream.
- Iterating the `activity_level` prompt in `analyze_meeting_content`. The classifier is fine; starvation is at the briefing level.
- Adding logging/monitoring to `PruneHollowAppearancesJob`. That belongs in follow-up #92.
- Detecting patterns in the backend via analytics. The briefing AI is the pattern detector; feed it content, not summary statistics.
- Changing the user-facing topic show view. It already renders `TopicBriefing.generation_data` correctly; fixing upstream is enough.
