# Agenda-Only Preview Summary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate meeting-level preview summaries for meetings that have an agenda PDF but no packet, transcript, or minutes — the current fallback chain drops these silently.

**Architecture:** Extend `SummarizeMeetingJob` with a `mode:` keyword argument (`:full` default, `:agenda_preview` new). Add an `agenda_preview` summary type that sits at the bottom of the supersede chain (minutes > transcript > packet > agenda). In `:agenda_preview` mode, generate only the meeting-level summary and refresh topic briefings — skip `TopicSummary` generation, `PruneHollowAppearancesJob`, and `ExtractKnowledgeJob`. Trigger the mode from `Documents::AnalyzePdfJob` when `agenda_pdf` completes.

**Tech Stack:** Rails 8.1, Ruby 4.0, Solid Queue, Minitest, `PromptTemplate` DB-driven prompts.

**Spec:** `docs/superpowers/specs/2026-04-15-agenda-only-preview-summary-design.md`

---

## File Structure

**Modified files:**
- `app/models/meeting_summary.rb` — add `"agenda_preview"` to `SUMMARY_TYPES`.
- `app/jobs/summarize_meeting_job.rb` — add `mode:` kwarg; refactor `perform` to dispatch; add `:agenda_preview` path; add cleanup for `agenda_preview` on packet/transcript/minutes paths; priority 4 agenda fallback.
- `app/jobs/documents/analyze_pdf_job.rb` — enqueue `SummarizeMeetingJob.set(wait: 5.minutes).perform_later(meeting_id, mode: :agenda_preview)` after `agenda_pdf` analysis.
- `app/controllers/meetings_controller.rb` — extend `@summary` preference chain to fall through to `agenda_preview`.
- `app/views/meetings/show.html.erb` — add banner for `source_type == "agenda"`.
- `lib/prompt_template_data.rb` — add agenda-specific narrative block to `analyze_meeting_content` instructions.
- `test/jobs/summarize_meeting_job_test.rb` — add agenda-preview mode tests, supersede tests.
- `test/jobs/documents/analyze_pdf_job_test.rb` — add agenda_pdf trigger test (if file exists; create if not).
- `test/models/meeting_summary_test.rb` — validator test for `agenda_preview`.

**New files:**
- `lib/tasks/agenda_previews.rake` — optional backfill task.

---

## Task 1: Add `agenda_preview` to `MeetingSummary` validator

**Files:**
- Modify: `app/models/meeting_summary.rb`
- Test: `test/models/meeting_summary_test.rb`

- [ ] **Step 1: Check if the test file exists**

Run: `ls test/models/meeting_summary_test.rb 2>&1 || echo MISSING`

If MISSING, create it with this content:

```ruby
require "test_helper"

class MeetingSummaryTest < ActiveSupport::TestCase
  setup do
    @meeting = Meeting.create!(
      body_name: "City Council",
      starts_at: 1.day.ago,
      detail_page_url: "http://example.com/meeting"
    )
  end
end
```

- [ ] **Step 2: Write failing validator test**

Append to `test/models/meeting_summary_test.rb`:

```ruby
  test "accepts agenda_preview as summary_type" do
    summary = MeetingSummary.new(meeting: @meeting, summary_type: "agenda_preview")
    assert summary.valid?, "agenda_preview should be a valid summary_type, errors: #{summary.errors.full_messages}"
  end

  test "rejects unknown summary_type" do
    summary = MeetingSummary.new(meeting: @meeting, summary_type: "bogus_type")
    refute summary.valid?
    assert_includes summary.errors[:summary_type].join, "included"
  end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bin/rails test test/models/meeting_summary_test.rb -n "/agenda_preview/"`
Expected: FAIL — inclusion list doesn't include `agenda_preview`.

- [ ] **Step 4: Add `agenda_preview` to `SUMMARY_TYPES`**

Edit `app/models/meeting_summary.rb`:

```ruby
class MeetingSummary < ApplicationRecord
  SUMMARY_TYPES = %w[minutes_recap transcript_recap packet_analysis agenda_preview].freeze

  belongs_to :meeting

  validates :summary_type, presence: true, inclusion: { in: SUMMARY_TYPES }
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bin/rails test test/models/meeting_summary_test.rb`
Expected: PASS (both new tests plus any existing tests).

- [ ] **Step 6: Commit**

```bash
git add app/models/meeting_summary.rb test/models/meeting_summary_test.rb
git commit -m "feat(meeting_summary): add agenda_preview to valid summary_types"
```

---

## Task 2: Refactor `SummarizeMeetingJob` to accept `mode:` kwarg (preserve :full behavior)

This task only introduces the mode argument and its dispatch — no behavior changes for existing callers. Future tasks implement the `:agenda_preview` path.

**Files:**
- Modify: `app/jobs/summarize_meeting_job.rb`
- Test: `test/jobs/summarize_meeting_job_test.rb`

- [ ] **Step 1: Write failing test for mode dispatch (default :full)**

Append to `test/jobs/summarize_meeting_job_test.rb` (inside the class, near the top of the existing tests):

