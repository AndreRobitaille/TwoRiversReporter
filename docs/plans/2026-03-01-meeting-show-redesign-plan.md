# Meeting Show Page Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the meeting show page's wall-of-text layout with structured JSON rendering (inverted pyramid: headline → highlights → public input → unified agenda item cards → topic cards → documents) and drop the two-pass AI summarization to a single pass.

**Architecture:** Add `generation_data` (jsonb) to `meeting_summaries`. Rewrite the `analyze_meeting_content` prompt to produce a new schema (`headline`, `highlights`, `public_input`, `item_details`) in editorial voice. Modify `SummarizeMeetingJob` to store Pass 1 JSON and drop the Pass 2 markdown call. Rewrite the meeting show view to render directly from structured JSON, with markdown `content` fallback for un-backfilled meetings.

**Tech Stack:** Rails 8.1, PostgreSQL jsonb, Minitest, ERB views, CSS custom properties

**Design doc:** `docs/plans/2026-03-01-meeting-show-redesign-design.md`

**Reference pattern:** Topic show page (`app/views/topics/show.html.erb`) renders from `TopicBriefing.generation_data` with helper methods in `TopicsHelper`.

---

### Task 1: Migration — Add `generation_data` to `meeting_summaries`

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_add_generation_data_to_meeting_summaries.rb`
- Verify: `db/schema.rb`

**Step 1: Generate the migration**

Run:
```bash
bin/rails generate migration AddGenerationDataToMeetingSummaries generation_data:jsonb
```
Expected: Creates migration file in `db/migrate/`.

**Step 2: Edit the migration to add a default**

Open the generated migration and ensure it reads:

```ruby
class AddGenerationDataToMeetingSummaries < ActiveRecord::Migration[8.1]
  def change
    add_column :meeting_summaries, :generation_data, :jsonb, default: {}
  end
