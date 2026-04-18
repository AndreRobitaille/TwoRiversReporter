# Opportunistic Safe Upgrade on Rerun Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make newly arrived documents trigger a safe, meeting-scoped agenda upgrade attempt for historical meetings, while preserving already-okay meetings and failing closed on ambiguity.

**Architecture:** Reuse the new non-destructive agenda reconciliation path as the upgrade engine, then wire the rerun entry points that matter for late-arriving documents so they invoke that safe path only when a meeting is being reanalyzed. Add regression coverage proving legacy-flat meetings survive reruns, upgrade when safe, and remain unchanged when matching is ambiguous.

**Tech Stack:** Ruby on Rails, ActiveJob, ActiveRecord, Minitest, PostgreSQL.

---

## File map

- **Modify:** `app/jobs/documents/analyze_pdf_job.rb`
  - Wire rerun-capable document paths so old meetings with new source material attempt safe agenda upgrade.
- **Modify:** `app/jobs/scrapers/parse_agenda_job.rb`
  - Preserve current reconciliation behavior while making rerun intent explicit and side effects safe.
- **Modify:** `app/services/agendas/reconcile_items.rb`
  - Keep matching conservative for opportunistic upgrade of legacy-flat meetings.
- **Modify:** `test/jobs/documents/analyze_pdf_job_test.rb`
  - Cover trigger behavior for new-document reruns.
- **Modify:** `test/jobs/scrapers/parse_agenda_job_test.rb`
  - Cover safe upgrade success/fail-closed behavior on legacy meetings.
- **Modify:** `test/jobs/extract_votes_job_test.rb`
  - Cover end-to-end behavior that vote extraction still binds correctly after safe upgrade on rerun.
- **Optional docs update after verification:** GitHub issue `#101`

### Task 1: Add rerun-trigger regression tests first

**Files:**
- Modify: `test/jobs/documents/analyze_pdf_job_test.rb`
- Modify: `test/jobs/scrapers/parse_agenda_job_test.rb`
- Modify: `test/jobs/extract_votes_job_test.rb`

- [ ] **Step 1: Write the failing minutes-trigger trigger test**

```ruby
test "enqueues ParseAgendaJob when document_type is minutes_pdf and agenda already exists" do
  doc = MeetingDocument.create!(
    meeting: @meeting,
    document_type: "minutes_pdf"
  )
  @meeting.meeting_documents.create!(
    document_type: "agenda_pdf",
    extracted_text: "5. NEW BUSINESS b. Storm Water Grant Resolution"
  )
  doc.file.attach(
    io: StringIO.new("%PDF-1.0 minimal"),
    filename: "minutes.pdf",
    content_type: "application/pdf"
  )

  pdfinfo_output = "Pages: 1\n"
  pdftotext_output = ("minutes text " * 30).strip

  Open3.stub :capture2e, [ pdfinfo_output, OpenStruct.new(success?: true) ] do
    Open3.stub :capture3, [ pdftotext_output, "", OpenStruct.new(success?: true) ] do
      assert_enqueued_with(job: Scrapers::ParseAgendaJob, args: [ @meeting.id ]) do
        Documents::AnalyzePdfJob.perform_now(doc.id)
      end
    end
  end
end
```

- [ ] **Step 2: Write the failing safe-upgrade-on-rerun test for a legacy-flat meeting**

```ruby
test "legacy flat meeting upgrades to structured rows on rerun when match is safe" do
  meeting = Meeting.create!(
    body_name: "Advisory Recreation Board Meeting",
    meeting_type: "Regular",
    starts_at: Time.current,
    status: "parsed",
    detail_page_url: "http://example.com/legacy-upgrade-safe"
  )

  legacy_item = meeting.agenda_items.create!(
    number: "b.",
    title: "2026/27 DNR Non-Point Source & Storm Water Grant",
    order_index: 1
  )
  motion = meeting.motions.create!(
    agenda_item: legacy_item,
    description: "Motion to support applying for the grant",
    outcome: "passed"
  )
  meeting.meeting_documents.create!(
    document_type: "agenda_pdf",
    extracted_text: "5. NEW BUSINESS b. 2026/27 DNR Non-Point Source & Storm Water Grant - Action recommended in support of City Council passing a resolution in support of applying for the grant"
  )

  Scrapers::ParseAgendaJob.perform_now(meeting.id)
  meeting.reload

  section = meeting.agenda_items.find_by(number: "5.")
  child = meeting.agenda_items.find_by(number: "b.")

  assert_equal legacy_item.id, child.id
  assert_equal "section", section.kind
  assert_equal "item", child.kind
  assert_equal section.id, child.parent_id
  assert_equal legacy_item.id, motion.reload.agenda_item_id
end
```

