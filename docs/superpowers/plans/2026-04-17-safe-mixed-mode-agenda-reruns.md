# Safe Mixed-Mode Agenda Reruns Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make routine agenda reruns non-destructive and ID-preserving, while adding a separate guarded repair path for legacy meetings that truly need structural normalization.

**Architecture:** Replace `Scrapers::ParseAgendaJob`'s destructive `destroy_all` flow with a reconciliation service that parses candidate agenda rows, matches them to existing rows conservatively, updates parser-owned fields in place, creates only clearly new rows, and aborts on ambiguity. Add a meeting-scoped repair service/job for explicit historical migrations, including dependent-row relinking, and protect both paths with per-meeting locking, transactions, and regression tests.

**Tech Stack:** Ruby on Rails, ActiveJob, ActiveRecord, Minitest, PostgreSQL, Nokogiri.

---

## File map

- **Modify:** `app/jobs/scrapers/parse_agenda_job.rb`
  - Stop deleting agenda items on normal reruns.
  - Parse HTML/PDF into candidate hashes/objects and hand them to a reconciliation service.
  - Wrap reconciliation in `meeting.with_lock` + transaction.
- **Create:** `app/services/agendas/reconcile_items.rb`
  - Core ID-preserving upsert/reconciliation logic.
  - Match by number/title/parent context/order.
  - Return `:noop`, `:updated`, or raise a domain error on ambiguity.
- **Create:** `app/services/agendas/repair_structure.rb`
  - Explicit legacy repair path.
  - Build old→new mapping, relink downstream records, then prune obsolete rows.
- **Create:** `app/jobs/agendas/repair_structure_job.rb`
  - Thin job wrapper for targeted repair execution.
- **Modify:** `app/models/agenda_item.rb`
  - Add matching helpers / normalization helpers if needed for stable comparisons.
- **Modify:** `app/models/meeting.rb`
  - Add agenda structure digest storage accessors if the migration adds columns.
- **Create:** `db/migrate/20260417220000_add_agenda_structure_digest_to_meetings.rb`
  - Persist the last successfully reconciled agenda digest on each meeting.
- **Modify:** `test/jobs/scrapers/parse_agenda_job_test.rb`
  - Add regression tests for safe reruns, ambiguity aborts, and digest no-op behavior.
- **Create:** `test/services/agendas/reconcile_items_test.rb`
  - Unit coverage for matching and in-place updates.
- **Create:** `test/services/agendas/repair_structure_test.rb`
  - Unit coverage for targeted migration/relink behavior.
- **Create:** `test/jobs/agendas/repair_structure_job_test.rb`
  - Job-level coverage for the explicit repair path.
- **Modify:** `test/jobs/extract_votes_job_test.rb`
  - Add regression proving a repaired/reconciled structured child item remains the target for motion linking.

### Task 1: Lock in normal-rerun safety tests first

**Files:**
- Modify: `test/jobs/scrapers/parse_agenda_job_test.rb`
- Create: `test/services/agendas/reconcile_items_test.rb`

- [ ] **Step 1: Write the failing rerun regression in `test/jobs/scrapers/parse_agenda_job_test.rb`**

```ruby
test "rerunning parse preserves agenda item ids when downstream references exist" do
  meeting = Meeting.create!(
    body_name: "Plan Commission Meeting",
    meeting_type: "Regular",
    starts_at: Time.current,
    status: "parsed",
    detail_page_url: "http://example.com/reconcile-test"
  )

  section = meeting.agenda_items.create!(number: "3.", title: "ACTION ITEMS", kind: "section", order_index: 1)
  item = meeting.agenda_items.create!(number: "A.", title: "Harbor Resolution", kind: "item", parent: section, order_index: 2)

  topic = Topic.create!(name: "Harbor")
  AgendaItemTopic.create!(agenda_item: item, topic: topic)
  TopicAppearance.create!(
    topic: topic,
    meeting: meeting,
    agenda_item: item,
    evidence_type: "agenda_item",
    appeared_at: meeting.starts_at
  )

  meeting.meeting_documents.create!(
    document_type: "agenda_pdf",
    extracted_text: "3. ACTION ITEMS A. Harbor Resolution - Action Recommended Approve resolution"
  )

  original_id = item.id

  assert_enqueued_with(job: ExtractTopicsJob, args: [ meeting.id ]) do
    Scrapers::ParseAgendaJob.perform_now(meeting.id)
  end

  assert_equal original_id, meeting.agenda_items.find_by(number: "A.")&.id
  assert_equal original_id, TopicAppearance.find_by(topic: topic, meeting: meeting)&.agenda_item_id
end
```