end
```

**Step 3: Run the migration**

Run:
```bash
bin/rails db:migrate
```
Expected: `db/schema.rb` now shows `t.jsonb "generation_data", default: {}` in the `meeting_summaries` table.

**Step 4: Commit**

```bash
git add db/migrate/*_add_generation_data_to_meeting_summaries.rb db/schema.rb
git commit -m "feat: add generation_data column to meeting_summaries"
```

---

### Task 2: AI Prompt — Rewrite `analyze_meeting_content` for new schema

**Files:**
- Modify: `app/services/ai/open_ai_service.rb` (lines 876–954, the `analyze_meeting_content` method)
- Test: `test/services/ai/open_ai_service_test.rb` (create if needed, or manual verification)

**Context:**
- Read `docs/AUDIENCE.md` for editorial voice guidelines.
- Read `docs/plans/2026-03-01-meeting-show-redesign-design.md` for the `generation_data` schema.
- The current method at line 876 produces `top_topics`, `other_topics`, `framing_notes`, etc. Replace the entire prompt and schema.

**Step 1: Write the test**

Create `test/services/ai/open_ai_service_analyze_meeting_test.rb`:

```ruby
require "test_helper"
require "minitest/mock"

class OpenAiServiceAnalyzeMeetingTest < ActiveSupport::TestCase
  setup do
    @service = Ai::OpenAiService.new
  end

  test "analyze_meeting_content prompt includes json keyword for response_format" do
    # The prompt must contain "json" when using response_format: json_object
    # We verify the prompt is constructed correctly by intercepting the API call
    mock_client = Minitest::Mock.new

    expected_response = {
      "choices" => [{
        "message" => {
          "content" => {
            "headline" => "Test headline",
            "highlights" => [],
            "public_input" => [],
            "item_details" => []
          }.to_json
        }
      }]
    }

    mock_client.expect :chat, expected_response do |params:|
      messages = params[:messages]
      prompt_text = messages.map { |m| m[:content] }.join(" ")

      # Must contain "json" for OpenAI json_object mode
      assert prompt_text.downcase.include?("json"), "Prompt must contain 'json'"

      # Must request the new schema fields
      assert prompt_text.include?("headline"), "Prompt must request headline"
      assert prompt_text.include?("highlights"), "Prompt must request highlights"
      assert prompt_text.include?("public_input"), "Prompt must request public_input"
      assert prompt_text.include?("item_details"), "Prompt must request item_details"

      # Must mention editorial voice / plain language
      assert prompt_text.include?("plain language") || prompt_text.include?("editorial"),
        "Prompt must specify editorial voice"

      # Must exclude procedural items
      assert prompt_text.include?("procedural") || prompt_text.include?("adjourn"),
        "Prompt must mention procedural filtering"

      true
    end

    @service.instance_variable_set(:@client, mock_client)
    result = @service.analyze_meeting_content("Test minutes text", "kb context", "minutes")

    assert result.present?
    mock_client.verify
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
bin/rails test test/services/ai/open_ai_service_analyze_meeting_test.rb -v
```
Expected: FAIL — the current prompt doesn't contain `headline`, `highlights`, `public_input`, `item_details`.

**Step 3: Rewrite `analyze_meeting_content`**

Replace the method at `app/services/ai/open_ai_service.rb:876-954` with:

```ruby
    # PASS 1: Structured meeting analysis — produces JSON for direct rendering
    def analyze_meeting_content(doc_text, kb_context, type)
      system_role = <<~ROLE
        You are a civic journalist covering Two Rivers, WI city government
        for a community news site. Your audience is residents — mostly 35+,
        mobile-heavy, skeptical of city leadership, checking in casually.
        They want the gist fast in plain language. No government jargon.

        Write in editorial voice: skeptical of process and decisions (not of
        people), editorialize early, surface patterns, note deferrals, flag
        when framing doesn't match outcomes. Criticize decisions and
        processes, not individuals.
      ROLE

      prompt = <<~PROMPT
        Analyze the provided #{type} text and return a JSON object with the
        structure specified below.

        #{kb_context}
        #{prepare_committee_context}

        <guidelines>
        - Write in plain language a resident would use at a neighborhood
          gathering. No government jargon ("motion to waive reading and
          adopt the ordinance to amend..." → "voted to change the rule").
        - Headline: 1-2 backward-looking sentences, max ~40 words.
          What happened at this meeting that residents should know.
        - Highlights: max 3 items, highest resident impact first. Include
          vote tallies where votes occurred. Each highlight gets a page
          citation.
        - Public input: Distinguish general public comment (resident spoke
          at open comment period, unrelated to specific agenda items) from
          communication (council/committee member relayed resident contact).
          Item-specific public hearings go in item_details, NOT here.
          Redact residential addresses: "[Address redacted]".
        - Item details: Cover substantive agenda items only. Each gets 2-4
          sentences of editorial summary explaining what happened and why it
          matters. Include public_hearing note for items with formal public
          input (Wisconsin law three-calls). Include decision and vote tally
          where applicable. Anchor citations to page numbers.
        </guidelines>

        <procedural_filter>
        EXCLUDE these procedural items from item_details entirely:
        - Adjournment motions
        - Minutes approval
        - Consent agenda approval (unless a specific item was pulled for
          separate discussion)
        - Remote participation approval
        - Treasurer's report acceptance
        - Reconvene in open session

        DO NOT EXCLUDE closed session motions — they contain statutory
        justification (Wis. Stats 19.85) that residents need for open
        meetings law transparency.
        </procedural_filter>

        DOCUMENT TEXT:
        #{doc_text.truncate(100_000)}

        <output_schema>
        Return a JSON object matching this schema exactly:

        {
          "headline": "1-2 sentences summarizing what happened at this meeting.",
          "highlights": [
            {
              "text": "What happened and why it matters to residents.",
              "citation": "Page X",
              "vote": "6-3 or null if no vote",
              "impact": "high|medium|low"
            }
          ],
          "public_input": [
            {
              "speaker": "Speaker Name",
              "type": "public_comment|communication",
              "summary": "What they said or relayed, in plain language."
            }
          ],
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
        }

        highlights: max 3 items. Order by resident impact (highest first).
        public_input: include all speakers. Empty array if none.
        item_details: substantive items only (see procedural_filter above).
        All text fields: plain language, no jargon.
        </output_schema>
      PROMPT

      response = @client.chat(
        parameters: {
          model: DEFAULT_MODEL,
          response_format: { type: "json_object" },
          messages: [
            { role: "system", content: system_role },
            { role: "user", content: prompt }
          ],
          temperature: 0.1
        }
      )

      response.dig("choices", 0, "message", "content")
    end
```

**Step 4: Run test to verify it passes**

Run:
```bash
bin/rails test test/services/ai/open_ai_service_analyze_meeting_test.rb -v
```
Expected: PASS

**Step 5: Run full test suite to verify no regressions**

Run:
```bash
bin/rails test
```
Expected: All tests pass. The existing `SummarizeMeetingJobTest` tests may need adjustment (they don't mock `analyze_meeting_content` directly — check the mock_ai expectations).

**Step 6: Commit**

```bash
git add app/services/ai/open_ai_service.rb test/services/ai/open_ai_service_analyze_meeting_test.rb
git commit -m "feat: rewrite analyze_meeting_content prompt for structured JSON schema

Produces headline, highlights, public_input, item_details in editorial
voice. Filters procedural items. Drops the old top_topics/other_topics
schema."
```

---

### Task 3: Job — Modify `SummarizeMeetingJob` to store `generation_data` and drop Pass 2

**Files:**
- Modify: `app/jobs/summarize_meeting_job.rb` (lines 18–46, `generate_meeting_summary` and `save_summary`)
- Modify: `test/jobs/summarize_meeting_job_test.rb` (update mocks, add new tests)

**Context:**
- Currently `summarize_minutes` calls `analyze_meeting_content` (Pass 1) → `render_meeting_summary` (Pass 2). We want to keep Pass 1 JSON and skip Pass 2.
- `save_summary` currently only stores `content`. It must also store `generation_data`.
- The `summarize_minutes`, `summarize_packet`, and `summarize_packet_with_citations` methods in `OpenAiService` chain Pass 1 → Pass 2. We need to bypass them and call `analyze_meeting_content` directly from the job.

**Step 1: Write the failing test**

Add to `test/jobs/summarize_meeting_job_test.rb`:

```ruby
  test "generates meeting summary with generation_data from minutes" do
    doc = @meeting.meeting_documents.create!(
      document_type: "minutes_pdf",
      source_url: "http://example.com/minutes.pdf",
      extracted_text: "Page 1: The council approved the budget 5-2."
    )

    generation_data = {
      "headline" => "Council approved the budget",
      "highlights" => [{ "text" => "Budget approved", "citation" => "Page 1", "vote" => "5-2", "impact" => "high" }],
      "public_input" => [],
      "item_details" => []
    }

    mock_ai = Minitest::Mock.new
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |text, kb, type|
      type == "minutes"
    end
    # analyze_topic_summary + render_topic_summary for topic summaries
    mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg|
      arg.is_a?(Hash)
    end
    mock_ai.expect :render_topic_summary, "## Summary" do |arg|
      arg.is_a?(String)
    end

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

    summary = @meeting.meeting_summaries.find_by(summary_type: "minutes_recap")
    assert summary, "Should create a minutes_recap summary"
    assert_equal generation_data, summary.generation_data
    # content should NOT be populated (no Pass 2)
    assert_nil summary.content
  end
```

**Step 2: Run test to verify it fails**

Run:
```bash
bin/rails test test/jobs/summarize_meeting_job_test.rb -n "/generates meeting summary with generation_data/" -v
```
Expected: FAIL — `generation_data` column doesn't exist yet in the test DB (run migration first if Task 1 is done), and the job still calls `summarize_minutes` which chains Pass 1 → Pass 2.

**Step 3: Rewrite `generate_meeting_summary` in `summarize_meeting_job.rb`**

Replace lines 18–46 with:

```ruby
  def generate_meeting_summary(meeting, ai_service, retrieval_service)
    query = build_retrieval_query(meeting)
    retrieved_chunks = retrieval_service.retrieve_context(query)
    formatted_context = retrieval_service.format_context(retrieved_chunks).split("\n\n")
    kb_context = ai_service.send(:prepare_kb_context, formatted_context)

    # Prefer minutes (authoritative) over packet
    minutes_doc = meeting.meeting_documents.find_by(document_type: "minutes_pdf")
    if minutes_doc&.extracted_text.present?
      json_str = ai_service.analyze_meeting_content(minutes_doc.extracted_text, kb_context, "minutes")
      save_summary(meeting, "minutes_recap", json_str)
      return
    end

    # Fall back to packet
    packet_doc = meeting.meeting_documents.where("document_type LIKE ?", "%packet%").first
    if packet_doc
      doc_text = if packet_doc.extractions.any?
        ai_service.send(:prepare_doc_context, packet_doc.extractions)
      elsif packet_doc.extracted_text.present?
        packet_doc.extracted_text
      end

      if doc_text
        json_str = ai_service.analyze_meeting_content(doc_text, kb_context, "packet")
        save_summary(meeting, "packet_analysis", json_str)
      end
    end
  end
```

**Step 4: Rewrite `save_summary` to store `generation_data`**

Replace lines 144–148 with:

```ruby
  def save_summary(meeting, type, json_str)
    generation_data = begin
      JSON.parse(json_str)
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse meeting summary JSON: #{e.message}"
      {}
    end

    summary = meeting.meeting_summaries.find_or_initialize_by(summary_type: type)
    summary.generation_data = generation_data
    summary.content = nil  # No longer generating markdown
    summary.save!
  end
```

**Step 5: Run test to verify it passes**

Run:
```bash
bin/rails test test/jobs/summarize_meeting_job_test.rb -v
```
Expected: The new test passes. Existing tests may fail because the mock expectations changed — the job no longer calls `summarize_minutes` / `summarize_packet` / `render_meeting_summary`. Update existing tests:

The existing tests only mock `analyze_topic_summary` and `render_topic_summary` (for topic summaries), not meeting-level summarization. Since the meeting has no `minutes_pdf` or `packet_pdf` documents in the existing test setup, `generate_meeting_summary` returns early without calling the AI. So existing tests should still pass.

**Step 6: Run full test suite**

Run:
```bash
bin/rails test
```
Expected: All pass.

**Step 7: Commit**

```bash
git add app/jobs/summarize_meeting_job.rb test/jobs/summarize_meeting_job_test.rb
git commit -m "feat: store generation_data in meeting summaries, drop Pass 2

SummarizeMeetingJob now calls analyze_meeting_content directly and stores
the structured JSON in generation_data. The render_meeting_summary (Pass 2)
call is removed. Old markdown content field is set to nil for new summaries."
```

---

### Task 4: Helper — Add `MeetingsHelper` methods for `generation_data` extraction

**Files:**
- Modify: `app/helpers/meetings_helper.rb`
- Create: `test/helpers/meetings_helper_test.rb`

**Context:**
- Follow the pattern in `app/helpers/topics_helper.rb` — simple methods that dig into nested JSON.
- Reuse the existing `render_inline_markdown` helper from `TopicsHelper` for bold text.

**Step 1: Write the tests**

Create `test/helpers/meetings_helper_test.rb`:

```ruby
require "test_helper"

class MeetingsHelperTest < ActionView::TestCase
  include MeetingsHelper

  setup do
    @generation_data = {
      "headline" => "Council approved $2.5M borrowing 6-3, tabled property assessment policy.",
      "highlights" => [
        { "text" => "Adopted intent-to-reimburse resolution", "citation" => "Page 3", "vote" => "6-3", "impact" => "high" },
        { "text" => "Tabled property assessment ordinance", "citation" => "Page 2", "vote" => nil, "impact" => "high" }
      ],
      "public_input" => [
        { "speaker" => "Jim Smith", "type" => "public_comment", "summary" => "Raised concerns about building condition" },
        { "speaker" => "Councilmember Jones", "type" => "communication", "summary" => "Contacted by resident about parking" }
      ],
      "item_details" => [
        {
          "agenda_item_title" => "Rezoning at 3204 Lincoln Ave",
          "summary" => "Plan Commission recommended approval.",
          "public_hearing" => "Three calls for public input. No one spoke.",
          "decision" => "Passed",
          "vote" => "7-0",
          "citations" => ["Page 2"]
        },
        {
          "agenda_item_title" => "Property Assessment Ordinance",
          "summary" => "Council chose to table rather than vote.",
          "public_hearing" => nil,
          "decision" => "Tabled",
          "vote" => nil,
          "citations" => ["Page 2"]
        }
      ]
    }
  end

  test "meeting_headline extracts headline" do
    assert_equal "Council approved $2.5M borrowing 6-3, tabled property assessment policy.",
      meeting_headline(@generation_data)
  end

  test "meeting_headline returns nil for missing data" do
    assert_nil meeting_headline(nil)
    assert_nil meeting_headline({})
  end

  test "meeting_highlights extracts highlights array" do
    highlights = meeting_highlights(@generation_data)
    assert_equal 2, highlights.size
    assert_equal "6-3", highlights.first["vote"]
  end

  test "meeting_highlights returns empty array for missing data" do
    assert_equal [], meeting_highlights(nil)
    assert_equal [], meeting_highlights({})
  end

  test "meeting_public_input extracts public input array" do
    inputs = meeting_public_input(@generation_data)
    assert_equal 2, inputs.size
    assert_equal "public_comment", inputs.first["type"]
  end

  test "meeting_public_input returns empty array for missing data" do
    assert_equal [], meeting_public_input(nil)
  end

  test "meeting_item_details extracts item details array" do
    items = meeting_item_details(@generation_data)
    assert_equal 2, items.size
    assert_equal "Passed", items.first["decision"]
    assert_equal "7-0", items.first["vote"]
  end

  test "meeting_item_details returns empty array for missing data" do
    assert_equal [], meeting_item_details(nil)
  end

  test "decision_badge_class returns correct CSS class" do
    assert_equal "decision-badge--passed", decision_badge_class("Passed")
    assert_equal "decision-badge--failed", decision_badge_class("Failed")
    assert_equal "decision-badge--tabled", decision_badge_class("Tabled")
    assert_equal "decision-badge--tabled", decision_badge_class("Referred")
    assert_equal "decision-badge--default", decision_badge_class("Other")
    assert_equal "decision-badge--default", decision_badge_class(nil)
  end
end
```

**Step 2: Run test to verify it fails**

Run:
```bash
bin/rails test test/helpers/meetings_helper_test.rb -v
```
Expected: FAIL — methods don't exist.

**Step 3: Add helper methods to `app/helpers/meetings_helper.rb`**

Replace the entire file with:

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

  # --- generation_data extraction helpers ---

  def meeting_headline(generation_data)
    return nil if generation_data.blank?
    generation_data["headline"]
  end

  def meeting_highlights(generation_data)
    return [] if generation_data.blank?
    generation_data["highlights"] || []
  end

  def meeting_public_input(generation_data)
    return [] if generation_data.blank?
    generation_data["public_input"] || []
  end

  def meeting_item_details(generation_data)
    return [] if generation_data.blank?
    generation_data["item_details"] || []
  end

  def decision_badge_class(decision)
    case decision&.downcase
    when "passed" then "decision-badge--passed"
    when "failed" then "decision-badge--failed"
    when "tabled", "referred" then "decision-badge--tabled"
    else "decision-badge--default"
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run:
```bash
bin/rails test test/helpers/meetings_helper_test.rb -v
```
Expected: All PASS.

**Step 5: Commit**

```bash
git add app/helpers/meetings_helper.rb test/helpers/meetings_helper_test.rb
git commit -m "feat: add MeetingsHelper methods for generation_data extraction"
```

---

### Task 5: Controller — Expose `@summary` in `MeetingsController#show`

**Files:**
- Modify: `app/controllers/meetings_controller.rb` (lines 12–22, `show` action)
- Modify: `test/controllers/meetings_controller_test.rb`

**Step 1: Write the failing test**

Add to `test/controllers/meetings_controller_test.rb`:

```ruby
  test "show assigns summary with generation_data" do
    summary = MeetingSummary.create!(
      meeting: @meeting,
      summary_type: "minutes_recap",
      generation_data: { "headline" => "Test headline" }
    )

    get meeting_url(@meeting)
    assert_response :success
    assert_equal summary, assigns(:summary)
  end

  test "show assigns nil summary when none exists" do
    get meeting_url(@meeting)
    assert_response :success
    assert_nil assigns(:summary)
  end
```

**Step 2: Run test to verify it fails**

Run:
```bash
bin/rails test test/controllers/meetings_controller_test.rb -n "/assigns summary/" -v
```
Expected: FAIL — `@summary` is not assigned.

**Step 3: Add `@summary` to the controller**

Edit `app/controllers/meetings_controller.rb`, add to the `show` action after the existing topic partition code:

```ruby
  def show
    @meeting = Meeting.find(params[:id])

    approved_topics = @meeting.topics.approved
      .includes(:topic_appearances, :topic_briefing)
      .distinct

    @ongoing_topics, @new_topics = approved_topics.partition do |topic|
      topic.topic_appearances.size > 1
    end

    # Prefer minutes_recap over packet_analysis
    @summary = @meeting.meeting_summaries.find_by(summary_type: "minutes_recap") ||
               @meeting.meeting_summaries.find_by(summary_type: "packet_analysis")
  end
```

**Step 4: Run test to verify it passes**

Run:
```bash
bin/rails test test/controllers/meetings_controller_test.rb -v
```
Expected: All PASS.

**Step 5: Commit**

```bash
git add app/controllers/meetings_controller.rb test/controllers/meetings_controller_test.rb
git commit -m "feat: expose @summary in MeetingsController#show"
```

---

### Task 6: CSS — Add styles for meeting show page sections

**Files:**
- Modify: `app/assets/stylesheets/application.css`

**Context:**
- The design has: headline section, highlights bullets, public input list, agenda item cards with decision badges, topic pills on cards.
- Existing CSS variables are used throughout. Check the top of `application.css` for `--color-*`, `--space-*`, `--font-size-*`, `--radius-*`.
- Follow patterns from topic show page: `.topic-watch-callout` (callout card), `.topic-timeline-entry` (timeline items).

**Step 1: Add new CSS classes**

Add the following CSS before the `/* Section empty states */` comment (around line 2010 of `application.css`):

```css
/* === Meeting Show — Structured Sections === */