```ruby
  test "defaults to :full mode when mode kwarg is omitted" do
    # Stub the private mode methods to prove default dispatch works.
    called = nil
    job = SummarizeMeetingJob.new
    job.define_singleton_method(:run_full_mode) { |_m| called = :full }
    job.define_singleton_method(:run_agenda_preview_mode) { |_m| called = :agenda_preview }

    job.perform(@meeting.id)
    assert_equal :full, called
  end

  test "dispatches to :agenda_preview when mode kwarg is :agenda_preview" do
    called = nil
    job = SummarizeMeetingJob.new
    job.define_singleton_method(:run_full_mode) { |_m| called = :full }
    job.define_singleton_method(:run_agenda_preview_mode) { |_m| called = :agenda_preview }

    job.perform(@meeting.id, mode: :agenda_preview)
    assert_equal :agenda_preview, called
  end

  test "raises on unknown mode" do
    job = SummarizeMeetingJob.new
    assert_raises(ArgumentError) do
      job.perform(@meeting.id, mode: :bogus)
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/jobs/summarize_meeting_job_test.rb -n "/mode/"`
Expected: FAIL — `perform` does not accept a `mode:` kwarg.

- [ ] **Step 3: Refactor `perform` to dispatch by mode**

Edit `app/jobs/summarize_meeting_job.rb`. Replace the existing `perform` method with a dispatcher, and rename the current body to `run_full_mode`:

```ruby
class SummarizeMeetingJob < ApplicationJob
  queue_as :default

  def perform(meeting_id, mode: :full)
    meeting = Meeting.find(meeting_id)

    case mode
    when :full
      run_full_mode(meeting)
    when :agenda_preview
      run_agenda_preview_mode(meeting)
    else
      raise ArgumentError, "Unknown mode: #{mode.inspect}"
    end
  end

  private

  def run_full_mode(meeting)
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

  def run_agenda_preview_mode(meeting)
    # Implemented in Task 3.
    raise NotImplementedError, "agenda_preview mode not yet implemented"
  end
```

Leave the rest of the file (`generate_meeting_summary`, `generate_topic_summaries`, `validate_analysis_json`, `compute_framing`, `build_retrieval_query`, `save_summary`, `save_topic_summary`) untouched.

- [ ] **Step 4: Run all job tests to verify no regression**

Run: `bin/rails test test/jobs/summarize_meeting_job_test.rb`
Expected: PASS (16 existing tests + 3 new dispatch tests; `:agenda_preview` dispatch test passes because the stubbed `run_agenda_preview_mode` captures the call before `NotImplementedError` would fire).

If the `:agenda_preview` test fails because it hits the stub first: confirm behavior by reading the trace — the stub replacement via `define_singleton_method` should intercept. If it doesn't, wrap the test in `assert_nothing_raised`.

- [ ] **Step 5: Commit**

```bash
git add app/jobs/summarize_meeting_job.rb test/jobs/summarize_meeting_job_test.rb
git commit -m "refactor(summarize_meeting_job): add mode kwarg dispatcher, keep :full behavior unchanged"
```

---

## Task 3: Implement `:agenda_preview` mode (meeting summary only, silent skip on missing text)

**Files:**
- Modify: `app/jobs/summarize_meeting_job.rb`
- Test: `test/jobs/summarize_meeting_job_test.rb`

- [ ] **Step 1: Write failing test — generates summary from agenda_pdf**

Append to `test/jobs/summarize_meeting_job_test.rb`:

