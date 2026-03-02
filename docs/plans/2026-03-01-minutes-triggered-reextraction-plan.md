# Minutes-Triggered Topic Re-Extraction — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Trigger `ExtractTopicsJob` when meeting minutes arrive, and
prioritize minutes text over packet text as AI context for topic
extraction.

**Architecture:** Two small changes. (1) Add a one-line job trigger in
`AnalyzePdfJob` so minutes arrival enqueues `ExtractTopicsJob`. (2)
Rewrite `ExtractTopicsJob#build_meeting_document_context` to prefer
minutes over packet and raise the minutes truncation limit to 25K.

**Tech Stack:** Rails jobs, Minitest, existing `ExtractTopicsJob` /
`AnalyzePdfJob` infrastructure.

**Design doc:**
`docs/plans/2026-03-01-minutes-triggered-reextraction-design.md`

---

### Task 1: Test that `build_meeting_document_context` prefers minutes over packet

**Files:**
- Test: `test/jobs/extract_topics_job_test.rb`

**Context:** `ExtractTopicsJob#build_meeting_document_context` currently
includes both `packet_pdf` and `minutes_pdf` text indiscriminately
(each truncated to 8K). We need it to prefer minutes when available
and skip packet text.

See existing test `"includes meeting-level packet text as context"`
(line 164) for the pattern: create a meeting + agenda item + unlinked
document, stub the AI service, and assert the `meeting_documents_context`
kwarg contents.

**Step 1: Write the failing test**

Add this test to `test/jobs/extract_topics_job_test.rb`:

```ruby
test "prefers minutes over packet in meeting document context" do
  meeting = Meeting.create!(
    body_name: "City Council", meeting_type: "Regular",
    starts_at: 1.day.from_now, status: "agenda_posted",
    detail_page_url: "http://example.com/m/minutes-pref"
  )
  item = AgendaItem.create!(meeting: meeting, number: "1", title: "Budget Discussion", order_index: 1)

  # Both packet and minutes exist — minutes should win
  MeetingDocument.create!(
    meeting: meeting, document_type: "packet_pdf",
    extracted_text: "PACKET_MARKER consent agenda embedded committee minutes financial reports"
  )
  MeetingDocument.create!(
    meeting: meeting, document_type: "minutes_pdf",
    extracted_text: "MINUTES_MARKER council discussed budget and voted to approve"
  )

  captured_kwargs = nil
  ai_response = {
    "items" => [ {
      "id" => item.id,
      "category" => "Finance",
      "tags" => [ "city budget" ],
      "topic_worthy" => true,
      "confidence" => 0.85
    } ]
  }.to_json

  mock_ai = Minitest::Mock.new
  mock_ai.expect :extract_topics, ai_response do |text, **kwargs|
    captured_kwargs = kwargs
    true
  end

  retrieval_stub = Object.new
  def retrieval_stub.retrieve_context(*args, **kwargs); []; end
  def retrieval_stub.format_context(*args); ""; end

  RetrievalService.stub :new, retrieval_stub do
    Ai::OpenAiService.stub :new, mock_ai do
      ExtractTopicsJob.perform_now(meeting.id)
    end
  end

  # Minutes should be included, packet should NOT
  assert_includes captured_kwargs[:meeting_documents_context], "MINUTES_MARKER"
  refute_includes captured_kwargs[:meeting_documents_context], "PACKET_MARKER"
  mock_ai.verify
end
```

**Step 2: Run the test to verify it fails**

Run: `bin/rails test test/jobs/extract_topics_job_test.rb -n "/prefers minutes/"`

Expected: FAIL — `PACKET_MARKER` will be present in context because
current code includes both documents.

**Step 3: Implement `build_meeting_document_context` change**

In `app/jobs/extract_topics_job.rb`, replace the
`build_meeting_document_context` method (lines 163–180):