- [ ] **Step 3: Write the failing fail-closed rerun test for an ambiguous legacy meeting**

```ruby
test "legacy meeting remains unchanged on rerun when upgrade is ambiguous" do
  meeting = Meeting.create!(
    body_name: "Library Board Meeting",
    meeting_type: "Regular",
    starts_at: Time.current,
    status: "parsed",
    detail_page_url: "http://example.com/legacy-upgrade-ambiguous"
  )

  meeting.agenda_items.create!(number: "A.", title: "Resolution", order_index: 1)
  meeting.agenda_items.create!(number: "A.", title: "Resolution", order_index: 2)
  meeting.meeting_documents.create!(document_type: "agenda_pdf", extracted_text: "5. NEW BUSINESS A. Resolution")

  snapshot = meeting.agenda_items.order(:id).pluck(:id, :number, :title, :kind, :parent_id, :order_index)

  assert_raises(Agendas::ReconcileItems::AmbiguousMatchError) do
    Scrapers::ParseAgendaJob.perform_now(meeting.id)
  end

  assert_equal snapshot, meeting.agenda_items.reload.order(:id).pluck(:id, :number, :title, :kind, :parent_id, :order_index)
end
```

- [ ] **Step 4: Write the failing end-to-end vote-link regression after safe upgrade**

```ruby
test "vote extraction still links to upgraded legacy child item after rerun" do
  section = AgendaItem.create!(meeting: @meeting, number: "8.", title: "NEW BUSINESS", kind: "section", order_index: 10)
  child = AgendaItem.create!(meeting: @meeting, number: "B.", title: "Storm Water Grant Resolution", kind: nil, order_index: 11)
  child.update!(parent: section, kind: "item")

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

- [ ] **Step 5: Run the regression slice to confirm red failures**

Run:

```bash
bin/rails test test/jobs/documents/analyze_pdf_job_test.rb test/jobs/scrapers/parse_agenda_job_test.rb test/jobs/extract_votes_job_test.rb
```

Expected:
- failing assertions around the new minutes-trigger rerun hook
- failing legacy upgrade assertions if the rerun path does not yet opportunistically upgrade the meeting

- [ ] **Step 6: Commit the red tests**

```bash
git add test/jobs/documents/analyze_pdf_job_test.rb test/jobs/scrapers/parse_agenda_job_test.rb test/jobs/extract_votes_job_test.rb
git commit -m "test: cover opportunistic rerun upgrades"
```

### Task 2: Wire rerun triggers for newly arrived documents

**Files:**
- Modify: `app/jobs/documents/analyze_pdf_job.rb`
- Test: `test/jobs/documents/analyze_pdf_job_test.rb`

- [ ] **Step 1: Implement the minimal rerun hook for late-arriving minutes/transcripts when an agenda exists**

```ruby
if document.document_type == "minutes_pdf"
  ExtractVotesJob.perform_later(document.meeting_id)
  ExtractCommitteeMembersJob.perform_later(document.meeting_id)
  ExtractTopicsJob.perform_later(document.meeting_id)
  Scrapers::ParseAgendaJob.perform_later(document.meeting_id) if document.meeting.meeting_documents.exists?(document_type: "agenda_pdf")
  SummarizeMeetingJob.set(wait: 10.minutes).perform_later(document.meeting_id)
end
```

- [ ] **Step 2: Run the focused trigger tests**

Run:

```bash
bin/rails test test/jobs/documents/analyze_pdf_job_test.rb
```

Expected:
- PASS for the new enqueue assertion and existing PDF-analysis tests

- [ ] **Step 3: Commit the trigger wiring**

```bash
git add app/jobs/documents/analyze_pdf_job.rb test/jobs/documents/analyze_pdf_job_test.rb
git commit -m "feat: rerun agenda parsing when new minutes arrive"
```

### Task 3: Make legacy-flat meetings upgrade safely on rerun

**Files:**
- Modify: `app/services/agendas/reconcile_items.rb`
- Modify: `app/jobs/scrapers/parse_agenda_job.rb`
- Test: `test/jobs/scrapers/parse_agenda_job_test.rb`

- [ ] **Step 1: Extend the reconciler to convert safe legacy-flat matches into structured rows in place**

```ruby
def find_matching_items(candidate, parent_id)
  kind = candidate[:kind].presence || "item"
  scope = meeting.agenda_items.where(number: candidate[:number])

  scope = if kind == "item"
    scope.where(kind: [nil, "item"])
  else
    scope.where(kind: [nil, "section"])
  end

  same_parent = scope.where(parent_id: parent_id)
  return same_parent if same_parent.one?

  exact = scope.where(title: candidate[:title], parent_id: parent_id)
  return exact if exact.one?

  ordered = exact.where(order_index: candidate[:order_index])
  return ordered if ordered.one?

  scope.none?