- [ ] **Step 2: Write the failing ambiguity-abort regression in `test/jobs/scrapers/parse_agenda_job_test.rb`**

```ruby
test "rerun aborts safely when parsed child could match multiple substantive rows" do
  meeting = Meeting.create!(
    body_name: "Library Board Meeting",
    meeting_type: "Regular",
    starts_at: Time.current,
    status: "parsed",
    detail_page_url: "http://example.com/ambiguous-rerun"
  )

  meeting.agenda_items.create!(number: "A.", title: "Resolution", kind: "item", order_index: 1)
  meeting.agenda_items.create!(number: "A.", title: "Resolution", kind: "item", order_index: 2)
  meeting.meeting_documents.create!(document_type: "agenda_pdf", extracted_text: "5. NEW BUSINESS A. Resolution")

  snapshot = meeting.agenda_items.order(:id).pluck(:id, :number, :title, :kind, :parent_id, :order_index)

  assert_raises(Agendas::ReconcileItems::AmbiguousMatchError) do
    Scrapers::ParseAgendaJob.perform_now(meeting.id)
  end

  assert_equal snapshot, meeting.agenda_items.reload.order(:id).pluck(:id, :number, :title, :kind, :parent_id, :order_index)
end
```

- [ ] **Step 3: Write the failing digest no-op regression in `test/jobs/scrapers/parse_agenda_job_test.rb`**

```ruby
test "rerun is a no-op when parsed agenda structure digest is unchanged" do
  meeting = Meeting.create!(
    body_name: "Committee On Aging",
    meeting_type: "Regular",
    starts_at: Time.current,
    status: "parsed",
    detail_page_url: "http://example.com/digest-rerun",
    agenda_structure_digest: "existing-digest"
  )

  meeting.meeting_documents.create!(document_type: "agenda_pdf", extracted_text: "1. CALL TO ORDER")

  Agendas::ReconcileItems.stub :digest_for_candidates, "existing-digest" do
    Agendas::ReconcileItems.stub :new, ->(*) { flunk "reconciler should not run when digest is unchanged" } do
      Scrapers::ParseAgendaJob.perform_now(meeting.id)
    end
  end
end
```

- [ ] **Step 4: Write focused service tests in `test/services/agendas/reconcile_items_test.rb`**

```ruby
require "test_helper"

class Agendas::ReconcileItemsTest < ActiveSupport::TestCase
  test "updates matched rows in place and preserves ids" do
    meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: Time.current, status: "parsed", detail_page_url: "http://example.com/reconcile-service")
    parent = meeting.agenda_items.create!(number: "7.", title: "ACTION ITEMS", kind: "section", order_index: 1)
    child = meeting.agenda_items.create!(number: "A.", title: "Old Harbor Title", kind: "item", parent: parent, order_index: 2)

    candidates = [
      { number: "7.", title: "ACTION ITEMS", kind: "section", parent_key: nil, order_index: 1, summary: nil, recommended_action: nil },
      { number: "A.", title: "Harbor Resolution", kind: "item", parent_key: "7.:ACTION ITEMS", order_index: 2, summary: nil, recommended_action: "Approve resolution" }
    ]

    Agendas::ReconcileItems.new(meeting: meeting, candidates: candidates).call

    assert_equal child.id, meeting.agenda_items.find_by(number: "A.")&.id
    assert_equal "Harbor Resolution", child.reload.title
    assert_equal "Approve resolution", child.recommended_action
  end
end
```

- [ ] **Step 5: Run the new test slice to verify it fails for the right reasons**

Run:

```bash
bin/rails test test/jobs/scrapers/parse_agenda_job_test.rb test/services/agendas/reconcile_items_test.rb
```

Expected:
- failures around missing `agenda_structure_digest`
- missing `Agendas::ReconcileItems`
- current destructive rerun behavior breaking the ID-preservation assertions