```ruby
def build_meeting_document_context(meeting, items)
  # Find document IDs already linked to specific agenda items
  linked_doc_ids = AgendaItemDocument
    .where(agenda_item_id: items.map(&:id))
    .pluck(:meeting_document_id)

  # Prefer minutes over packet — minutes are authoritative and clean.
  # Packet text (especially for council) contains consent agenda noise
  # (embedded committee minutes, financial reports, check registers).
  minutes_doc = meeting.meeting_documents
    .where(document_type: "minutes_pdf")
    .where.not(id: linked_doc_ids)
    .where.not(extracted_text: [nil, ""])
    .first

  if minutes_doc
    return "minutes_pdf: #{minutes_doc.extracted_text.truncate(25_000, separator: ' ')}"
  end

  # Fall back to packet if no minutes
  packet_doc = meeting.meeting_documents
    .where(document_type: "packet_pdf")
    .where.not(id: linked_doc_ids)
    .where.not(extracted_text: [nil, ""])
    .first

  if packet_doc
    return "packet_pdf: #{packet_doc.extracted_text.truncate(8_000, separator: ' ')}"
  end

  ""
end
```

**Step 4: Run the test to verify it passes**

Run: `bin/rails test test/jobs/extract_topics_job_test.rb -n "/prefers minutes/"`

Expected: PASS

**Step 5: Run the full test file to check for regressions**

Run: `bin/rails test test/jobs/extract_topics_job_test.rb`

Expected: All tests pass. The existing `"includes meeting-level packet
text as context"` test (line 164) should still pass because it creates
only a `packet_pdf` (no minutes), so the fallback path runs.

**Step 6: Commit**

```bash
git add test/jobs/extract_topics_job_test.rb app/jobs/extract_topics_job.rb
git commit -m "feat: prefer minutes over packet text in topic extraction context

When both minutes and packet PDFs exist, use minutes as the document
context for topic extraction (25K limit). Skip noisy packet text
which contains embedded committee minutes and financial reports.
Falls back to packet (8K limit) when no minutes available."
```

---

### Task 2: Test that minutes text gets full 25K budget

**Files:**
- Test: `test/jobs/extract_topics_job_test.rb`

**Context:** The old code truncated all documents to 8K. Minutes can
be up to 23K chars (Advisory Rec Board). Verify the 25K limit works.

**Step 1: Write the failing test**

```ruby
test "minutes text uses 25K truncation limit" do
  meeting = Meeting.create!(
    body_name: "Advisory Recreation Board", meeting_type: "Regular",
    starts_at: 1.day.from_now, status: "agenda_posted",
    detail_page_url: "http://example.com/m/minutes-25k"
  )
  item = AgendaItem.create!(meeting: meeting, number: "1", title: "Parks Discussion", order_index: 1)

  # Create minutes text that's 15K chars — above old 8K limit
  long_minutes = "MINUTES_START " + ("discussion about park improvements. " * 400) + " MINUTES_END"
  MeetingDocument.create!(
    meeting: meeting, document_type: "minutes_pdf",
    extracted_text: long_minutes
  )

  captured_kwargs = nil
  ai_response = {
    "items" => [ {
      "id" => item.id,
      "category" => "Recreation",
      "tags" => [ "park improvements" ],
      "topic_worthy" => true,
      "confidence" => 0.8
    } ]
  }.to_json

  mock_ai = Minitest::Mock.new
  mock_ai.expect :extract_topics, ai_response do |text, **kwargs|
    captured_kwargs = kwargs
    true
  end

  retrieval_stub = Object.new
  def retrieval_stub.retrieve_context(*args, **kwargs); []; end
  def retrieval_stub.format_context(*args); ""; end

  RetrievalService.stub :new, retrieval_stub do
    Ai::OpenAiService.stub :new, mock_ai do
      ExtractTopicsJob.perform_now(meeting.id)
    end
  end

  # Should include text beyond the old 8K limit
  assert_includes captured_kwargs[:meeting_documents_context], "MINUTES_START"
  assert_includes captured_kwargs[:meeting_documents_context], "MINUTES_END"
  assert captured_kwargs[:meeting_documents_context].length > 8000
  mock_ai.verify
end
```

**Step 2: Run the test to verify it passes**

Run: `bin/rails test test/jobs/extract_topics_job_test.rb -n "/25K truncation/"`

Expected: PASS — Task 1 already implemented the 25K limit. This test
verifies the limit works for longer minutes. If it fails, check that
`truncate(25_000)` was applied correctly.

**Step 3: Commit**

```bash
git add test/jobs/extract_topics_job_test.rb
git commit -m "test: verify minutes text uses 25K truncation limit"
```

---

### Task 3: Test that `AnalyzePdfJob` triggers `ExtractTopicsJob` for minutes

**Files:**
- Create: `test/jobs/documents/analyze_pdf_job_test.rb`
- Modify: `app/jobs/documents/analyze_pdf_job.rb`

