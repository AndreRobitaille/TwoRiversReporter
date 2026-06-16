# Committee-Scoped Topic Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent generic committee agenda items such as Room Tax Commission `BUDGET REVIEW` from incorrectly reviving broad citywide topics, then surgically reanalyze meeting `216` and verify the homepage.

**Architecture:** Add explicit meeting-body context to topic extraction, make the prompt enforce body-scoped interpretation before broad topic reuse, and add a surgical reanalysis rake task that captures before/after links and regenerates affected downstream topic artifacts. Homepage selection is verification-only unless the corrected extraction still fails.

**Tech Stack:** Rails 8, ActiveJob, Minitest, PromptTemplate seed data in `lib/prompt_template_data.rb`, Solid Queue jobs, Rake tasks.

---

## Files

- Modify: `lib/prompt_template_data.rb` — add `meeting_context` placeholder and body-scoped extraction rules to the `extract_topics` template.
- Modify: `app/services/ai/open_ai_service.rb` — accept and interpolate `meeting_context` in `extract_topics`.
- Modify: `app/jobs/extract_topics_job.rb` — build meeting context from `Meeting` and pass it to the AI service.
- Modify: `test/services/ai/open_ai_service_extract_topics_test.rb` — test prompt interpolation and scope rule wording.
- Modify: `test/jobs/extract_topics_job_test.rb` — test `ExtractTopicsJob` passes body/date context.
- Create: `lib/tasks/topic_reanalysis.rake` — surgical meeting reanalysis task for meeting `216` and similar future repairs.
- Create: `test/tasks/topic_reanalysis_task_test.rb` — task-level regression coverage for before/after capture and downstream job invocation.

---

### Task 1: Add failing tests for committee-scoped extraction prompts

**Files:**
- Modify: `test/services/ai/open_ai_service_extract_topics_test.rb`
- Modify: `test/jobs/extract_topics_job_test.rb`

- [ ] **Step 1: Add prompt interpolation test**

Append this test to `test/services/ai/open_ai_service_extract_topics_test.rb` before the final `end`:

```ruby
  test "extract_topics includes meeting context and body scoped reuse rules" do
    captured_prompt = nil
    mock_response = {
      "choices" => [ { "message" => { "content" => '{"items":[]}' } } ]
    }

    client = @service.instance_variable_get(:@client)
    client.stub :chat, ->(parameters:) {
      captured_prompt = parameters[:messages].last[:content]
      mock_response
    } do
      @service.extract_topics(
        "ID: 3029\nTitle: BUDGET REVIEW",
        existing_topics: [ "city budget" ],
        meeting_context: "Meeting body: Room Tax Commission Meeting\nMeeting date: 2026-06-23"
      )
    end

    assert_includes captured_prompt, "Meeting body: Room Tax Commission Meeting"
    assert_includes captured_prompt, "committee_scope"
    assert_includes captured_prompt, "body-scoped by default"
    assert_includes captured_prompt, "Room Tax Commission"
    assert_includes captured_prompt, "not the overall city budget"
  end
```

- [ ] **Step 2: Add job context-passing test**

Append this test to `test/jobs/extract_topics_job_test.rb` before the final `end`:

```ruby
  test "passes meeting body and date context to topic extraction" do
    meeting = Meeting.create!(
      body_name: "Room Tax Commission Meeting",
      meeting_type: "regular",
      starts_at: Time.zone.parse("2026-06-23 16:00:00"),
      status: "upcoming",
      detail_page_url: "http://example.com/room-tax"
    )
    item = AgendaItem.create!(
      meeting: meeting,
      number: "4.",
      title: "BUDGET REVIEW (Action Item)",
      order_index: 4,
      kind: "item"
    )

    captured_kwargs = nil
    ai_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Finance",
        "tags" => [ "room tax budget" ],
        "topic_worthy" => true,
        "confidence" => 0.8
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_topics, ai_response do |_text, **kwargs|
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

    assert_includes captured_kwargs[:meeting_context], "Meeting body: Room Tax Commission Meeting"
    assert_includes captured_kwargs[:meeting_context], "Meeting date: 2026-06-23"
    assert_includes captured_kwargs[:meeting_context], "Interpret generic agenda terms within this body's jurisdiction"
    mock_ai.verify
  end
```

- [ ] **Step 3: Run the two new tests and verify they fail**

Run:

```bash
bin/rails test test/services/ai/open_ai_service_extract_topics_test.rb test/jobs/extract_topics_job_test.rb
```

Expected: failures mentioning missing keyword `meeting_context` or missing prompt text.

---