.meeting-headline {
  font-size: var(--font-size-lg);
  line-height: 1.4;
  color: var(--color-text);
  margin-bottom: var(--space-6);
}

.meeting-highlights {
  list-style: none;
  padding: 0;
  margin: 0 0 var(--space-2) 0;
}

.meeting-highlights li {
  padding: var(--space-3) 0;
  border-bottom: 1px solid var(--color-border);
  line-height: 1.5;
}

.meeting-highlights li:last-child {
  border-bottom: none;
}

.highlight-citation {
  font-size: var(--font-size-xs);
  color: var(--color-text-muted);
  margin-left: var(--space-2);
}

.highlight-vote {
  font-weight: 600;
}

/* Public Input */
.public-input-list {
  list-style: none;
  padding: 0;
  margin: 0;
}

.public-input-item {
  padding: var(--space-3) 0;
  border-bottom: 1px solid var(--color-border);
}

.public-input-item:last-child {
  border-bottom: none;
}

.public-input-speaker {
  font-weight: 600;
}

.public-input-type {
  font-size: var(--font-size-xs);
  color: var(--color-text-muted);
  margin-left: var(--space-2);
}

/* Agenda Item Cards */
.meeting-item-card {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  padding: var(--space-5);
  margin-bottom: var(--space-4);
}