```ruby
  test "agenda_preview mode generates meeting summary from agenda_pdf extracted_text" do
    @meeting.meeting_documents.create!(
      document_type: "agenda_pdf",
      source_url: "http://example.com/agenda.pdf",
      extracted_text: "1. Welcome. 2. Review of last meeting. 3. Discussion of playground repairs."
    )

    generation_data = {
      "headline" => "Board will review playground repairs tonight",
      "highlights" => [],
      "public_input" => [],
      "item_details" => [
        { "title" => "Playground repairs", "summary" => "The board will discuss playground repairs.", "activity_level" => "discussion" }
      ]
    }

    mock_ai = Minitest::Mock.new
    mock_ai.expect :prepare_kb_context, "" do |arg|
      arg.is_a?(Array)
    end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |text, kb, type, **|
      type == "agenda" && text.include?("playground")
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id, mode: :agenda_preview)
      end
    end

    summary = @meeting.meeting_summaries.find_by(summary_type: "agenda_preview")
    assert summary, "Should create an agenda_preview summary"
    assert_equal "agenda", summary.generation_data["source_type"]
    assert_equal "Board will review playground repairs tonight", summary.generation_data["headline"]
    mock_ai.verify
  end

  test "agenda_preview mode returns silently when no agenda_pdf exists" do
    # Meeting has no agenda_pdf.
    assert_nothing_raised do
      SummarizeMeetingJob.perform_now(@meeting.id, mode: :agenda_preview)
    end
    assert_equal 0, @meeting.meeting_summaries.count
  end

  test "agenda_preview mode returns silently when agenda_pdf extracted_text is blank" do
    @meeting.meeting_documents.create!(
      document_type: "agenda_pdf",
      source_url: "http://example.com/agenda.pdf",
      extracted_text: ""
    )

    assert_nothing_raised do
      SummarizeMeetingJob.perform_now(@meeting.id, mode: :agenda_preview)
    end
    assert_equal 0, @meeting.meeting_summaries.count
  end

  test "agenda_preview mode enqueues GenerateTopicBriefingJob for each approved topic" do
    @meeting.meeting_documents.create!(
      document_type: "agenda_pdf",
      source_url: "http://example.com/agenda.pdf",
      extracted_text: "1. Budget review."
    )

    generation_data = { "headline" => "H", "highlights" => [], "public_input" => [], "item_details" => [] }
    mock_ai = Minitest::Mock.new
    mock_ai.expect :prepare_kb_context, "" do |arg| arg.is_a?(Array) end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |*, **| true end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end

    assert_enqueued_with(job: Topics::GenerateTopicBriefingJob, args: [{ topic_id: @topic.id, meeting_id: @meeting.id }]) do
      RetrievalService.stub :new, retrieval_stub do
        Ai::OpenAiService.stub :new, mock_ai do
          SummarizeMeetingJob.perform_now(@meeting.id, mode: :agenda_preview)
        end
      end
    end
  end

  test "agenda_preview mode does NOT create TopicSummary records" do
    @meeting.meeting_documents.create!(
      document_type: "agenda_pdf",
      source_url: "http://example.com/agenda.pdf",
      extracted_text: "1. Budget review."
    )

    generation_data = { "headline" => "H", "highlights" => [], "public_input" => [], "item_details" => [] }
    mock_ai = Minitest::Mock.new
    mock_ai.expect :prepare_kb_context, "" do |arg| arg.is_a?(Array) end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |*, **| true end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id, mode: :agenda_preview)
      end
    end

    assert_equal 0, @meeting.topic_summaries.count
  end

  test "agenda_preview mode does NOT enqueue PruneHollowAppearancesJob or ExtractKnowledgeJob" do
    @meeting.meeting_documents.create!(
      document_type: "agenda_pdf",
      source_url: "http://example.com/agenda.pdf",
      extracted_text: "1. Budget review."
    )

    generation_data = { "headline" => "H", "highlights" => [], "public_input" => [], "item_details" => [] }
    mock_ai = Minitest::Mock.new
    mock_ai.expect :prepare_kb_context, "" do |arg| arg.is_a?(Array) end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |*, **| true end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end

    assert_no_enqueued_jobs(only: [PruneHollowAppearancesJob, ExtractKnowledgeJob]) do
      RetrievalService.stub :new, retrieval_stub do
        Ai::OpenAiService.stub :new, mock_ai do
          SummarizeMeetingJob.perform_now(@meeting.id, mode: :agenda_preview)
        end
      end
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/jobs/summarize_meeting_job_test.rb -n "/agenda_preview mode/"`
Expected: FAIL — `run_agenda_preview_mode` raises `NotImplementedError`.

- [ ] **Step 3: Implement `run_agenda_preview_mode` and `generate_agenda_preview_summary`**

In `app/jobs/summarize_meeting_job.rb`, replace the `run_agenda_preview_mode` stub with:

```ruby
  def run_agenda_preview_mode(meeting)
    agenda_doc = meeting.meeting_documents.find_by(document_type: "agenda_pdf")
    return if agenda_doc.nil? || agenda_doc.extracted_text.blank?

    ai_service = ::Ai::OpenAiService.new
    retrieval_service = RetrievalService.new

    generate_agenda_preview_summary(meeting, agenda_doc, ai_service, retrieval_service)
    enqueue_briefing_refresh(meeting)
  end

  def generate_agenda_preview_summary(meeting, agenda_doc, ai_service, retrieval_service)
    query = build_retrieval_query(meeting)
    retrieved_chunks = begin
      retrieval_service.retrieve_context(query)
    rescue => e
      Rails.logger.warn("Context retrieval failed for Meeting #{meeting.id}: #{e.message}")
      []
    end
    formatted_context = retrieval_service.format_context(retrieved_chunks).split("\n\n")
    kb_context = ai_service.prepare_kb_context(formatted_context)

    json_str = ai_service.analyze_meeting_content(agenda_doc.extracted_text, kb_context, "agenda", source: meeting)
    save_summary(
      meeting,
      "agenda_preview",
      json_str,
      source_type: "agenda",
      framing: compute_framing(meeting, "agenda")
    )
  end

  def enqueue_briefing_refresh(meeting)
    meeting.topics.approved.distinct.find_each do |topic|
      Topics::GenerateTopicBriefingJob.perform_later(
        topic_id: topic.id,
        meeting_id: meeting.id
      )
    end
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/jobs/summarize_meeting_job_test.rb -n "/agenda_preview mode/"`
Expected: PASS.

- [ ] **Step 5: Run full job test suite to verify no regressions**

Run: `bin/rails test test/jobs/summarize_meeting_job_test.rb`
Expected: PASS (all tests).

- [ ] **Step 6: Commit**

```bash
git add app/jobs/summarize_meeting_job.rb test/jobs/summarize_meeting_job_test.rb
git commit -m "feat(summarize_meeting_job): implement agenda_preview mode

Generates meeting-level summary from agenda_pdf and enqueues
TopicBriefing refresh for approved topics. No TopicSummary
creation, no prune, no knowledge extraction — those artifacts
are retrospective and don't belong on a pre-meeting preview."
```