end
```

- [ ] **Step 2: Keep fail-closed behavior explicit in the parse job**

```ruby
def reconcile_candidates(meeting, candidates)
  # existing digest + lock logic...
rescue Agendas::ReconcileItems::AmbiguousMatchError
  Rails.logger.warn("Ambiguous agenda upgrade for Meeting #{meeting.id}; preserving existing agenda state")
  raise
end
```

- [ ] **Step 3: Run the parse-job regression slice**

Run:

```bash
bin/rails test test/jobs/scrapers/parse_agenda_job_test.rb test/services/agendas/reconcile_items_test.rb
```

Expected:
- PASS for safe legacy upgrade, ambiguity fail-closed, digest persistence/no-op, and existing HTML/PDF parser regressions

- [ ] **Step 4: Commit the safe-upgrade reconciliation changes**

```bash
git add app/services/agendas/reconcile_items.rb app/jobs/scrapers/parse_agenda_job.rb test/jobs/scrapers/parse_agenda_job_test.rb test/services/agendas/reconcile_items_test.rb
git commit -m "feat: upgrade legacy agenda rows safely on rerun"
```

### Task 4: Verify downstream extraction still works after rerun upgrade

**Files:**
- Modify: `test/jobs/extract_votes_job_test.rb`

- [ ] **Step 1: Implement the vote-link regression if still failing**

```ruby
test "vote extraction still links to upgraded legacy child item after rerun" do
  # use upgraded structured child row and assert the motion binds to the preserved id
end
```

- [ ] **Step 2: Run the focused vote slice**

Run:

```bash
bin/rails test test/jobs/extract_votes_job_test.rb
```

Expected:
- PASS for existing section/child vote resolution tests and the new rerun-upgrade regression

- [ ] **Step 3: Commit the downstream verification coverage**

```bash
git add test/jobs/extract_votes_job_test.rb
git commit -m "test: verify vote links survive rerun upgrades"
```

### Task 5: Final verification and debt-note update

**Files:**
- Optional docs update: GitHub issue `#101`

- [ ] **Step 1: Run the final related verification slice**

Run:

```bash
bin/rails test test/jobs/documents/analyze_pdf_job_test.rb test/services/agendas/reconcile_items_test.rb test/jobs/scrapers/parse_agenda_job_test.rb test/jobs/extract_votes_job_test.rb
```

Expected:
- PASS with 0 failures and 0 errors

- [ ] **Step 2: Sanity-check a representative historical meeting in Rails runner**

Run:

```bash
bin/rails runner 'meeting = Meeting.find(173); puts({items: meeting.agenda_items.count, motions: meeting.motions.count, docs: meeting.meeting_documents.pluck(:document_type)}.inspect)'
```

Expected:
- command succeeds
- current state can be inspected safely before any deliberate rerun/repair

- [ ] **Step 3: Update GitHub issue #101 with the remaining debt boundaries**

Add notes summarizing:

```markdown
- Historical meetings are now protected from destructive reruns when new source documents arrive.
- Safe opportunistic upgrade on rerun is supported meeting-by-meeting.
- Historical meetings that never rerun may remain legacy indefinitely.
- Full historical normalization is still deferred and separate from this protection path.
```

- [ ] **Step 4: Commit the final implementation**

```bash
git add app/jobs/documents/analyze_pdf_job.rb app/jobs/scrapers/parse_agenda_job.rb app/services/agendas/reconcile_items.rb test/jobs/documents/analyze_pdf_job_test.rb test/jobs/scrapers/parse_agenda_job_test.rb test/jobs/extract_votes_job_test.rb
git commit -m "fix: protect historical meetings during reruns"
```

## Self-review checklist

- Spec coverage:
  - protect historical meetings from rerun damage → Tasks 2, 3, 4
  - opportunistic meeting-scoped upgrade only on rerun → Tasks 1, 2, 3
  - fail closed on ambiguity → Tasks 1, 3
  - no global cleanup/backfill → reflected in scope and lack of blanket migration tasks
  - update issue #101 after success → Task 5
- Placeholder scan:
  - no `TODO` / `TBD` placeholders
  - each task has exact files, commands, and expected results
- Type consistency:
  - `Agendas::ReconcileItems`, `Scrapers::ParseAgendaJob`, and `agenda_structure_digest` are named consistently throughout