- [ ] **Step 6: Commit the red tests**

```bash
git add test/jobs/scrapers/parse_agenda_job_test.rb test/services/agendas/reconcile_items_test.rb
git commit -m "test: cover safe agenda reruns"
```

### Task 2: Implement non-destructive agenda reconciliation

**Files:**
- Create: `app/services/agendas/reconcile_items.rb`
- Modify: `app/jobs/scrapers/parse_agenda_job.rb`
- Modify: `app/models/agenda_item.rb`
- Test: `test/jobs/scrapers/parse_agenda_job_test.rb`
- Test: `test/services/agendas/reconcile_items_test.rb`

- [ ] **Step 1: Create the reconciler service with matching and ambiguity errors**

```ruby
module Agendas
  class ReconcileItems
    class AmbiguousMatchError < StandardError; end

    def self.digest_for_candidates(candidates)
      Digest::SHA256.hexdigest(candidates.map { |row|
        [ row[:number], row[:title], row[:kind], row[:parent_key], row[:summary], row[:recommended_action] ].join("|")
      }.join("\n"))
    end

    def initialize(meeting:, candidates:)
      @meeting = meeting
      @candidates = candidates
    end

    def call
      existing = @meeting.agenda_items.includes(:parent, :agenda_item_documents, :agenda_item_topics, :motions).ordered.to_a
      matched_ids = {}
      created_or_updated = []

      @candidates.each do |candidate|
        match = find_match(candidate, existing, matched_ids)
        if match
          update_item!(match, candidate)
          matched_ids[match.id] = true
          created_or_updated << match
        else
          created_or_updated << create_item!(candidate, created_or_updated)
        end
      end

      :updated
    end

    private

    def find_match(candidate, existing, matched_ids)
      matches = existing.reject { |item| matched_ids[item.id] }.select { |item| candidate_matches?(item, candidate) }
      raise AmbiguousMatchError, "Ambiguous agenda item match for #{candidate[:number]} #{candidate[:title]}" if matches.many?
      matches.first
    end
  end
end
```

- [ ] **Step 2: Add normalization helpers to `AgendaItem` for stable matching**

```ruby
class AgendaItem < ApplicationRecord
  # ...existing associations/scopes...

  def normalized_number
    number.to_s.downcase.gsub(/\s+/, "").presence
  end

  def normalized_title
    title.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
  end

  def parent_match_key
    return nil if parent.blank?
    "#{parent.normalized_number}:#{parent.normalized_title}"
  end
end
```

- [ ] **Step 3: Refactor `Scrapers::ParseAgendaJob` to build candidates instead of creating rows directly**

```ruby
def perform(meeting_id)
  meeting = Meeting.find(meeting_id)
  agenda_doc = meeting.meeting_documents.find_by(document_type: "agenda_html")
  agenda_pdf_doc = meeting.meeting_documents.find_by(document_type: "agenda_pdf")

  candidates = extract_candidates(meeting: meeting, agenda_doc: agenda_doc, agenda_pdf_doc: agenda_pdf_doc)
  return if candidates.blank?

  digest = Agendas::ReconcileItems.digest_for_candidates(candidates)
  return if meeting.agenda_structure_digest == digest

  meeting.with_lock do
    Meeting.transaction do
      Agendas::ReconcileItems.new(meeting: meeting, candidates: candidates).call
      meeting.update!(agenda_structure_digest: digest)
    end
  end

  ExtractTopicsJob.perform_later(meeting_id)
end
```

- [ ] **Step 4: Convert the HTML/PDF parsing helpers to emit candidate hashes**

```ruby
def parse_pdf_agenda_text_to_candidates(text)
  current_index = 0
  candidates = []

  text.to_s.scan(SECTION_PATTERN).each do |number, body|
    body = body.to_s.squish
    child_matches = body.to_enum(:scan, CHILD_PATTERN).map { Regexp.last_match }
    title = child_matches.any? ? body[0...child_matches.first.begin(0)].to_s.squish : body
    next if title.blank?

    section_key = "#{number.to_s.downcase}:#{title.downcase.gsub(/[^a-z0-9]+/, ' ').squish}"
    candidates << {
      number: number,
      title: title,
      kind: child_matches.any? ? "section" : "item",
      parent_key: nil,
      order_index: current_index += 1,
      summary: nil,
      recommended_action: nil
    }

    child_matches.each do |match|
      sub_title, recommended_action = split_inline_recommended_action(match[2].to_s.squish)
      next if sub_title.blank?

      candidates << {
        number: match[1],
        title: sub_title,
        kind: "item",
        parent_key: section_key,
        order_index: current_index += 1,
        summary: nil,
        recommended_action: recommended_action
      }
    end
  end

  candidates
end
```