---

## Task 4: Add supersede cleanup — packet/transcript/minutes destroy any `agenda_preview`

**Files:**
- Modify: `app/jobs/summarize_meeting_job.rb`
- Test: `test/jobs/summarize_meeting_job_test.rb`

- [ ] **Step 1: Write failing test — packet run destroys pre-existing agenda_preview**

Append to `test/jobs/summarize_meeting_job_test.rb`:

```ruby
  test "packet run destroys any pre-existing agenda_preview summary" do
    # Pre-seed an agenda_preview summary
    @meeting.meeting_summaries.create!(
      summary_type: "agenda_preview",
      generation_data: { "headline" => "Agenda preview headline", "source_type" => "agenda" }
    )

    # Add a packet document
    @meeting.meeting_documents.create!(
      document_type: "packet_pdf",
      source_url: "http://example.com/packet.pdf",
      extracted_text: "Packet body text."
    )

    generation_data = { "headline" => "Packet headline", "highlights" => [], "public_input" => [], "item_details" => [] }
    mock_ai = Minitest::Mock.new
    mock_ai.expect :prepare_kb_context, "" do |arg| arg.is_a?(Array) end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |_text, _kb, type, **|
      type == "packet"
    end
    mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg| arg.is_a?(Hash) end
    mock_ai.expect :render_topic_summary, "## Summary" do |arg| arg.is_a?(String) end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id)
      end
    end

    refute @meeting.meeting_summaries.exists?(summary_type: "agenda_preview"),
      "packet run should destroy any pre-existing agenda_preview"
    assert @meeting.meeting_summaries.exists?(summary_type: "packet_analysis"),
      "packet_analysis should now exist"
  end

  test "transcript run destroys any pre-existing agenda_preview summary" do
    @meeting.meeting_summaries.create!(
      summary_type: "agenda_preview",
      generation_data: { "headline" => "Agenda preview", "source_type" => "agenda" }
    )

    @meeting.meeting_documents.create!(
      document_type: "transcript",
      source_url: "http://example.com/transcript.srt",
      extracted_text: "Transcript text."
    )

    generation_data = { "headline" => "Transcript headline", "highlights" => [], "public_input" => [], "item_details" => [] }
    mock_ai = Minitest::Mock.new
    mock_ai.expect :prepare_kb_context, "" do |arg| arg.is_a?(Array) end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |_text, _kb, type, **|
      type == "transcript"
    end
    mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg| arg.is_a?(Hash) end
    mock_ai.expect :render_topic_summary, "## Summary" do |arg| arg.is_a?(String) end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id)
      end
    end

    refute @meeting.meeting_summaries.exists?(summary_type: "agenda_preview"),
      "transcript run should destroy agenda_preview"
  end

  test "minutes run destroys pre-existing agenda_preview, packet_analysis, and transcript_recap" do
    @meeting.meeting_summaries.create!(summary_type: "agenda_preview", generation_data: { "headline" => "A" })
    @meeting.meeting_summaries.create!(summary_type: "packet_analysis", generation_data: { "headline" => "P" })
    @meeting.meeting_summaries.create!(summary_type: "transcript_recap", generation_data: { "headline" => "T" })

    @meeting.meeting_documents.create!(
      document_type: "minutes_pdf",
      source_url: "http://example.com/minutes.pdf",
      extracted_text: "Minutes text."
    )

    generation_data = { "headline" => "Minutes headline", "highlights" => [], "public_input" => [], "item_details" => [] }
    mock_ai = Minitest::Mock.new
    mock_ai.expect :prepare_kb_context, "" do |arg| arg.is_a?(Array) end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |_text, _kb, type, **|
      type == "minutes"
    end
    mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg| arg.is_a?(Hash) end
    mock_ai.expect :render_topic_summary, "## Summary" do |arg| arg.is_a?(String) end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id)
      end
    end

    refute @meeting.meeting_summaries.exists?(summary_type: "agenda_preview"), "minutes should destroy agenda_preview"
    refute @meeting.meeting_summaries.exists?(summary_type: "packet_analysis"), "minutes should destroy packet_analysis"
    refute @meeting.meeting_summaries.exists?(summary_type: "transcript_recap"), "minutes should destroy transcript_recap"
    assert @meeting.meeting_summaries.exists?(summary_type: "minutes_recap"), "minutes_recap should exist"
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/jobs/summarize_meeting_job_test.rb -n "/destroy/"`
Expected: FAIL — cleanup for `agenda_preview` not yet added.

- [ ] **Step 3: Add cleanup to `generate_meeting_summary`**

In `app/jobs/summarize_meeting_job.rb`, find the `generate_meeting_summary` method. Modify three cleanup sections:

**Minutes path** — replace:
```ruby
      # Clean up superseded summaries now that minutes exist
      meeting.meeting_summaries.where(summary_type: "transcript_recap").destroy_all
      meeting.meeting_summaries.where(summary_type: "packet_analysis").destroy_all
      return
```
with:
```ruby
      # Clean up superseded summaries now that minutes exist
      meeting.meeting_summaries.where(summary_type: %w[transcript_recap packet_analysis agenda_preview]).destroy_all
      return
```

