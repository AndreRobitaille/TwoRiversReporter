# Temporal Meeting Summary Framing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add temporal context to the `analyze_meeting_content` prompt so meeting summaries adopt the correct narrative posture (preview vs recap) based on whether the meeting has occurred.

**Architecture:** Derive `framing` ("preview", "recap", "stale_preview") from `meeting.starts_at` vs `Date.current` and document type. Pass as placeholders to the prompt template. Store in `generation_data`. Clean up stale previews when authoritative summaries arrive.

**Tech Stack:** Rails 8.1, Minitest, `PromptTemplate` interpolation system

**Spec:** `docs/superpowers/specs/2026-04-09-temporal-meeting-summary-framing-design.md`

---

### Task 1: Add temporal placeholders to `OpenAiService#analyze_meeting_content`

**Files:**
- Modify: `app/services/ai/open_ai_service.rb:602-614`
- Test: `test/services/ai/open_ai_service_analyze_meeting_test.rb`

- [ ] **Step 1: Write failing test — future meeting passes temporal placeholders**

Add this test to `test/services/ai/open_ai_service_analyze_meeting_test.rb`:

```ruby
test "analyze_meeting_content includes temporal context for future meeting" do
  captured_params = nil

  mock_chat = lambda do |parameters:|
    captured_params = parameters
    {
      "choices" => [ {
        "message" => {
          "content" => {
            "headline" => "Test headline",
            "highlights" => [],
            "public_input" => [],
            "item_details" => []
          }.to_json
        }
      } ]
    }
  end

  meeting = Meeting.create!(
    body_name: "City Council Meeting",
    starts_at: 3.days.from_now,
    detail_page_url: "https://example.com/meeting/future"
  )

  @service.instance_variable_get(:@client).stub :chat, mock_chat do
    @service.send(:analyze_meeting_content, "Agenda text", "kb context", "packet", source: meeting)
  end

  prompt_text = captured_params[:messages].map { |m| m[:content] }.join(" ")

  assert prompt_text.include?("preview"), "Prompt must include 'preview' framing for future meeting"
  assert prompt_text.include?(meeting.starts_at.to_date.to_s), "Prompt must include meeting date"
  assert prompt_text.include?(Date.current.to_s), "Prompt must include today's date"
  assert prompt_text.include?("HAS NOT OCCURRED"), "Prompt must include preview instructions"
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/ai/open_ai_service_analyze_meeting_test.rb -n "/temporal context for future/""`
Expected: FAIL — prompt does not contain "preview" or temporal context

- [ ] **Step 3: Write failing test — past meeting with minutes gets recap framing**

Add this test to `test/services/ai/open_ai_service_analyze_meeting_test.rb`:

```ruby
test "analyze_meeting_content includes recap framing for past meeting with minutes" do
  captured_params = nil

  mock_chat = lambda do |parameters:|
    captured_params = parameters
    {
      "choices" => [ {
        "message" => {
          "content" => {
            "headline" => "Test headline",
            "highlights" => [],
            "public_input" => [],
            "item_details" => []
          }.to_json
        }
      } ]
    }
  end

  meeting = Meeting.create!(
    body_name: "City Council Meeting",
    starts_at: 3.days.ago,
    detail_page_url: "https://example.com/meeting/past"
  )

  @service.instance_variable_get(:@client).stub :chat, mock_chat do
    @service.send(:analyze_meeting_content, "Minutes text", "kb context", "minutes", source: meeting)
  end

  prompt_text = captured_params[:messages].map { |m| m[:content] }.join(" ")

  assert prompt_text.include?("recap"), "Prompt must include 'recap' framing for past meeting with minutes"
end
```

- [ ] **Step 4: Write failing test — past meeting with only packet gets stale_preview framing**

Add this test to `test/services/ai/open_ai_service_analyze_meeting_test.rb`:

```ruby
test "analyze_meeting_content includes stale_preview framing for past meeting with only packet" do
  captured_params = nil

  mock_chat = lambda do |parameters:|
    captured_params = parameters
    {
      "choices" => [ {
        "message" => {
          "content" => {
            "headline" => "Test headline",
            "highlights" => [],
            "public_input" => [],
            "item_details" => []
          }.to_json
        }
      } ]
    }
  end

  meeting = Meeting.create!(
    body_name: "City Council Meeting",
    starts_at: 3.days.ago,
    detail_page_url: "https://example.com/meeting/stale"
  )

  @service.instance_variable_get(:@client).stub :chat, mock_chat do
    @service.send(:analyze_meeting_content, "Packet text", "kb context", "packet", source: meeting)
  end

  prompt_text = captured_params[:messages].map { |m| m[:content] }.join(" ")

  assert prompt_text.include?("stale_preview"), "Prompt must include 'stale_preview' framing for past meeting with only packet"
end
```