- [ ] **Step 5: Run the Task 1 slice and make sure it passes**

Run:

```bash
bin/rails test test/jobs/scrapers/parse_agenda_job_test.rb test/services/agendas/reconcile_items_test.rb
```

Expected:
- PASS for the new rerun-preservation, ambiguity, and digest cases
- existing parse-agenda regressions still PASS

- [ ] **Step 6: Commit the reconciliation implementation**

```bash
git add app/services/agendas/reconcile_items.rb app/jobs/scrapers/parse_agenda_job.rb app/models/agenda_item.rb test/jobs/scrapers/parse_agenda_job_test.rb test/services/agendas/reconcile_items_test.rb
git commit -m "feat: reconcile agenda items in place on rerun"
```

### Task 3: Add the explicit historical repair path

**Files:**
- Create: `app/services/agendas/repair_structure.rb`
- Create: `app/jobs/agendas/repair_structure_job.rb`
- Create: `test/services/agendas/repair_structure_test.rb`
- Create: `test/jobs/agendas/repair_structure_job_test.rb`

- [ ] **Step 1: Write the failing repair service test for relinking a motion and topic appearance**

```ruby
require "test_helper"

class Agendas::RepairStructureTest < ActiveSupport::TestCase
  test "relinks dependent rows from legacy flat item to structured child item" do
    meeting = Meeting.create!(body_name: "Advisory Recreation Board Meeting", meeting_type: "Regular", starts_at: Time.current, status: "parsed", detail_page_url: "http://example.com/repair-173")
    legacy_item = meeting.agenda_items.create!(number: "5.", title: "NEW BUSINESS", order_index: 1)
    motion = meeting.motions.create!(description: "Support applying for storm water grant", outcome: "passed", agenda_item: legacy_item)
    topic = Topic.create!(name: "Storm Water Grant")
    AgendaItemTopic.create!(agenda_item: legacy_item, topic: topic)
    appearance = TopicAppearance.find_by!(topic: topic, meeting: meeting, agenda_item: legacy_item)

    parsed_candidates = [
      { number: "5.", title: "NEW BUSINESS", kind: "section", parent_key: nil, order_index: 1, summary: nil, recommended_action: nil },
      { number: "b.", title: "2026/27 DNR Non-Point Source & Storm Water Grant", kind: "item", parent_key: "5.:new business", order_index: 2, summary: nil, recommended_action: "in support of City Council passing a resolution in support of applying for the grant" }
    ]

    Agendas::RepairStructure.new(meeting: meeting, candidates: parsed_candidates, remap_rules: { legacy_item.id => "b.:2026/27 dnr non point source storm water grant" }).call

    target = meeting.agenda_items.find_by(number: "b.")
    assert_equal target.id, motion.reload.agenda_item_id
    assert_equal target.id, appearance.reload.agenda_item_id
  end
end
```

- [ ] **Step 2: Write the failing job wrapper test**

```ruby
require "test_helper"

class Agendas::RepairStructureJobTest < ActiveJob::TestCase
  test "delegates to repair service for a single meeting" do
    meeting = Meeting.create!(body_name: "ARB", meeting_type: "Regular", starts_at: Time.current, status: "parsed", detail_page_url: "http://example.com/repair-job")
    called = false

    Agendas::RepairStructure.stub :new, ->(**kwargs) {
      Struct.new(:call).new(proc { called = kwargs[:meeting].id == meeting.id })
    } do
      Agendas::RepairStructureJob.perform_now(meeting.id)
    end

    assert called
  end
end
```

- [ ] **Step 3: Run the new repair-path tests to verify they fail**

Run:

```bash
bin/rails test test/services/agendas/repair_structure_test.rb test/jobs/agendas/repair_structure_job_test.rb
```