.meeting-item-card-title {
  font-size: var(--font-size-base);
  font-weight: 600;
  margin-bottom: var(--space-3);
}

.meeting-item-card-summary {
  line-height: 1.6;
  margin-bottom: var(--space-3);
}

.meeting-item-card-hearing {
  font-size: var(--font-size-sm);
  color: var(--color-text-secondary);
  font-style: italic;
  margin-bottom: var(--space-3);
}

.meeting-item-card-decision {
  margin-bottom: var(--space-3);
}

.decision-badge {
  display: inline-block;
  font-size: var(--font-size-sm);
  font-weight: 600;
  padding: var(--space-1) var(--space-3);
  border-radius: var(--radius-sm);
}

.decision-badge--passed {
  background: var(--color-success-bg, #dcfce7);
  color: var(--color-success-text, #166534);
}

.decision-badge--failed {
  background: var(--color-danger-bg, #fee2e2);
  color: var(--color-danger-text, #991b1b);
}

.decision-badge--tabled {
  background: var(--color-warning-bg, #fef3c7);
  color: var(--color-warning-text, #92400e);
}

.decision-badge--default {
  background: var(--color-border);
  color: var(--color-text-secondary);
}

.meeting-item-card-citations {
  font-size: var(--font-size-xs);
  color: var(--color-text-muted);
}

.meeting-item-card .tags {
  margin-top: var(--space-3);
}

/* Legacy prose fallback */
.meeting-legacy-recap {
  margin-top: var(--space-4);
}
```

**Step 2: Verify CSS doesn't break anything**

Run:
```bash
bin/rails test test/controllers/meetings_controller_test.rb -v
```
Expected: PASS (CSS changes don't break tests).

**Step 3: Commit**

```bash
git add app/assets/stylesheets/application.css
git commit -m "feat: add CSS styles for meeting show structured sections

Agenda item cards, decision badges, highlights, public input list,
and headline styles."
```

---

### Task 7: View — Rewrite `meetings/show.html.erb` with structured layout

**Files:**
- Rewrite: `app/views/meetings/show.html.erb`
- Modify: `test/controllers/meetings_controller_test.rb` (update section heading assertions)

**Context:**
- Design doc section order: Header → Headline → Highlights → Public Input → Agenda Items → Topics → Documents.
- `@summary` is the `MeetingSummary` record (may be nil).
- `@summary&.generation_data` is a Hash (may be empty `{}`).
- For meetings without `generation_data`, fall back to rendering `@summary.content` as markdown prose.
- All sections always render. Empty sections show `.section-empty` messages.
- Agenda item cards match AI `item_details` to database `AgendaItem` records by title for topic pills.
- Topic cards section uses the existing `topics/_topic_card` partial.

**Step 1: Update controller test assertions**

The existing tests reference `"Issues in This Meeting"` — the new heading will be `"Topics in This Meeting"`. Update `test/controllers/meetings_controller_test.rb`:

Replace:
```ruby
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
```

With:
```ruby
  test "show renders topics section with ongoing and new subsections" do
    get meeting_url(@meeting)
    assert_response :success

    assert_select "h2", text: "Topics in This Meeting"
    assert_select "h3", text: "Ongoing"
    assert_select "h3", text: "New This Meeting"
  end

  test "show renders empty state when no approved topics" do
    AgendaItemTopic.destroy_all
    get meeting_url(@meeting)
    assert_response :success

    assert_select ".section-empty", text: "No topics have been identified for this meeting."
  end
```

Add new tests:

```ruby
  test "show renders headline from generation_data" do
    MeetingSummary.create!(
      meeting: @meeting,
      summary_type: "minutes_recap",
      generation_data: { "headline" => "Council approved the budget 5-2." }
    )

    get meeting_url(@meeting)
    assert_response :success

    assert_select ".meeting-headline", text: /Council approved the budget/
  end

  test "show renders empty state when no summary exists" do
    get meeting_url(@meeting)
    assert_response :success

    assert_select ".section-empty", text: "No summary available for this meeting yet."
  end

  test "show renders legacy markdown when no generation_data" do
    MeetingSummary.create!(
      meeting: @meeting,
      summary_type: "minutes_recap",
      content: "## Old Recap\n\nThis is the old markdown."
    )

    get meeting_url(@meeting)
    assert_response :success

    assert_select ".meeting-legacy-recap"
  end

  test "show renders documents section with empty state" do
    @meeting.meeting_documents.destroy_all
    get meeting_url(@meeting)
    assert_response :success

    assert_select ".section-empty", text: "No documents available for this meeting."
  end
```

**Step 2: Run tests to verify they fail**

Run:
```bash
bin/rails test test/controllers/meetings_controller_test.rb -v
```
Expected: FAIL — old section headings/classes don't match.

**Step 3: Rewrite the view**

Replace the entire contents of `app/views/meetings/show.html.erb`:

```erb
<% content_for(:title) { "#{@meeting.body_name} - #{@meeting.starts_at&.strftime('%B %d, %Y')} - Two Rivers Matters" } %>

<%# === Section 1: Header === %>
<div class="page-header">
  <h1 class="page-title"><%= @meeting.body_name %></h1>
</div>

<div class="meeting-meta">
  <div class="meeting-meta-item">
    <span class="meeting-meta-label">Date & Time</span>
    <span class="meeting-meta-value"><%= @meeting.starts_at&.strftime("%B %d, %Y at %l:%M %p") %></span>
  </div>
  <div class="meeting-meta-item">
    <span class="meeting-meta-label">Status</span>
    <span class="badge <%= case @meeting.status
      when 'minutes_posted' then 'badge--success'
      when 'upcoming' then 'badge--primary'
      else 'badge--default'
    end %>">
      <%= @meeting.status&.titleize || "Unknown" %>
    </span>
  </div>
  <% if @meeting.committee.present? %>
    <div class="meeting-meta-item">
      <span class="meeting-meta-label">Committee</span>
      <span class="meeting-meta-value"><%= @meeting.committee.name %></span>
    </div>
  <% end %>
  <div class="meeting-meta-item">
    <span class="meeting-meta-label">Original Source</span>
    <span class="meeting-meta-value">
      <%= link_to "View on City Website", safe_external_url(@meeting.detail_page_url), target: "_blank", rel: "noopener" %>
    </span>
  </div>
</div>

<% gd = @summary&.generation_data.presence %>

<% if gd %>
  <%# === Section 2: Headline === %>
  <section class="section">
    <% headline = meeting_headline(gd) %>
    <% if headline.present? %>
      <p class="meeting-headline"><%= headline %></p>
    <% else %>
      <p class="section-empty">No summary available for this meeting yet.</p>
    <% end %>
  </section>

  <%# === Section 3: Highlights === %>
  <% highlights = meeting_highlights(gd) %>
  <% if highlights.any? %>
    <section class="section">
      <h2>Highlights</h2>
      <ul class="meeting-highlights">
        <% highlights.each do |h| %>
          <li>
            <%= h["text"] %>
            <% if h["vote"].present? %>
              <span class="highlight-vote">(<%= h["vote"] %>)</span>
            <% end %>
            <% if h["citation"].present? %>
              <span class="highlight-citation">[<%= h["citation"] %>]</span>
            <% end %>
          </li>
        <% end %>
      </ul>
    </section>
  <% end %>

  <%# === Section 4: Public Input === %>
  <section class="section">
    <h2>Public Input</h2>
    <% public_inputs = meeting_public_input(gd) %>
    <% if public_inputs.any? %>
      <ul class="public-input-list">
        <% public_inputs.each do |pi| %>
          <li class="public-input-item">
            <span class="public-input-speaker"><%= pi["speaker"] %></span>
            <span class="public-input-type">
              <%= pi["type"] == "communication" ? "Communication" : "Public Comment" %>
            </span>
            <p><%= pi["summary"] %></p>
          </li>
        <% end %>
      </ul>
    <% else %>
      <p class="section-empty">No public comments or communications recorded for this meeting.</p>
    <% end %>
  </section>

  <%# === Section 5: Agenda Items === %>
  <section class="section">
    <h2>Agenda Items</h2>
    <% items = meeting_item_details(gd) %>
    <% if items.any? %>
      <% items.each do |item| %>
        <div class="meeting-item-card">
          <div class="meeting-item-card-title"><%= item["agenda_item_title"] %></div>

          <% if item["summary"].present? %>
            <div class="meeting-item-card-summary"><%= item["summary"] %></div>
          <% end %>

          <% if item["public_hearing"].present? %>
            <div class="meeting-item-card-hearing">
              Public Input: <%= item["public_hearing"] %>
            </div>
          <% end %>

          <% if item["decision"].present? %>
            <div class="meeting-item-card-decision">
              <span class="decision-badge <%= decision_badge_class(item["decision"]) %>">
                <%= item["decision"] %>
                <%= " #{item["vote"]}" if item["vote"].present? %>
              </span>
            </div>
          <% end %>

          <% if item["citations"].present? %>
            <div class="meeting-item-card-citations">
              <%= Array(item["citations"]).join(", ") %>
            </div>
          <% end %>

          <%# Match AI item to database agenda items for topic pills %>
          <% matched_agenda_item = @meeting.agenda_items.detect { |ai| ai.title&.downcase&.include?(item["agenda_item_title"]&.downcase&.first(30).to_s) } %>
          <% if matched_agenda_item&.topics&.any? %>
            <div class="tags">
              <% matched_agenda_item.topics.each do |topic| %>
                <%= link_to topic.name, topic_path(topic), class: "tag" %>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    <% else %>
      <p class="section-empty">No agenda items available for this meeting.</p>
    <% end %>
  </section>

<% elsif @summary&.content.present? %>
  <%# === Legacy fallback: render old markdown content === %>
  <section class="section">
    <div class="ai-content">
      <div class="ai-content-header">
        <h2>
          <% if @summary.summary_type == "minutes_recap" %>
            Meeting Recap
          <% else %>
            Packet Analysis
          <% end %>
        </h2>
        <span class="badge badge--ai" title="Generated by AI">AI Analysis</span>
      </div>
      <div class="prose meeting-legacy-recap">
        <%= markdown @summary.content %>
      </div>
      <div class="ai-content-disclaimer">
        Generated by AI based on official documents. Always verify with original sources.
      </div>
    </div>
  </section>

<% else %>
  <%# === No summary at all === %>
  <section class="section">
    <p class="section-empty">No summary available for this meeting yet.</p>
  </section>
<% end %>

<%# === Section 6: Topics in This Meeting === %>
<section class="section">
  <h2>Topics in This Meeting</h2>
  <% if @ongoing_topics.present? || @new_topics.present? %>
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
  <% else %>
    <p class="section-empty">No topics have been identified for this meeting.</p>
  <% end %>
</section>

<%# === Section 7: Documents === %>
<section class="section">
  <h2>Documents</h2>
  <% if @meeting.meeting_documents.any? %>
    <div class="card">
      <ul class="documents-list">
        <% @meeting.meeting_documents.each do |doc| %>
          <li>
            <div>
              <span class="document-type"><%= doc.document_type.humanize %></span>
              <% if doc.file.attached? && doc.document_type.include?("pdf") %>
                <span class="document-meta">
                  (<%= number_to_human_size(doc.file.byte_size) %>)
                  <% if doc.text_quality.present? %>
                    - Quality: <%= doc.text_quality.humanize %>
                  <% end %>
                </span>
              <% end %>
            </div>
            <div>
              <% if doc.file.attached? && doc.document_type.include?("pdf") %>
                <%= link_to "Download PDF", rails_blob_path(doc.file, disposition: "attachment"), class: "btn btn--secondary btn--sm" %>
              <% else %>
                <%= link_to "View Original", safe_external_url(doc.source_url), target: "_blank", rel: "noopener", class: "btn btn--secondary btn--sm" %>
              <% end %>
            </div>
          </li>
        <% end %>
      </ul>
    </div>
  <% else %>
    <p class="section-empty">No documents available for this meeting.</p>
  <% end %>
</section>

<%= link_to meetings_path, class: "back-link" do %>
  <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
    <line x1="19" y1="12" x2="5" y2="12"></line>
    <polyline points="12 19 5 12 12 5"></polyline>
  </svg>
  Back to Meetings
<% end %>
```

**Step 4: Run tests to verify they pass**

Run:
```bash
bin/rails test test/controllers/meetings_controller_test.rb -v
```
Expected: All PASS.

**Step 5: Run full test suite**

Run:
```bash
bin/rails test
```
Expected: All PASS.

**Step 6: Commit**

```bash
git add app/views/meetings/show.html.erb test/controllers/meetings_controller_test.rb
git commit -m "feat: rewrite meeting show page with structured JSON layout

Inverted pyramid: headline, highlights, public input, unified agenda
item cards, topic cards, documents. All sections always render with
empty state messages. Falls back to legacy markdown for old summaries."
```

---

### Task 8: Verification — Test on real data

**Files:** None (manual verification)

**Step 1: Re-summarize a council meeting with minutes**

Run:
```bash
bin/rails runner "SummarizeMeetingJob.perform_now(131)"
```
Expected: `MeetingSummary` for meeting 131 now has `generation_data` with `headline`, `highlights`, `public_input`, and `item_details`.

**Step 2: Verify the generation_data structure**

Run:
```bash
bin/rails runner "s = Meeting.find(131).meeting_summaries.last; puts JSON.pretty_generate(s.generation_data)"
```
Expected: JSON output showing all four top-level keys with meaningful editorial content.

**Step 3: Verify the page renders**

Run:
```bash
bin/dev
```
Then visit `http://localhost:3000/meetings/131` in a browser. Verify:
- Headline appears as 1-2 sentences below the header
- Highlights appear as 3 bulleted items with vote tallies and citations
- Public Input section shows speakers with comment types
- Agenda Item cards show title, editorial summary, decision badges, topic pills
- Topics section shows ongoing/new cards
- Documents section shows download links

**Step 4: Test a meeting with no summary**

Visit a meeting with no `MeetingSummary` records. Verify empty state: "No summary available for this meeting yet."

**Step 5: Test a meeting with old markdown only**

Find a meeting that has `content` but no `generation_data`:
```bash
bin/rails runner "s = MeetingSummary.where.not(content: nil).where(generation_data: {}).first; puts s&.meeting_id"
```
Visit that meeting. Verify the legacy markdown fallback renders.

**Step 6: Test a subcommittee meeting**

Run:
```bash
bin/rails runner "SummarizeMeetingJob.perform_now(130)"
```
Visit `http://localhost:3000/meetings/130`. Verify adequate detail for a smaller meeting.

**Step 7: Evaluate editorial quality**

Compare the structured JSON rendering against the old two-pass markdown. If per-item summaries are too thin (especially for 2-hour council meetings with 10-15 substantive items), document findings. The design doc notes we may add Pass 2 back as a JSON enrichment step — but start with one pass.

---

### Task 9: Documentation — Update CLAUDE.md and DEVELOPMENT_PLAN.md

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/DEVELOPMENT_PLAN.md`

**Step 1: Add Meeting Show Page section to CLAUDE.md**

Add a new `### Meeting Show Page` subsection under `## Architecture` (after `### Topic Show Page`), documenting:
- Structured JSON rendering from `MeetingSummary.generation_data`
- Section order (inverted pyramid)
- Helper methods in `MeetingsHelper`
- Fallback to legacy markdown `content`
- Key CSS classes
- Design doc reference

**Step 2: Update DEVELOPMENT_PLAN.md**

Update the relevant sections to reflect:
- Meeting summaries now use single-pass structured JSON
- `generation_data` stores the structured analysis
- Pass 2 (`render_meeting_summary`) is no longer used for meeting summaries
- Meeting show page uses structured JSON rendering

**Step 3: Commit**

```bash
git add CLAUDE.md docs/DEVELOPMENT_PLAN.md
git commit -m "docs: update CLAUDE.md and DEVELOPMENT_PLAN.md for meeting show page redesign"
```