- [ ] **Step 5: Run all three new tests to verify they fail**

Run: `bin/rails test test/services/ai/open_ai_service_analyze_meeting_test.rb`
Expected: 3 failures for the new temporal tests, existing tests still pass

- [ ] **Step 6: Implement temporal placeholder derivation**

In `app/services/ai/open_ai_service.rb`, replace lines 606-613:

```ruby
      body_name = source.respond_to?(:body_name) ? source.body_name.to_s : ""
      placeholders = {
        kb_context: kb_context.to_s,
        committee_context: committee_ctx,
        type: type.to_s,
        body_name: body_name,
        doc_text: doc_text.truncate(100_000)
      }
```

with:

```ruby
      body_name = source.respond_to?(:body_name) ? source.body_name.to_s : ""
      meeting_date = source.respond_to?(:starts_at) ? source.starts_at&.to_date : nil
      today = Date.current

      temporal_framing = if meeting_date && meeting_date > today
                           "preview"
                         elsif type.to_s == "minutes" || type.to_s == "transcript"
                           "recap"
                         else
                           "stale_preview"
                         end

      placeholders = {
        kb_context: kb_context.to_s,
        committee_context: committee_ctx,
        type: type.to_s,
        body_name: body_name,
        meeting_date: meeting_date.to_s,
        today: today.to_s,
        temporal_framing: temporal_framing,
        doc_text: doc_text.truncate(100_000)
      }
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `bin/rails test test/services/ai/open_ai_service_analyze_meeting_test.rb`
Expected: All tests pass (new tests will pass once the prompt template is updated in Task 2, so they may still fail here — that's expected, the placeholders are in place but the template doesn't use them yet)

- [ ] **Step 8: Commit**

```bash
git add app/services/ai/open_ai_service.rb test/services/ai/open_ai_service_analyze_meeting_test.rb
git commit -m "feat: add temporal placeholder derivation to analyze_meeting_content"
```

---

### Task 2: Update the `analyze_meeting_content` prompt template

**Files:**
- Modify: `lib/prompt_template_data.rb:149-158` (metadata placeholders)
- Modify: `lib/prompt_template_data.rb:806-829` (prompt instructions)

- [ ] **Step 1: Add new placeholders to metadata**

In `lib/prompt_template_data.rb`, replace the placeholders array for `analyze_meeting_content` (lines 153-158):

```ruby
      placeholders: [
        { "name" => "kb_context", "description" => "Knowledge base context chunks" },
        { "name" => "committee_context", "description" => "Active committees and descriptions" },
        { "name" => "type", "description" => "Document type: packet or minutes" },
        { "name" => "doc_text", "description" => "Meeting document text (truncated to 50k)" }
      ]
```

with:

```ruby
      placeholders: [
        { "name" => "kb_context", "description" => "Knowledge base context chunks" },
        { "name" => "committee_context", "description" => "Active committees and descriptions" },
        { "name" => "type", "description" => "Document type: packet, minutes, or transcript" },
        { "name" => "body_name", "description" => "Name of the governing body" },
        { "name" => "meeting_date", "description" => "Date of the meeting (YYYY-MM-DD)" },
        { "name" => "today", "description" => "Current date (YYYY-MM-DD)" },
        { "name" => "temporal_framing", "description" => "preview, recap, or stale_preview" },
        { "name" => "doc_text", "description" => "Meeting document text (truncated to 100k)" }
      ]
```

- [ ] **Step 2: Add `<temporal_context>` block to prompt instructions**

In `lib/prompt_template_data.rb`, after the `</document_scope>` closing tag (line 823) and before `<guidelines>` (line 825), insert:

```ruby
        <temporal_context>
        Today's date: {{today}}. This meeting is scheduled for {{meeting_date}}.

        {{temporal_framing}} is one of: preview, recap, stale_preview.

        If "preview": This meeting HAS NOT OCCURRED. You are writing a preview
        based on the agenda/packet. Do not infer outcomes, reactions, decisions,
        debate, or public input — none of that has happened yet. Frame everything
        as what is proposed, what is at stake, and what residents should watch for.
        Use future tense ("will consider", "is expected to", "is proposed").
        headline should be forward-looking. highlights become "what to watch"
        items. item_details describe what is being proposed and why it matters,
        not what happened. decision and vote fields must be null.

        If "recap": This meeting has occurred. Summarize what happened.

        If "stale_preview": This meeting's date has passed, but only agenda/packet
        text is available — no minutes or transcript. Do not fabricate outcomes.
        Frame as: here is what was on the agenda. Note that official results are
        not yet available. Use past tense for the scheduling ("was scheduled")
        but do not state or imply any decisions, votes, or discussion occurred.
        headline should note that results are pending. decision and vote fields
        must be null.
        </temporal_context>