**Context:** `AnalyzePdfJob` already triggers `SummarizeMeetingJob`,
`ExtractVotesJob`, and `ExtractCommitteeMembersJob` when processing
minutes. We need to add `ExtractTopicsJob` to that list.

Note: There is no existing test file for `AnalyzePdfJob`. The job
requires real PDF files and `pdftotext`/`pdfinfo` binaries, so tests
must stub file operations or focus on the trigger logic.

**Step 1: Write the failing test**

Create `test/jobs/documents/analyze_pdf_job_test.rb`:

```ruby
require "test_helper"

module Documents
  class AnalyzePdfJobTest < ActiveJob::TestCase
    test "triggers ExtractTopicsJob when processing minutes_pdf" do
      meeting = Meeting.create!(
        body_name: "Public Works Committee", meeting_type: "Regular",
        starts_at: 1.week.ago, status: "held",
        detail_page_url: "http://example.com/m/analyze-test"
      )
      doc = MeetingDocument.create!(
        meeting: meeting,
        document_type: "minutes_pdf"
      )

      # Create a minimal valid PDF in memory
      pdf_content = create_minimal_pdf("Test minutes content for extraction")
      doc.file.attach(io: StringIO.new(pdf_content), filename: "minutes.pdf", content_type: "application/pdf")

      assert_enqueued_with(job: ExtractTopicsJob, args: [meeting.id]) do
        perform_enqueued_jobs(only: Documents::AnalyzePdfJob) do
          Documents::AnalyzePdfJob.perform_later(doc.id)
        end
      end
    end

    test "does not trigger ExtractTopicsJob for agenda_pdf" do
      meeting = Meeting.create!(
        body_name: "Public Works Committee", meeting_type: "Regular",
        starts_at: 1.week.ago, status: "held",
        detail_page_url: "http://example.com/m/analyze-test-2"
      )
      doc = MeetingDocument.create!(
        meeting: meeting,
        document_type: "agenda_pdf"
      )

      pdf_content = create_minimal_pdf("Test agenda content")
      doc.file.attach(io: StringIO.new(pdf_content), filename: "agenda.pdf", content_type: "application/pdf")

      # Should NOT enqueue ExtractTopicsJob for agenda documents
      perform_enqueued_jobs(only: Documents::AnalyzePdfJob) do
        Documents::AnalyzePdfJob.perform_later(doc.id)
      end

      refute_enqueued_jobs(only: ExtractTopicsJob)
    end

    private

    def create_minimal_pdf(text)
      # Minimal valid PDF with text content
      # pdftotext can extract text from this format
      content_stream = text
      <<~PDF
        %PDF-1.0
        1 0 obj
        << /Type /Catalog /Pages 2 0 R >>
        endobj
        2 0 obj
        << /Type /Pages /Kids [3 0 R] /Count 1 >>
        endobj
        3 0 obj
        << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792]
           /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>
        endobj
        4 0 obj
        << /Length #{content_stream.length + 30} >>
        stream
        BT /F1 12 Tf 100 700 Td (#{content_stream}) Tj ET
        endstream
        endobj
        5 0 obj
        << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>
        endobj
        xref
        0 6
        trailer << /Size 6 /Root 1 0 R >>
        startxref
        0
        %%EOF
      PDF
    end
  end
end
```

**Step 2: Run the test to verify it fails**

Run: `bin/rails test test/jobs/documents/analyze_pdf_job_test.rb -n "/triggers ExtractTopicsJob/"`

Expected: FAIL — `ExtractTopicsJob` is not yet triggered.

Note: If the test has trouble with the minimal PDF and `pdftotext`,
we may need to adjust the PDF helper or stub the file operations.
The important thing to verify is the enqueueing behavior.

**Step 3: Add the trigger to `AnalyzePdfJob`**

In `app/jobs/documents/analyze_pdf_job.rb`, add `ExtractTopicsJob`
to the minutes block (line 93):

```ruby
# Trigger Vote and Membership Extraction for minutes
if document.document_type == "minutes_pdf"
  ExtractVotesJob.perform_later(document.meeting_id)
  ExtractCommitteeMembersJob.perform_later(document.meeting_id)
  ExtractTopicsJob.perform_later(document.meeting_id)
end
```

**Step 4: Run the test to verify it passes**