### Task 2: Implement meeting context plumbing and prompt rules

**Files:**
- Modify: `lib/prompt_template_data.rb`
- Modify: `app/services/ai/open_ai_service.rb`
- Modify: `app/jobs/extract_topics_job.rb`

- [ ] **Step 1: Add `meeting_context` placeholder metadata**

In `lib/prompt_template_data.rb`, update the `extract_topics` prompt metadata placeholders from:

```ruby
        { "name" => "meeting_documents_context", "description" => "Extracted text from meeting documents" },
        { "name" => "items_text", "description" => "Formatted agenda items to classify" }
```

to:

```ruby
        { "name" => "meeting_documents_context", "description" => "Extracted text from meeting documents" },
        { "name" => "meeting_context", "description" => "Meeting body, date, and scope instructions" },
        { "name" => "items_text", "description" => "Formatted agenda items to classify" }
```

- [ ] **Step 2: Add body-scope rules to the extract prompt**

In `lib/prompt_template_data.rb`, inside `DEFAULTS["extract_topics"][:instructions]`, insert this block after `</topic_granularity>` and before `{{community_context}}`:

```text

        <committee_scope>
        {{meeting_context}}

        Before reusing an existing broad topic, determine what body is having
        the discussion and what that body normally governs. Generic agenda
        labels such as "budget review", "policy update", "director update",
        "treasurer report", "program update", or "review" are body-scoped by
        default.

        Reuse a broad citywide topic only when the agenda item, attached
        documents, or meeting-level documents explicitly show citywide scope —
        for example General Fund, citywide tax levy, all fund budgets, City
        Council budget adoption, citywide service levels, city budget, or a
        citywide budget amendment.

        For the Room Tax Commission, "budget review" normally means the
        room-tax/tourism budget, not the overall city budget. Do not link a
        Room Tax Commission budget item to "city budget" unless the record
        explicitly says the item concerns the citywide budget, General Fund,
        tax levy, or all city funds.

        If scope is ambiguous and the item is generic, prefer a narrower
        body-scoped topic or set topic_worthy: false. Do not use a broad
        canonical topic to fill uncertainty.
        </committee_scope>
```

- [ ] **Step 3: Accept and interpolate `meeting_context` in AI service**

In `app/services/ai/open_ai_service.rb`, change the method signature and placeholders.

Replace:

```ruby
    def extract_topics(items_text, community_context: "", existing_topics: [], meeting_documents_context: "", source: nil)
```

with:

```ruby
    def extract_topics(items_text, community_context: "", existing_topics: [], meeting_documents_context: "", meeting_context: "", source: nil)
```

Then replace the placeholders hash with:

```ruby
      placeholders = {
        items_text: items_text.truncate(50_000),
        community_context: community_context,
        existing_topics: existing_topics_list,
        meeting_documents_context: meeting_documents_context.to_s.truncate(30_000, separator: " "),
        meeting_context: meeting_context.to_s
      }
```

- [ ] **Step 4: Build and pass meeting context from `ExtractTopicsJob`**

In `app/jobs/extract_topics_job.rb`, update the `ai_service.extract_topics` call from:

```ruby
      meeting_documents_context: meeting_docs_context,
      source: meeting
```

to:

```ruby
      meeting_documents_context: meeting_docs_context,
      meeting_context: build_meeting_context(meeting),
      source: meeting
```

Add this private method near the other private helpers:

```ruby
  def build_meeting_context(meeting)
    date = meeting.starts_at&.to_date&.iso8601 || "unknown"

    <<~TEXT.strip
      Meeting body: #{meeting.body_name}
      Meeting date: #{date}
      Interpret generic agenda terms within this body's jurisdiction unless attached documents clearly broaden the scope.
    TEXT
  end
```

- [ ] **Step 5: Run targeted tests**

Run:

```bash
bin/rails test test/services/ai/open_ai_service_extract_topics_test.rb test/jobs/extract_topics_job_test.rb
```

Expected: PASS.

---

### Task 3: Add surgical topic reanalysis rake task

**Files:**
- Create: `lib/tasks/topic_reanalysis.rake`
- Create: `test/tasks/topic_reanalysis_task_test.rb`

- [ ] **Step 1: Write failing task test**

Create `test/tasks/topic_reanalysis_task_test.rb` with:

```ruby
require "test_helper"
require "rake"

class TopicReanalysisTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.none? { |task| task.name == "topics:reanalyze_meeting" }
    Rake::Task["topics:reanalyze_meeting"].reenable
  end

  test "reanalyze meeting captures before and after topics and regenerates affected artifacts" do
    meeting = Meeting.create!(
      body_name: "Room Tax Commission Meeting",
      meeting_type: "regular",
      starts_at: Time.zone.parse("2026-06-23 16:00:00"),
      status: "upcoming",
      detail_page_url: "http://example.com/rtc"
    )
    item = AgendaItem.create!(meeting: meeting, title: "BUDGET REVIEW", order_index: 1, kind: "item")

    old_topic = Topic.create!(name: "city budget", status: "approved", review_status: "approved", resident_impact_score: 4, last_activity_at: meeting.starts_at)
    new_topic = Topic.create!(name: "room tax budget", status: "approved", review_status: "approved")
    AgendaItemTopic.create!(agenda_item: item, topic: old_topic)
    TopicSummary.create!(topic: old_topic, meeting: meeting, content: "stale", summary_type: "topic_digest", generation_data: {})

    extract_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Finance",
        "tags" => [ "room tax budget" ],
        "topic_worthy" => true,
        "confidence" => 0.9
      } ]
    }.to_json

    summary_response = {
      "headline" => "Room tax budget review is upcoming",
      "factual_record" => [],
      "resident_impact" => { "score" => 2, "rationale" => "Commission-specific budget review" }
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_topics, extract_response do |_text, **kwargs|
      kwargs[:meeting_context].include?("Room Tax Commission")
    end
    mock_ai.expect :analyze_topic_summary, summary_response do |context, **_kwargs|
      context[:topic_metadata][:id] == new_topic.id
    end
    mock_ai.expect :render_topic_summary, "## Room tax budget\nCommission budget review" do |_analysis_json, **_kwargs|
      true
    end
    mock_ai.expect :analyze_topic_briefing, {
      "headline" => "Room tax budget review is upcoming",
      "editorial_analysis" => { "current_state" => "Upcoming commission budget review" },
      "factual_record" => [],
      "resident_impact" => { "score" => 2, "rationale" => "Commission-specific" }
    }.to_json do |context|
      context[:topic_metadata][:id].in?([ old_topic.id, new_topic.id ])
    end
    mock_ai.expect :render_topic_briefing, { "editorial_content" => "Editorial", "record_content" => "Record" } do |_arg|
      true
    end
    mock_ai.expect :analyze_topic_briefing, {
      "headline" => "City budget is no longer active from this meeting",
      "editorial_analysis" => { "current_state" => "No current room tax link" },
      "factual_record" => [],
      "resident_impact" => { "score" => 2, "rationale" => "No current link" }
    }.to_json do |context|
      context[:topic_metadata][:id].in?([ old_topic.id, new_topic.id ])
    end
    mock_ai.expect :render_topic_briefing, { "editorial_content" => "Editorial", "record_content" => "Record" } do |_arg|
      true
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    output = StringIO.new

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        $stdout = output
        Rake::Task["topics:reanalyze_meeting"].invoke(meeting.id.to_s)
      ensure
        $stdout = STDOUT
      end
    end

    item.reload
    assert_equal [ new_topic.id ], item.topics.pluck(:id)
    assert_nil TopicSummary.find_by(topic: old_topic, meeting: meeting)
    assert TopicSummary.find_by(topic: new_topic, meeting: meeting)
    assert_includes output.string, "Before topic ids: [#{old_topic.id}]"
    assert_includes output.string, "After topic ids: [#{new_topic.id}]"
    mock_ai.verify
  end
end
```

- [ ] **Step 2: Run task test and verify it fails**

Run:

```bash
bin/rails test test/tasks/topic_reanalysis_task_test.rb
```

Expected: FAIL because `topics:reanalyze_meeting` is not defined.

- [ ] **Step 3: Implement the rake task**

Create `lib/tasks/topic_reanalysis.rake` with:

```ruby
namespace :topics do
  desc "Surgically rerun topic extraction and downstream topic analysis for one meeting"
  task :reanalyze_meeting, [ :meeting_id ] => :environment do |_task, args|
    meeting_id = args[:meeting_id].presence || ENV["MEETING_ID"]
    abort "Usage: bin/rails 'topics:reanalyze_meeting[MEETING_ID]'" if meeting_id.blank?

    meeting = Meeting.find(meeting_id)
    items = meeting.agenda_items.substantive.order(:order_index)

    before_topic_ids = AgendaItemTopic.where(agenda_item_id: items.select(:id)).distinct.pluck(:topic_id).sort
    puts "Before topic ids: #{before_topic_ids.inspect}"

    AgendaItemTopic.where(agenda_item_id: items.select(:id)).destroy_all
    ExtractTopicsJob.perform_now(meeting.id)

    after_topic_ids = AgendaItemTopic.where(agenda_item_id: items.select(:id)).distinct.pluck(:topic_id).sort
    puts "After topic ids: #{after_topic_ids.inspect}"

    affected_topic_ids = (before_topic_ids | after_topic_ids).sort
    puts "Affected topic ids: #{affected_topic_ids.inspect}"

    remove_stale_topic_summaries(meeting, after_topic_ids)
    regenerate_topic_summaries(meeting, after_topic_ids)
    regenerate_continuity(affected_topic_ids)
    regenerate_briefings(meeting, affected_topic_ids)

    selector_ids = GeneratedImages::HomepageTopicSelector.new.call.map(&:id)
    wire_ids = Topic.reusable
      .where("resident_impact_score >= ?", HomeController::WIRE_MIN_IMPACT)
      .where("last_activity_at > ?", HomeController::ACTIVITY_WINDOW.ago)
      .order(resident_impact_score: :desc, last_activity_at: :desc, id: :desc)
      .limit(HomeController::WIRE_CARD_COUNT + HomeController::WIRE_ROW_LIMIT)
      .pluck(:id)

    puts "Homepage top story candidate ids: #{selector_ids.inspect}"
    puts "Homepage wire candidate ids: #{wire_ids.inspect}"
    puts "Topic 189 on homepage: #{(selector_ids | wire_ids).include?(189)}"
  end

  def remove_stale_topic_summaries(meeting, after_topic_ids)
    TopicSummary.where(meeting: meeting).where.not(topic_id: after_topic_ids).destroy_all
  end

  def regenerate_topic_summaries(meeting, after_topic_ids)
    ai_service = Ai::OpenAiService.new
    retrieval_service = RetrievalService.new

    Topic.approved.where(id: after_topic_ids).find_each do |topic|
      query = Topics::RetrievalQueryBuilder.new(topic, meeting).build_query
      chunks = retrieval_service.retrieve_topic_context(topic: topic, query_text: query, limit: 5, max_chars: 6000)
      formatted_context = retrieval_service.format_topic_context(chunks)
      context_json = Topics::SummaryContextBuilder.new(topic, meeting).build_context_json(kb_context_chunks: formatted_context)
      analysis_json_str = ai_service.analyze_topic_summary(context_json, source: topic)
      analysis_json = JSON.parse(analysis_json_str)
      markdown = ai_service.render_topic_summary(analysis_json.to_json, source: topic)

      summary = TopicSummary.find_or_initialize_by(topic: topic, meeting: meeting, summary_type: "topic_digest")
      summary.content = markdown
      summary.generation_data = analysis_json
      summary.save!

      impact = analysis_json["resident_impact"]
      score = impact["score"].to_i if impact.is_a?(Hash)
      topic.update_resident_impact_from_ai(score) if score&.between?(1, 5)
    end
  end

  def regenerate_continuity(topic_ids)
    topic_ids.each do |topic_id|
      Topics::UpdateContinuityJob.perform_now(topic_id: topic_id)
    end
  end

  def regenerate_briefings(meeting, topic_ids)
    topic_ids.each do |topic_id|
      Topics::GenerateTopicBriefingJob.perform_now(topic_id: topic_id, meeting_id: meeting.id)
    end
  end
end
```

- [ ] **Step 4: Run task test**

Run:

```bash
bin/rails test test/tasks/topic_reanalysis_task_test.rb
```

Expected: PASS.

---

### Task 4: Run full targeted validation before live reanalysis

**Files:**
- No source changes expected.

- [ ] **Step 1: Run all changed test files**

Run:

```bash
bin/rails test test/services/ai/open_ai_service_extract_topics_test.rb test/jobs/extract_topics_job_test.rb test/tasks/topic_reanalysis_task_test.rb
```

Expected: PASS.

- [ ] **Step 2: Run lint on changed Ruby files**

Run:

```bash
bin/rubocop app/services/ai/open_ai_service.rb app/jobs/extract_topics_job.rb lib/prompt_template_data.rb lib/tasks/topic_reanalysis.rake test/services/ai/open_ai_service_extract_topics_test.rb test/jobs/extract_topics_job_test.rb test/tasks/topic_reanalysis_task_test.rb
```

Expected: no offenses.

---

### Task 5: Perform surgical reanalysis for meeting 216

**Files:**
- Runtime database changes only.

- [ ] **Step 1: Capture pre-reanalysis state**

Run:

```bash
bin/rails runner 'meeting = Meeting.find(216); puts({meeting_id: meeting.id, body_name: meeting.body_name, starts_at: meeting.starts_at, topic_links: AgendaItemTopic.joins(:agenda_item, :topic).where(agenda_items: { meeting_id: meeting.id }).order("agenda_items.order_index", "topics.id").pluck("agenda_items.id", "agenda_items.title", "topics.id", "topics.name")}.to_json)'
```

Expected: output includes agenda item `3029`, `BUDGET REVIEW`, and topic `189` before the fix.

- [ ] **Step 2: Run surgical reanalysis**

Run:

```bash
bin/rails 'topics:reanalyze_meeting[216]'
```

Expected:

- Prints `Before topic ids:`.
- Prints `After topic ids:`.
- Prints `Affected topic ids:`.
- Does not crash.
- Ideally prints `Topic 189 on homepage: false`.

- [ ] **Step 3: Capture post-reanalysis links**

Run:

```bash
bin/rails runner 'meeting = Meeting.find(216); puts({meeting_id: meeting.id, topic_links: AgendaItemTopic.joins(:agenda_item, :topic).where(agenda_items: { meeting_id: meeting.id }).order("agenda_items.order_index", "topics.id").pluck("agenda_items.id", "agenda_items.title", "topics.id", "topics.name")}.to_json)'
```

Expected: agenda item `3029` is no longer linked to topic `189` unless the reanalysis found explicit citywide-budget evidence in the record.

---

### Task 6: Verify homepage and decide whether optional guardrail is needed

**Files:**
- No source changes expected unless verification fails.

- [ ] **Step 1: Verify top story selector**

Run:

```bash
bin/rails runner 'ids = GeneratedImages::HomepageTopicSelector.new.call.map { |t| [t.id, t.name, t.resident_impact_score, t.last_activity_at] }; puts ids.to_json; abort("topic 189 still in top stories") if ids.any? { |row| row[0] == 189 }'
```

Expected: command exits successfully and topic `189` is absent.

- [ ] **Step 2: Verify homepage wire query**

Run:

```bash
bin/rails runner 'topics = Topic.reusable.where("resident_impact_score >= ?", HomeController::WIRE_MIN_IMPACT).where("last_activity_at > ?", HomeController::ACTIVITY_WINDOW.ago).order(resident_impact_score: :desc, last_activity_at: :desc, id: :desc).limit(HomeController::WIRE_CARD_COUNT + HomeController::WIRE_ROW_LIMIT).map { |t| [t.id, t.name, t.resident_impact_score, t.last_activity_at] }; puts topics.to_json; abort("topic 189 still in wire") if topics.any? { |row| row[0] == 189 }'
```

Expected: command exits successfully and topic `189` is absent.

- [ ] **Step 3: Stop if verification passes**

If Steps 1 and 2 pass, do not implement any homepage guardrail.

- [ ] **Step 4: If verification fails, pause for design update**

If topic `189` still appears after corrected extraction and reanalysis, do not patch homepage ranking ad hoc. Report the exact remaining reason: topic links, `last_activity_at`, `resident_impact_score`, and selected query. Then update the design before implementing a narrow guardrail.

---

### Task 7: Final verification and review

**Files:**
- Review changed files only.

- [ ] **Step 1: Run targeted tests**

Run:

```bash
bin/rails test test/services/ai/open_ai_service_extract_topics_test.rb test/jobs/extract_topics_job_test.rb test/tasks/topic_reanalysis_task_test.rb
```

Expected: PASS.

- [ ] **Step 2: Run lint**

Run:

```bash
bin/rubocop app/services/ai/open_ai_service.rb app/jobs/extract_topics_job.rb lib/prompt_template_data.rb lib/tasks/topic_reanalysis.rake test/services/ai/open_ai_service_extract_topics_test.rb test/jobs/extract_topics_job_test.rb test/tasks/topic_reanalysis_task_test.rb
```

Expected: no offenses.

- [ ] **Step 3: Inspect git diff**

Run:

```bash
git diff -- app/services/ai/open_ai_service.rb app/jobs/extract_topics_job.rb lib/prompt_template_data.rb lib/tasks/topic_reanalysis.rake test/services/ai/open_ai_service_extract_topics_test.rb test/jobs/extract_topics_job_test.rb test/tasks/topic_reanalysis_task_test.rb docs/superpowers/specs/2026-06-16-committee-scoped-topic-extraction-design.md docs/superpowers/plans/2026-06-16-committee-scoped-topic-extraction.md
```

Expected: only scoped prompt/context, reanalysis task, tests, and docs changes.