```

- [ ] **Step 3: Update headline guideline to defer to temporal context**

In `lib/prompt_template_data.rb`, replace lines 829-830:

```
        - Headline: 1-2 backward-looking sentences, max ~40 words.
          What happened at this meeting that residents should know.
```

with:

```
        - Headline: 1-2 sentences, max ~40 words. Follow the temporal_context
          framing for tense and posture.
```

- [ ] **Step 4: Run the service tests to verify temporal tests now pass**

Run: `bin/rails test test/services/ai/open_ai_service_analyze_meeting_test.rb`
Expected: All tests pass — the placeholders are interpolated into the prompt, temporal context block is present

- [ ] **Step 5: Run full test suite to check for regressions**

Run: `bin/rails test`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add lib/prompt_template_data.rb
git commit -m "feat: add temporal_context block to analyze_meeting_content prompt"
```

---

### Task 3: Store framing in `generation_data` and clean up stale previews

**Files:**
- Modify: `app/jobs/summarize_meeting_job.rb:18-74` (generate_meeting_summary) and `177-192` (save_summary)
- Test: `test/jobs/summarize_meeting_job_test.rb`

- [ ] **Step 1: Write failing test — framing stored in generation_data for packet preview**

Add this test to `test/jobs/summarize_meeting_job_test.rb`:

```ruby
test "stores preview framing in generation_data for future meeting with packet" do
  @meeting.update!(starts_at: 3.days.from_now)

  @meeting.meeting_documents.create!(
    document_type: "packet_pdf",
    source_url: "http://example.com/packet.pdf",
    extracted_text: "Agenda: Budget review scheduled."
  )

  generation_data = {
    "headline" => "Council will consider the budget",
    "highlights" => [],
    "public_input" => [],
    "item_details" => []
  }

  mock_ai = Minitest::Mock.new
  mock_ai.expect :prepare_kb_context, "" do |arg| arg.is_a?(Array) end
  mock_ai.expect :prepare_doc_context, "Agenda text" do |arg| true end
  mock_ai.expect :analyze_meeting_content, generation_data.to_json do |text, kb, type, **kwargs|
    type == "packet"
  end
  # Topic-level mocks
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

  summary = @meeting.meeting_summaries.find_by(summary_type: "packet_analysis")
  assert summary, "Should create a packet_analysis summary"
  assert_equal "preview", summary.generation_data["framing"]
end
```

- [ ] **Step 2: Write failing test — packet_analysis cleaned up when minutes arrive**

Add this test to `test/jobs/summarize_meeting_job_test.rb`:

```ruby
test "cleans up packet_analysis when minutes_recap is created" do
  # Pre-existing packet preview
  @meeting.meeting_summaries.create!(
    summary_type: "packet_analysis",
    generation_data: { "headline" => "Old preview", "framing" => "preview" }
  )

  @meeting.meeting_documents.create!(
    document_type: "minutes_pdf",
    source_url: "http://example.com/minutes.pdf",
    extracted_text: "Page 1: The council approved the budget 5-2."
  )

  generation_data = {
    "headline" => "Council approved the budget",
    "highlights" => [],
    "public_input" => [],
    "item_details" => []
  }

  mock_ai = Minitest::Mock.new
  mock_ai.expect :prepare_kb_context, "" do |arg| arg.is_a?(Array) end
  mock_ai.expect :analyze_meeting_content, generation_data.to_json do |text, kb, type, **kwargs|
    type == "minutes"
  end
  # Topic-level mocks
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

  assert_nil @meeting.meeting_summaries.find_by(summary_type: "packet_analysis"),
    "packet_analysis should be cleaned up when minutes_recap arrives"
  assert @meeting.meeting_summaries.find_by(summary_type: "minutes_recap"),
    "minutes_recap should exist"
end
```

- [ ] **Step 3: Write failing test — packet_analysis cleaned up when transcript arrives**

Add this test to `test/jobs/summarize_meeting_job_test.rb`:

```ruby
test "cleans up packet_analysis when transcript_recap is created" do
  @meeting.meeting_summaries.create!(
    summary_type: "packet_analysis",
    generation_data: { "headline" => "Old preview", "framing" => "stale_preview" }
  )

  @meeting.meeting_documents.create!(
    document_type: "transcript",
    source_url: "http://example.com/transcript.txt",
    extracted_text: "Transcript: The council discussed the budget."
  )

  generation_data = {
    "headline" => "Council discussed the budget",
    "highlights" => [],
    "public_input" => [],
    "item_details" => []
  }

  mock_ai = Minitest::Mock.new
  mock_ai.expect :prepare_kb_context, "" do |arg| arg.is_a?(Array) end
  mock_ai.expect :analyze_meeting_content, generation_data.to_json do |text, kb, type, **kwargs|
    type == "transcript"
  end
  # Topic-level mocks
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

  assert_nil @meeting.meeting_summaries.find_by(summary_type: "packet_analysis"),
    "packet_analysis should be cleaned up when transcript_recap arrives"
  assert @meeting.meeting_summaries.find_by(summary_type: "transcript_recap"),
    "transcript_recap should exist"
end
```