Run: `bin/rails test test/jobs/documents/analyze_pdf_job_test.rb`

Expected: Both tests pass.

**Step 5: Run the full test suite to check for regressions**

Run: `bin/rails test`

Expected: All tests pass.

**Step 6: Commit**

```bash
git add test/jobs/documents/analyze_pdf_job_test.rb app/jobs/documents/analyze_pdf_job.rb
git commit -m "feat: trigger topic re-extraction when minutes PDF arrives

AnalyzePdfJob now enqueues ExtractTopicsJob alongside the existing
ExtractVotesJob and ExtractCommitteeMembersJob when processing
minutes_pdf documents. This means meetings get a second pass at
topic extraction with the richer minutes content."
```

---

### Task 4: Test packet-only fallback still works

**Files:**
- Test: `test/jobs/extract_topics_job_test.rb`

**Context:** The existing test `"includes meeting-level packet text as
context"` (line 164) should already cover this, but let's verify it
still passes after our changes and add an explicit fallback test.

**Step 1: Run existing packet test**

Run: `bin/rails test test/jobs/extract_topics_job_test.rb -n "/includes meeting-level packet text/"`

Expected: PASS — packet fallback path should still work.

**Step 2: Write an explicit fallback test**

```ruby
test "falls back to packet text when no minutes exist" do
  meeting = Meeting.create!(
    body_name: "City Council", meeting_type: "Regular",
    starts_at: 1.day.from_now, status: "agenda_posted",
    detail_page_url: "http://example.com/m/packet-fallback"
  )
  item = AgendaItem.create!(meeting: meeting, number: "1", title: "Zoning Request", order_index: 1)
  MeetingDocument.create!(
    meeting: meeting, document_type: "packet_pdf",
    extracted_text: "PACKET_ONLY zoning variance application details"
  )

  captured_kwargs = nil
  ai_response = {
    "items" => [ {
      "id" => item.id,
      "category" => "Zoning",
      "tags" => [ "zoning variance" ],
      "topic_worthy" => true,
      "confidence" => 0.85
    } ]
  }.to_json

  mock_ai = Minitest::Mock.new
  mock_ai.expect :extract_topics, ai_response do |text, **kwargs|
    captured_kwargs = kwargs
    true
  end

  retrieval_stub = Object.new
  def retrieval_stub.retrieve_context(*args, **kwargs); []; end
  def retrieval_stub.format_context(*args); ""; end

  RetrievalService.stub :new, retrieval_stub do
    Ai::OpenAiService.stub :new, mock_ai do
      ExtractTopicsJob.perform_now(meeting.id)
    end
  end

  assert_includes captured_kwargs[:meeting_documents_context], "PACKET_ONLY"
  assert_includes captured_kwargs[:meeting_documents_context], "packet_pdf"
  mock_ai.verify
end
```

**Step 3: Run the test**

Run: `bin/rails test test/jobs/extract_topics_job_test.rb -n "/falls back to packet/"`

Expected: PASS

**Step 4: Run the full test suite**

Run: `bin/rails test`

Expected: All tests pass.

**Step 5: Commit**

```bash
git add test/jobs/extract_topics_job_test.rb
git commit -m "test: verify packet fallback when no minutes exist"
```

---

### Task 5: Also update `gather_item_document_text` to prefer minutes

**Files:**
- Modify: `app/jobs/extract_topics_job.rb`
- Test: `test/jobs/extract_topics_job_test.rb`

**Context:** `gather_item_document_text` (used by the catch-all topic
refinement pass 2) also includes meeting-level `packet_pdf` and
`minutes_pdf` text. Apply the same minutes-over-packet preference.

**Step 1: Write the failing test**