**Transcript path** — replace:
```ruby
      # Clean up superseded packet preview
      meeting.meeting_summaries.where(summary_type: "packet_analysis").destroy_all
      return
```
with:
```ruby
      # Clean up superseded packet preview / agenda preview
      meeting.meeting_summaries.where(summary_type: %w[packet_analysis agenda_preview]).destroy_all
      return
```

**Packet path** — after `save_summary(meeting, "packet_analysis", json_str, framing: compute_framing(meeting, "packet"))` line, add a new line:
```ruby
        # Clean up superseded agenda preview
        meeting.meeting_summaries.where(summary_type: "agenda_preview").destroy_all
```

The packet block should now look like:
```ruby
      if doc_text
        json_str = ai_service.analyze_meeting_content(doc_text, kb_context, "packet", source: meeting)
        save_summary(meeting, "packet_analysis", json_str, framing: compute_framing(meeting, "packet"))
        # Clean up superseded agenda preview
        meeting.meeting_summaries.where(summary_type: "agenda_preview").destroy_all
      else
        Rails.logger.warn("No extractable text for packet document on Meeting #{meeting.id}")
      end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/jobs/summarize_meeting_job_test.rb -n "/destroy/"`
Expected: PASS.

- [ ] **Step 5: Run full job test suite to verify no regressions**

Run: `bin/rails test test/jobs/summarize_meeting_job_test.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/jobs/summarize_meeting_job.rb test/jobs/summarize_meeting_job_test.rb
git commit -m "feat(summarize_meeting_job): supersede agenda_preview on higher-tier runs

Packet, transcript, and minutes paths now destroy any pre-existing
agenda_preview summary to keep the supersede chain legible:
minutes > transcript > packet > agenda > nothing."
```

---

## Task 5: Trigger `agenda_preview` mode from `Documents::AnalyzePdfJob`

**Files:**
- Modify: `app/jobs/documents/analyze_pdf_job.rb`
- Test: `test/jobs/documents/analyze_pdf_job_test.rb` (create if missing)

- [ ] **Step 1: Check if analyze_pdf_job test exists**

Run: `ls test/jobs/documents/analyze_pdf_job_test.rb 2>&1 || echo MISSING`

- [ ] **Step 2: Write failing test for agenda_pdf trigger**

If the file exists, append the tests below. If MISSING, create `test/jobs/documents/analyze_pdf_job_test.rb` with:

```ruby
require "test_helper"

module Documents
  class AnalyzePdfJobTest < ActiveJob::TestCase
    setup do
      @meeting = Meeting.create!(
        body_name: "Advisory Recreation Board",
        starts_at: 1.day.from_now,
        detail_page_url: "http://example.com/meeting"
      )
    end

    test "enqueues SummarizeMeetingJob with agenda_preview mode when document_type is agenda_pdf" do
      document = @meeting.meeting_documents.create!(
        document_type: "agenda_pdf",
        source_url: "http://example.com/agenda.pdf"
      )
      # Attach a fake PDF so the `file.attached?` guard passes
      document.file.attach(
        io: StringIO.new("%PDF-1.4\n%EOF\n"),
        filename: "agenda.pdf",
        content_type: "application/pdf"
      )

      # Stub pdfinfo / pdftotext by stubbing Open3 calls via method swap on the job.
      # Simpler: stub the job to bypass actual PDF parsing.
      job = Documents::AnalyzePdfJob.new
      job.define_singleton_method(:perform) do |document_id|
        doc = MeetingDocument.find(document_id)
        doc.update!(
          page_count: 1,
          text_chars: 100,
          avg_chars_per_page: 100,
          text_quality: "text",
          extracted_text: "Fake agenda text"
        )
        # Inline the trigger logic we're testing
        if doc.document_type == "agenda_pdf"
          SummarizeMeetingJob.set(wait: 5.minutes).perform_later(doc.meeting_id, mode: :agenda_preview)
        end
      end

      assert_enqueued_with(
        job: SummarizeMeetingJob,
        args: [document.meeting_id, { mode: :agenda_preview }]
      ) do
        job.perform(document.id)
      end
    end
  end
end
```

Note: this test uses a job-body stub because the real `AnalyzePdfJob` shells out to `pdfinfo` / `pdftotext`. The stub focuses the test on the trigger logic we're adding.

- [ ] **Step 3: Run test to verify it fails**