- [ ] **Step 4: Run all new tests to verify they fail**

Run: `bin/rails test test/jobs/summarize_meeting_job_test.rb`
Expected: 3 new tests fail (no "framing" in generation_data, no packet_analysis cleanup)

- [ ] **Step 5: Implement framing computation and save_summary changes**

In `app/jobs/summarize_meeting_job.rb`, add a private method after `build_retrieval_query`:

```ruby
  def compute_framing(meeting, type)
    meeting_date = meeting.starts_at&.to_date
    if meeting_date && meeting_date > Date.current
      "preview"
    elsif type == "minutes" || type == "transcript"
      "recap"
    else
      "stale_preview"
    end
  end
```

Update `save_summary` to accept and store `framing:`:

```ruby
  def save_summary(meeting, type, json_str, source_type: nil, framing: nil)
    generation_data = begin
      JSON.parse(json_str)
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse meeting summary JSON: #{e.message}"
      {}
    end

    generation_data["source_type"] = source_type if source_type
    generation_data["framing"] = framing if framing

    summary = meeting.meeting_summaries.find_or_initialize_by(summary_type: type)
    summary.generation_data = generation_data
    summary.content = nil
    summary.save!
    summary
  end
```

- [ ] **Step 6: Pass framing to save_summary in each branch and add cleanup**

In `generate_meeting_summary`, update the three branches:

**Minutes branch (around line 43-48):** Replace:

```ruby
      json_str = ai_service.analyze_meeting_content(input_text, kb_context, "minutes", source: meeting)
      summary = save_summary(meeting, "minutes_recap", json_str, source_type: source_type)

      # Clean up any old transcript-only summary now that minutes exist
      meeting.meeting_summaries.where(summary_type: "transcript_recap").destroy_all
```

with:

```ruby
      json_str = ai_service.analyze_meeting_content(input_text, kb_context, "minutes", source: meeting)
      summary = save_summary(meeting, "minutes_recap", json_str, source_type: source_type, framing: compute_framing(meeting, "minutes"))

      # Clean up superseded summaries now that minutes exist
      meeting.meeting_summaries.where(summary_type: "transcript_recap").destroy_all
      meeting.meeting_summaries.where(summary_type: "packet_analysis").destroy_all
```

**Transcript branch (around line 53-54):** Replace:

```ruby
      json_str = ai_service.analyze_meeting_content(transcript_doc.extracted_text, kb_context, "transcript", source: meeting)
      save_summary(meeting, "transcript_recap", json_str, source_type: "transcript")
```

with:

```ruby
      json_str = ai_service.analyze_meeting_content(transcript_doc.extracted_text, kb_context, "transcript", source: meeting)
      save_summary(meeting, "transcript_recap", json_str, source_type: "transcript", framing: compute_framing(meeting, "transcript"))

      # Clean up superseded packet preview
      meeting.meeting_summaries.where(summary_type: "packet_analysis").destroy_all
```

**Packet branch (around line 68-69):** Replace:

```ruby
        json_str = ai_service.analyze_meeting_content(doc_text, kb_context, "packet", source: meeting)
        save_summary(meeting, "packet_analysis", json_str)
```

with:

```ruby
        json_str = ai_service.analyze_meeting_content(doc_text, kb_context, "packet", source: meeting)
        save_summary(meeting, "packet_analysis", json_str, framing: compute_framing(meeting, "packet"))
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `bin/rails test test/jobs/summarize_meeting_job_test.rb`
Expected: All tests pass (new and existing)

- [ ] **Step 8: Run full test suite**

Run: `bin/rails test`
Expected: All tests pass

- [ ] **Step 9: Commit**

```bash
git add app/jobs/summarize_meeting_job.rb test/jobs/summarize_meeting_job_test.rb
git commit -m "feat: store framing in generation_data, clean up stale packet previews"
```

---

### Task 4: Lint check and final verification

**Files:**
- All modified files

- [ ] **Step 1: Run RuboCop**

Run: `bin/rubocop app/services/ai/open_ai_service.rb app/jobs/summarize_meeting_job.rb lib/prompt_template_data.rb`
Expected: No offenses. Fix any that appear.

- [ ] **Step 2: Run full CI**

Run: `bin/ci`
Expected: All checks pass

- [ ] **Step 3: Run full test suite one final time**

Run: `bin/rails test`
Expected: All tests pass

- [ ] **Step 4: Commit any lint fixes**

Only if Step 1 required changes:

```bash
git add -A
git commit -m "style: fix rubocop offenses in temporal framing changes"
```