```ruby
test "catch-all refinement uses minutes over packet for document text" do
  meeting = Meeting.create!(
    body_name: "Zoning Board", meeting_type: "Regular",
    starts_at: 1.day.from_now, status: "agenda_posted",
    detail_page_url: "http://example.com/m/catchall-minutes"
  )
  item = AgendaItem.create!(meeting: meeting, number: "1", title: "PUBLIC HEARING", order_index: 1)

  MeetingDocument.create!(
    meeting: meeting, document_type: "packet_pdf",
    extracted_text: "PACKET_NOISE consent agenda financial reports"
  )
  MeetingDocument.create!(
    meeting: meeting, document_type: "minutes_pdf",
    extracted_text: "MINUTES_CONTENT appeal to construct commercial structure at 456 Oak Ave"
  )

  catchall_topic = Topic.create!(name: "height and area exceptions", status: :approved, review_status: :approved)

  extract_response = {
    "items" => [ {
      "id" => item.id,
      "category" => "Zoning",
      "tags" => [ "height and area exceptions" ],
      "topic_worthy" => true,
      "confidence" => 0.8
    } ]
  }.to_json

  captured_refine_kwargs = nil
  refine_response = { "action" => "replace", "topic_name" => "commercial zoning appeal" }.to_json

  mock_ai = Minitest::Mock.new
  mock_ai.expect :extract_topics, extract_response do |text, **kwargs|
    true
  end
  mock_ai.expect :refine_catchall_topic, refine_response do |**kwargs|
    captured_refine_kwargs = kwargs
    true
  end

  retrieval_stub = Object.new
  def retrieval_stub.retrieve_context(*args, **kwargs); []; end
  def retrieval_stub.format_context(*args); ""; end

  RetrievalService.stub :new, retrieval_stub do
    Ai::OpenAiService.stub :new, mock_ai do
      ExtractTopicsJob.perform_now(meeting.id)
    end
  end

  assert_includes captured_refine_kwargs[:document_text], "MINUTES_CONTENT"
  refute_includes captured_refine_kwargs[:document_text], "PACKET_NOISE"
  mock_ai.verify
end
```

**Step 2: Run the test to verify it fails**

Run: `bin/rails test test/jobs/extract_topics_job_test.rb -n "/catch-all refinement uses minutes/"`

Expected: FAIL — current code includes both packet and minutes.

**Step 3: Update `gather_item_document_text`**

In `app/jobs/extract_topics_job.rb`, replace the
`gather_item_document_text` method (lines 145–161):

```ruby
def gather_item_document_text(item, meeting)
  parts = []

  # Item-linked documents
  item.meeting_documents.each do |doc|
    next if doc.extracted_text.blank?
    parts << doc.extracted_text.truncate(2000, separator: " ")
  end

  # Meeting-level context: prefer minutes over packet
  minutes_doc = meeting.meeting_documents
    .find_by(document_type: "minutes_pdf")
  if minutes_doc&.extracted_text.present?
    parts << minutes_doc.extracted_text.truncate(4000, separator: " ")
  else
    meeting.meeting_documents.where(document_type: "packet_pdf").each do |doc|
      next if doc.extracted_text.blank?
      parts << doc.extracted_text.truncate(4000, separator: " ")
    end
  end

  parts.join("\n---\n")
end
```

**Step 4: Run the test to verify it passes**

Run: `bin/rails test test/jobs/extract_topics_job_test.rb -n "/catch-all refinement uses minutes/"`

Expected: PASS

**Step 5: Run all extract_topics_job tests**

Run: `bin/rails test test/jobs/extract_topics_job_test.rb`

Expected: All tests pass, including the existing catch-all tests.

**Step 6: Commit**

```bash
git add app/jobs/extract_topics_job.rb test/jobs/extract_topics_job_test.rb
git commit -m "feat: prefer minutes over packet in catch-all refinement context

gather_item_document_text now uses minutes text when available,
skipping packet text. Consistent with build_meeting_document_context."
```

---

### Task 6: Run full test suite and CI

**Step 1: Run the full test suite**

Run: `bin/rails test`

Expected: All tests pass.

**Step 2: Run CI checks**

Run: `bin/ci`

Expected: All checks pass (rubocop, bundler-audit, brakeman).

**Step 3: Fix any issues found, then commit fixes**

---

### Task 7: Update documentation

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/DEVELOPMENT_PLAN.md`

**Step 1: Update CLAUDE.md**

In the "Job Namespaces" section, update the `ExtractTopicsJob`
description to note that it now runs on both agenda parse and minutes
arrival.

In the "Architecture > Data Flow" section, add a note that minutes
arrival triggers topic re-extraction.

**Step 2: Update DEVELOPMENT_PLAN.md**

In the "Ingestion Workflow" section, add a note about the minutes
re-extraction step.

**Step 3: Commit**

```bash
git add CLAUDE.md docs/DEVELOPMENT_PLAN.md
git commit -m "docs: document minutes-triggered topic re-extraction"
```