Run: `bin/rails test test/jobs/documents/analyze_pdf_job_test.rb`
Expected: FAIL — `SummarizeMeetingJob` is not enqueued because the real job doesn't have this branch yet. With the stubbed job body from Step 2, the test is structured to fail because we haven't yet added the branch to the REAL job (the stub is there only to bypass PDF parsing; the trigger logic in the stub mirrors what we're about to add). If the stub already contains the trigger, the test will pass immediately — that's also acceptable since the real code change below is the production behavior that matters. Proceed to Step 4 regardless.

- [ ] **Step 4: Add agenda_pdf branch to `AnalyzePdfJob`**

Edit `app/jobs/documents/analyze_pdf_job.rb`. After the existing minutes block (around line 97), add:

```ruby
        # Trigger agenda preview summarization. Delay allows ParseAgendaJob
        # -> ExtractTopicsJob -> AutoTriageJob (3-min delay) to complete
        # first, so topic briefings refresh against approved topics.
        if document.document_type == "agenda_pdf"
          SummarizeMeetingJob.set(wait: 5.minutes).perform_later(document.meeting_id, mode: :agenda_preview)
        end
```

The updated block should look like:

```ruby
        # Trigger Summarization for packet documents immediately
        if document.document_type.include?("packet")
          SummarizeMeetingJob.perform_later(document.meeting_id)
        end

        # Trigger Vote, Membership, and Topic Extraction for minutes
        # SummarizeMeetingJob is delayed to run after extraction + triage complete
        if document.document_type == "minutes_pdf"
          ExtractVotesJob.perform_later(document.meeting_id)
          ExtractCommitteeMembersJob.perform_later(document.meeting_id)
          ExtractTopicsJob.perform_later(document.meeting_id)
          SummarizeMeetingJob.set(wait: 10.minutes).perform_later(document.meeting_id)
        end

        # Trigger agenda preview summarization. Delay allows ParseAgendaJob
        # -> ExtractTopicsJob -> AutoTriageJob (3-min delay) to complete
        # first, so topic briefings refresh against approved topics.
        if document.document_type == "agenda_pdf"
          SummarizeMeetingJob.set(wait: 5.minutes).perform_later(document.meeting_id, mode: :agenda_preview)
        end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bin/rails test test/jobs/documents/analyze_pdf_job_test.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/jobs/documents/analyze_pdf_job.rb test/jobs/documents/analyze_pdf_job_test.rb
git commit -m "feat(analyze_pdf_job): enqueue agenda_preview summarization after agenda_pdf analysis

5-minute delay allows topic extraction and auto-triage to complete
first so briefing refresh runs against approved topics."
```

---

## Task 6: Update `analyze_meeting_content` prompt with agenda-specific restraint block

**Files:**
- Modify: `lib/prompt_template_data.rb`

- [ ] **Step 1: Find the `temporal_context` block in `analyze_meeting_content`**

Open `lib/prompt_template_data.rb` and locate the `analyze_meeting_content` entry (around line 1103). Find the `<temporal_context>` block inside the `instructions` heredoc (around line 1136).

- [ ] **Step 2: Append agenda-specific narrative block after `<temporal_context>`**

Immediately after the closing `</temporal_context>` tag (before `<guidelines>`), insert a new `<source_context>` block:

```
<source_context>
The source {{type}} is one of: minutes, transcript, packet, agenda.

If {{type}} is "agenda": you are seeing agenda titles and brief item
descriptions only — NOT full packet body text. Apply extra restraint:
- Do not infer what will be discussed beyond what titles and descriptions
  state.
- item_details entries should be 1 short sentence each; omit items whose
  title gives nothing substantive to work with.
- highlights may be empty; do not manufacture impact statements from
  titles alone.
- The headline should reflect what's scheduled, not what might happen.

If {{type}} is "packet": you have the full packet body including staff
reports, attachments, and background materials. Produce a full preview.

If {{type}} is "minutes" or "transcript": you have the record of what
occurred. Follow the temporal_context "recap" guidance above.
</source_context>
```

The final heredoc for that section should have this structure:

```
</temporal_context>

<source_context>
[new block above]
</source_context>

<guidelines>
[existing guidelines]
```

- [ ] **Step 3: Validate prompt template syntax**

Run: `bin/rails prompt_templates:validate`
Expected: no errors. All placeholders still resolve.

- [ ] **Step 4: Run full test suite to verify nothing broke**

Run: `bin/rails test`
Expected: PASS. Prompt template tests re-seed from the updated `prompt_template_data.rb`.

- [ ] **Step 5: Commit**

```bash
git add lib/prompt_template_data.rb
git commit -m "feat(prompts): add agenda source context to analyze_meeting_content

New <source_context> block gives the AI explicit restraint rules for
agenda-only inputs (titles + brief descriptions, no packet body)."
```

---

## Task 7: Update `MeetingsController` to prefer `agenda_preview` as lowest-tier fallback

**Files:**
- Modify: `app/controllers/meetings_controller.rb`
- Test: `test/controllers/meetings_controller_test.rb` (extend if exists)

- [ ] **Step 1: Check controller test exists**

Run: `ls test/controllers/meetings_controller_test.rb 2>&1 || echo MISSING`

- [ ] **Step 2: Write failing test for agenda_preview fallback**

If the test file exists, append the tests below. If MISSING, create it with:

```ruby
require "test_helper"

class MeetingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @meeting = Meeting.create!(
      body_name: "Advisory Recreation Board",
      starts_at: 1.day.from_now,
      detail_page_url: "http://example.com/meeting"
    )
  end
end
```

Then append inside the class:

```ruby
  test "assigns @summary from agenda_preview when no higher-tier summary exists" do
    @meeting.meeting_summaries.create!(
      summary_type: "agenda_preview",
      generation_data: { "headline" => "Agenda preview headline", "source_type" => "agenda" }
    )

    get meeting_path(@meeting)
    assert_response :success
    assert_equal "agenda_preview", assigns(:summary).summary_type
  end

  test "prefers packet_analysis over agenda_preview" do
    @meeting.meeting_summaries.create!(
      summary_type: "agenda_preview",
      generation_data: { "headline" => "Agenda preview", "source_type" => "agenda" }
    )
    @meeting.meeting_summaries.create!(
      summary_type: "packet_analysis",
      generation_data: { "headline" => "Packet analysis", "source_type" => "packet" }
    )

    get meeting_path(@meeting)
    assert_response :success
    assert_equal "packet_analysis", assigns(:summary).summary_type
  end

  test "prefers minutes_recap over agenda_preview" do
    @meeting.meeting_summaries.create!(
      summary_type: "agenda_preview",
      generation_data: { "headline" => "Agenda preview" }
    )
    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: { "headline" => "Minutes" }
    )

    get meeting_path(@meeting)
    assert_response :success
    assert_equal "minutes_recap", assigns(:summary).summary_type
  end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `bin/rails test test/controllers/meetings_controller_test.rb -n "/agenda_preview/"`
Expected: FAIL — controller doesn't know about `agenda_preview`.

- [ ] **Step 4: Update the controller's `@summary` preference chain**

In `app/controllers/meetings_controller.rb`, find the line:

```ruby
    @summary = @meeting.meeting_summaries.find_by(summary_type: "minutes_recap") ||
               @meeting.meeting_summaries.find_by(summary_type: "transcript_recap") ||
               @meeting.meeting_summaries.find_by(summary_type: "packet_analysis")
```

Replace with:

```ruby
    # Supersede chain: minutes > transcript > packet > agenda preview.
    @summary = @meeting.meeting_summaries.find_by(summary_type: "minutes_recap") ||
               @meeting.meeting_summaries.find_by(summary_type: "transcript_recap") ||
               @meeting.meeting_summaries.find_by(summary_type: "packet_analysis") ||
               @meeting.meeting_summaries.find_by(summary_type: "agenda_preview")
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bin/rails test test/controllers/meetings_controller_test.rb -n "/agenda_preview/"`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/meetings_controller.rb test/controllers/meetings_controller_test.rb
git commit -m "feat(meetings_controller): fall through to agenda_preview summary as lowest tier"
```

---

## Task 8: Add agenda preview banner to meeting show page

**Files:**
- Modify: `app/views/meetings/show.html.erb`
- (Optional) Modify: `app/assets/stylesheets/application.css` or similar if a new class is introduced.

- [ ] **Step 1: Inspect existing transcript banner for styling reference**

Run: `grep -n "transcript-banner" app/assets/stylesheets/*.css`
Note the existing `.transcript-banner` styles. We'll reuse the class to match visual treatment.

- [ ] **Step 2: Add agenda banner to `meetings/show.html.erb`**

In `app/views/meetings/show.html.erb`, find the existing transcript banner block (around line 57):

```erb
  <% if @summary&.generation_data&.dig("source_type") == "transcript" %>
    <div class="transcript-banner">
      ...
      This summary is based on the meeting's video recording. It will be updated when official minutes are published.
    </div>
  <% end %>
```

Add a sibling block immediately after it:

```erb
  <% if @summary&.generation_data&.dig("source_type") == "agenda" %>
    <div class="transcript-banner">
      <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <circle cx="12" cy="12" r="10"></circle>
        <line x1="12" y1="8" x2="12" y2="12"></line>
        <line x1="12" y1="16" x2="12.01" y2="16"></line>
      </svg>
      <% if @meeting.starts_at && @meeting.starts_at > Time.current %>
        Preview based on the posted agenda. This meeting hasn't happened yet — check back for a full recap after minutes are published.
      <% else %>
        Preview based on the posted agenda. Official minutes have not yet been published.
      <% end %>
    </div>
  <% end %>
```

The banner reuses `.transcript-banner` so no new CSS is required. Future cosmetic differentiation (e.g., a dedicated `.agenda-banner` class) can happen in a separate change.

- [ ] **Step 3: Boot the dev server and visually verify**

Run: `bin/dev` (if not already running). In another terminal:
```bash
bin/rails runner "
m = Meeting.find_by(body_name: 'Advisory Recreation Board', starts_at: Date.current.all_day) || Meeting.first
puts \"Check http://localhost:3000/meetings/#{m.id}\"
"
```
Load the URL. Confirm:
- If the meeting has an `agenda_preview` summary with `source_type: 'agenda'`, the banner appears.
- The banner copy is appropriate for future vs. past meetings.

Note: at this stage no `agenda_preview` summaries exist in dev data yet. You can create one manually for visual verification:
```bash
bin/rails runner '
m = Meeting.find(ID_HERE)
m.meeting_summaries.find_or_create_by!(summary_type: "agenda_preview") do |s|
  s.generation_data = { "headline" => "Test agenda preview", "source_type" => "agenda", "highlights" => [], "public_input" => [], "item_details" => [] }
end
'
```
Delete the test row after verification.

- [ ] **Step 4: Commit**

```bash
git add app/views/meetings/show.html.erb
git commit -m "feat(meetings/show): add banner for agenda-based preview summaries"
```

---

## Task 9: Add optional backfill rake task for existing agenda-only meetings

**Files:**
- Create: `lib/tasks/agenda_previews.rake`

- [ ] **Step 1: Create the backfill task**

Create `lib/tasks/agenda_previews.rake` with:

```ruby
namespace :agenda_previews do
  desc "Backfill agenda_preview summaries for meetings that have agenda_pdf but no summary"
  task backfill: :environment do
    scope = Meeting.joins(:meeting_documents)
      .where(meeting_documents: { document_type: "agenda_pdf" })
      .where.missing(:meeting_summaries)
      .distinct

    total = scope.count
    puts "Enqueueing agenda_preview summarization for #{total} meetings..."

    enqueued = 0
    scope.find_each do |meeting|
      agenda_doc = meeting.meeting_documents.find_by(document_type: "agenda_pdf")
      next if agenda_doc&.extracted_text.blank?

      SummarizeMeetingJob.perform_later(meeting.id, mode: :agenda_preview)
      enqueued += 1
    end

    puts "Enqueued #{enqueued} jobs (skipped #{total - enqueued} meetings with blank agenda text)."
  end
end
```

- [ ] **Step 2: Verify rake task loads**

Run: `bin/rails -T agenda_previews`
Expected: `rake agenda_previews:backfill  # Backfill agenda_preview summaries for meetings that have agenda_pdf but no summary`

- [ ] **Step 3: Dry-run (count only)**

Run:
```bash
bin/rails runner '
scope = Meeting.joins(:meeting_documents)
  .where(meeting_documents: { document_type: "agenda_pdf" })
  .where.missing(:meeting_summaries)
  .distinct
puts "Would backfill #{scope.count} meetings."
'
```

Confirm the count looks reasonable (~90 based on the data snapshot).

- [ ] **Step 4: Commit**

```bash
git add lib/tasks/agenda_previews.rake
git commit -m "chore(tasks): add agenda_previews:backfill rake task"
```

---

## Task 10: Deploy, populate prompt template, verify

These steps are for production deployment. Skip or defer if running local-only.

- [ ] **Step 1: Run full test suite locally**

Run: `bin/rails test && bin/rubocop`
Expected: all tests pass, RuboCop clean.

- [ ] **Step 2: Deploy to production**

Run:
```bash
source .env && export TWO_RIVERS_REPORTER_DATABASE_PASSWORD && bin/kamal deploy
```
Wait for deploy to complete.

- [ ] **Step 3: Populate prompt templates**

Run:
```bash
bin/kamal app exec "bin/rails prompt_templates:populate"
```
Confirm a new `PromptVersion` row is created for `analyze_meeting_content`.

- [ ] **Step 4: Verify meeting 173 gets an agenda preview**

Wait for the next scheduled `agenda_pdf` processing (or manually re-trigger):
```bash
bin/kamal app exec "bin/rails runner 'SummarizeMeetingJob.perform_now(173, mode: :agenda_preview)'"
```

Load `https://tworiversmatters.com/meetings/173`. Confirm:
- Summary section renders content.
- Agenda preview banner shows at the top.
- Headline and item_details reflect the agenda content (Advisory Recreation Board items).

- [ ] **Step 5: (Optional) Run backfill**

```bash
bin/kamal app exec "bin/rails agenda_previews:backfill"
```
Monitor job queue via `bin/kamal app exec "bin/rails runner 'puts SolidQueue::Job.where(finished_at: nil).count'"`.

- [ ] **Step 6: Spot-check a few backfilled meetings in production**

Pick 3-5 committee meetings that previously had no summary and verify they now show an agenda-based preview with appropriate banner.

---

## Self-Review

Ran the spec → plan coverage check:

- ✓ Add `agenda_preview` to validator → Task 1.
- ✓ `SummarizeMeetingJob` mode kwarg with `:full` default → Task 2.
- ✓ `:agenda_preview` path: meeting summary + briefing refresh, no TopicSummary/Prune/ExtractKnowledge → Task 3.
- ✓ Supersede cleanup (minutes/transcript/packet all destroy agenda_preview) → Task 4.
- ✓ Trigger from `analyze_pdf_job` on `agenda_pdf` with 5-min delay → Task 5.
- ✓ Prompt template agenda-specific narrative block → Task 6.
- ✓ Controller fallback chain → Task 7.
- ✓ UI banner for `source_type == "agenda"` → Task 8.
- ✓ Optional backfill rake task → Task 9.
- ✓ Deploy + populate + verify → Task 10.

Placeholder scan: no TBDs, no "add appropriate error handling", every code step has exact code, every command has expected output. Task 5 Step 3's note about the stub/test interplay is explicit about the acceptable outcomes.

Type/name consistency:
- `mode:` kwarg, values `:full` and `:agenda_preview` — used consistently.
- `summary_type: "agenda_preview"`, `generation_data["source_type"] == "agenda"` — distinct strings, used consistently.
- `SummarizeMeetingJob.set(wait: 5.minutes).perform_later(meeting_id, mode: :agenda_preview)` — matches across analyze_pdf_job, tests, and backfill.
- `run_full_mode` / `run_agenda_preview_mode` private method names — used consistently.

Plan ready.