Expected:
- FAIL because `Agendas::RepairStructure` and `Agendas::RepairStructureJob` do not exist yet.

- [ ] **Step 4: Implement the repair service and job**

```ruby
module Agendas
  class RepairStructure
    def initialize(meeting:, candidates:, remap_rules:)
      @meeting = meeting
      @candidates = candidates
      @remap_rules = remap_rules
    end

    def call
      @meeting.with_lock do
        Meeting.transaction do
          Agendas::ReconcileItems.new(meeting: @meeting, candidates: @candidates).call
          remap_rules.each do |old_id, target_key|
            old_item = @meeting.agenda_items.find(old_id)
            new_item = find_target!(target_key)

            AgendaItemTopic.where(agenda_item_id: old_item.id).update_all(agenda_item_id: new_item.id)
            TopicAppearance.where(agenda_item_id: old_item.id).update_all(agenda_item_id: new_item.id)
            AgendaItemDocument.where(agenda_item_id: old_item.id).update_all(agenda_item_id: new_item.id)
            Motion.where(agenda_item_id: old_item.id).update_all(agenda_item_id: new_item.id)

            old_item.destroy! if old_item.reload.agenda_item_topics.none? && old_item.motions.none?
          end
        end
      end
    end
  end
end
```

- [ ] **Step 5: Re-run the repair tests and confirm green**

Run:

```bash
bin/rails test test/services/agendas/repair_structure_test.rb test/jobs/agendas/repair_structure_job_test.rb
```

Expected:
- PASS for both repair service and job tests.

- [ ] **Step 6: Commit the repair path**

```bash
git add app/services/agendas/repair_structure.rb app/jobs/agendas/repair_structure_job.rb test/services/agendas/repair_structure_test.rb test/jobs/agendas/repair_structure_job_test.rb
git commit -m "feat: add guarded agenda structure repair path"
```

### Task 4: Persist structure digests and cover minutes-triggered rerun safety

**Files:**
- Create: `db/migrate/20260417220000_add_agenda_structure_digest_to_meetings.rb`
- Modify: `app/models/meeting.rb`
- Modify: `test/jobs/extract_votes_job_test.rb`
- Modify: `test/jobs/scrapers/parse_agenda_job_test.rb`

- [ ] **Step 1: Write the migration test expectation inline via schema assertion in a job test**

```ruby
test "meeting stores agenda structure digest after successful parse" do
  meeting = Meeting.create!(body_name: "Public Utilities Committee Meeting", meeting_type: "Regular", starts_at: Time.current, status: "parsed", detail_page_url: "http://example.com/digest-store")
  meeting.meeting_documents.create!(document_type: "agenda_pdf", extracted_text: "1. CALL TO ORDER")

  Scrapers::ParseAgendaJob.perform_now(meeting.id)

  assert meeting.reload.agenda_structure_digest.present?
end
```

- [ ] **Step 2: Add a vote-link regression in `test/jobs/extract_votes_job_test.rb`**

```ruby
test "motion remains linked to repaired child agenda item after minutes-triggered rerun" do
  section = AgendaItem.create!(meeting: @meeting, number: "8.", title: "NEW BUSINESS", kind: "section", order_index: 10)
  child = AgendaItem.create!(meeting: @meeting, number: "B.", title: "Storm Water Grant Resolution", kind: "item", parent: section, order_index: 11)

  ai_response = {
    "motions" => [ {
      "description" => "Approve the storm water grant resolution",
      "outcome" => "passed",
      "agenda_item_ref" => "B.: Storm Water Grant Resolution",
      "votes" => []
    } ]
  }.to_json

  mock_ai = Minitest::Mock.new
  mock_ai.expect :extract_votes, ai_response do |_text, **_kwargs|
    true
  end

  Ai::OpenAiService.stub :new, mock_ai do
    ExtractVotesJob.perform_now(@meeting.id)
  end

  assert_equal child.id, @meeting.motions.reload.first.agenda_item_id
end
```

- [ ] **Step 3: Run the broader targeted slice and confirm any failures are implementation gaps only**

Run:

```bash
bin/rails test test/jobs/scrapers/parse_agenda_job_test.rb test/services/agendas/reconcile_items_test.rb test/services/agendas/repair_structure_test.rb test/jobs/agendas/repair_structure_job_test.rb test/jobs/extract_votes_job_test.rb
```

Expected:
- if anything fails, it should be due to missing migration/model support for `agenda_structure_digest` or repair-path edge cases.

- [ ] **Step 4: Add the migration and meeting support**

```ruby
class AddAgendaStructureDigestToMeetings < ActiveRecord::Migration[8.1]
  def change
    add_column :meetings, :agenda_structure_digest, :string
  end
end
```

```ruby
class Meeting < ApplicationRecord
  # existing associations...

  def agenda_structure_known?
    agenda_structure_digest.present?
  end
end
```

- [ ] **Step 5: Run migration + targeted tests until green**

Run:

```bash
bin/rails db:migrate
bin/rails test test/jobs/scrapers/parse_agenda_job_test.rb test/services/agendas/reconcile_items_test.rb test/services/agendas/repair_structure_test.rb test/jobs/agendas/repair_structure_job_test.rb test/jobs/extract_votes_job_test.rb
```

Expected:
- PASS for all targeted rerun, repair, and vote-link regressions.

- [ ] **Step 6: Commit the digest persistence and verification slice**

```bash
git add db/migrate/20260417220000_add_agenda_structure_digest_to_meetings.rb app/models/meeting.rb test/jobs/scrapers/parse_agenda_job_test.rb test/jobs/extract_votes_job_test.rb
git commit -m "feat: persist safe agenda rerun digests"
```

### Task 5: Final verification and rollout notes

**Files:**
- Modify: `docs/superpowers/specs/2026-04-17-safe-mixed-mode-agenda-reruns-design.md` (only if implementation discovers a real nuance)
- Optional external update: GitHub issue `#101`

- [ ] **Step 1: Run the final verification suite for this change set**

Run:

```bash
bin/rails test test/jobs/scrapers/parse_agenda_job_test.rb test/services/agendas/reconcile_items_test.rb test/services/agendas/repair_structure_test.rb test/jobs/agendas/repair_structure_job_test.rb test/jobs/extract_votes_job_test.rb test/jobs/documents/analyze_pdf_job_test.rb
```

Expected:
- PASS with 0 failures and 0 errors.

- [ ] **Step 2: Manually verify meeting-scoped repair behavior in Rails runner**

Run:

```bash
bin/rails runner 'meeting = Meeting.find(173); puts({motions: meeting.motions.count, items: meeting.agenda_items.count}.inspect)'
```

Expected:
- command succeeds without foreign key failure
- current data can be inspected safely before any explicit repair is invoked

- [ ] **Step 3: If implementation discovered a meaningful nuance, update the spec and issue notes**

```markdown
- add note that routine reruns are now ID-preserving and that destructive legacy repair is isolated behind `Agendas::RepairStructureJob`
```

- [ ] **Step 4: Commit the final verified implementation**

```bash
git add app/jobs/scrapers/parse_agenda_job.rb app/services/agendas/reconcile_items.rb app/services/agendas/repair_structure.rb app/jobs/agendas/repair_structure_job.rb app/models/agenda_item.rb app/models/meeting.rb db/migrate/20260417220000_add_agenda_structure_digest_to_meetings.rb test/jobs/scrapers/parse_agenda_job_test.rb test/services/agendas/reconcile_items_test.rb test/services/agendas/repair_structure_test.rb test/jobs/agendas/repair_structure_job_test.rb test/jobs/extract_votes_job_test.rb
git commit -m "fix: make mixed-mode agenda reruns safe"
```

## Self-review checklist

- Spec coverage:
  - safe normal reruns → Tasks 1, 2, 4
  - guarded historical repair path → Task 3
  - cost constraint / no blanket backfill → architecture + Task 5 only for meeting-scoped/manual verification
  - minutes-triggered rerun safety → Tasks 2 and 4
- Placeholder scan:
  - no `TODO` / `TBD` placeholders left
  - each task includes exact files, test code, commands, and expected outcomes
- Type consistency:
  - `Agendas::ReconcileItems`, `Agendas::RepairStructure`, `Agendas::RepairStructureJob`, and `agenda_structure_digest` are named consistently throughout
