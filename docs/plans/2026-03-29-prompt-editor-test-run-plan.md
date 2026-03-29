# Prompt Editor Test Run — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let admins see recent real inputs/outputs for each prompt template and test prompt edits against that data before saving.

**Architecture:** New `PromptRun` model captures every OpenAI API call (interpolated messages, response, metadata). Edit page gains an "Examples" tab showing recent runs with a "Test with this example" button that re-runs the prompt with edited text and displays old vs. new output side-by-side.

**Tech Stack:** Rails 8.1, PostgreSQL (jsonb), Stimulus, Turbo

**Design spec:** `docs/plans/2026-03-29-prompt-editor-test-run-design.md`

---

## File Map

### New files
| File | Responsibility |
|------|---------------|
| `db/migrate/TIMESTAMP_create_prompt_runs.rb` | Migration |
| `app/models/prompt_run.rb` | Model + retention pruning |
| `test/models/prompt_run_test.rb` | Model tests |
| `app/views/admin/prompt_templates/_examples_tab.html.erb` | Examples tab content |
| `app/views/admin/prompt_templates/_prompt_run_card.html.erb` | Individual run card (collapsible) |
| `app/views/admin/prompt_templates/_test_comparison.html.erb` | Side-by-side old/new output |

### Modified files
| File | Changes |
|------|---------|
| `app/services/ai/open_ai_service.rb` | Add `record_prompt_run`, `source:` + `placeholder_values` capture, timing |
| `app/controllers/admin/prompt_templates_controller.rb` | Add `test_run` action, update `edit` to load examples |
| `app/views/admin/prompt_templates/edit.html.erb` | Add Examples tab button + panel |
| `app/javascript/controllers/prompt_editor_controller.js` | Add `testRun`, `toggleRunCard` actions |
| `config/routes.rb` | Add `post :test_run` member route |
| `app/assets/stylesheets/application.css` | Styles for examples tab + comparison |
| `app/jobs/summarize_meeting_job.rb` | Pass `source: meeting` to OpenAiService calls |
| `app/jobs/extract_topics_job.rb` | Pass `source: meeting` to OpenAiService calls |
| `app/jobs/extract_votes_job.rb` | Pass `source: meeting` to OpenAiService calls |
| `app/jobs/extract_committee_members_job.rb` | Pass `source: meeting` to OpenAiService calls |
| `app/jobs/topics/generate_topic_briefing_job.rb` | Pass `source: topic` to OpenAiService calls |
| `app/jobs/topics/generate_description_job.rb` | Pass `source: topic` to OpenAiService calls |
| `app/services/topics/triage_tool.rb` | Pass `source: nil` (no change needed, just for completeness) |
| `test/controllers/admin/prompt_templates_controller_test.rb` | Add test_run tests |

---

## Task 1: Create PromptRun model and migration

**Files:**
- Create: `db/migrate/TIMESTAMP_create_prompt_runs.rb`
- Create: `app/models/prompt_run.rb`
- Create: `test/models/prompt_run_test.rb`

- [ ] **Step 1: Write the model test**

Create `test/models/prompt_run_test.rb`:

```ruby
require "test_helper"

class PromptRunTest < ActiveSupport::TestCase
  test "creates a prompt run with valid attributes" do
    run = PromptRun.create!(
      prompt_template_key: "extract_votes",
      model_name: "gpt-5.2",
      messages: [
        { "role" => "system", "content" => "You are a vote extractor" },
        { "role" => "user", "content" => "Extract votes from: ..." }
      ],
      response_body: '{"motions": []}',
      response_format: "json_object",
      temperature: 0.1,
      duration_ms: 1500,
      placeholder_values: { "text" => "some meeting text" }
    )

    assert run.persisted?
    assert_equal "extract_votes", run.prompt_template_key
    assert_equal 2, run.messages.size
  end

  test "requires prompt_template_key" do
    run = PromptRun.new(model_name: "gpt-5.2", messages: [], response_body: "x")
    assert_not run.valid?
    assert_includes run.errors[:prompt_template_key], "can't be blank"
  end

  test "requires model_name" do
    run = PromptRun.new(prompt_template_key: "x", messages: [], response_body: "x")
    assert_not run.valid?
    assert_includes run.errors[:model_name], "can't be blank"
  end

  test "requires response_body" do
    run = PromptRun.new(prompt_template_key: "x", model_name: "gpt-5.2", messages: [])
    assert_not run.valid?
    assert_includes run.errors[:response_body], "can't be blank"
  end

  test "polymorphic source association" do
    meeting = meetings(:one) rescue nil
    skip "No meeting fixture available" unless meeting

    run = PromptRun.create!(
      prompt_template_key: "analyze_meeting_content",
      model_name: "gpt-5.2",
      messages: [{ "role" => "user", "content" => "test" }],
      response_body: "{}",
      source: meeting
    )

    assert_equal "Meeting", run.source_type
    assert_equal meeting.id, run.source_id
  end

  test "prunes old runs keeping most recent 10 per key" do
    12.times do |i|
      PromptRun.create!(
        prompt_template_key: "extract_votes",
        model_name: "gpt-5.2",
        messages: [{ "role" => "user", "content" => "run #{i}" }],
        response_body: "result #{i}"
      )
    end

    assert_equal 10, PromptRun.where(prompt_template_key: "extract_votes").count
  end

  test "pruning does not affect other template keys" do
    12.times do |i|
      PromptRun.create!(
        prompt_template_key: "extract_votes",
        model_name: "gpt-5.2",
        messages: [{ "role" => "user", "content" => "run #{i}" }],
        response_body: "result #{i}"
      )
    end

    other = PromptRun.create!(
      prompt_template_key: "extract_topics",
      model_name: "gpt-5.2",
      messages: [{ "role" => "user", "content" => "other" }],
      response_body: "other result"
    )

    assert other.persisted?
    assert_equal 1, PromptRun.where(prompt_template_key: "extract_topics").count
  end

  test "recent scope orders by created_at desc" do
    old = PromptRun.create!(
      prompt_template_key: "extract_votes",
      model_name: "gpt-5.2",
      messages: [{ "role" => "user", "content" => "old" }],
      response_body: "old",
      created_at: 2.hours.ago
    )
    new_run = PromptRun.create!(
      prompt_template_key: "extract_votes",
      model_name: "gpt-5.2",
      messages: [{ "role" => "user", "content" => "new" }],
      response_body: "new"
    )

    assert_equal new_run, PromptRun.where(prompt_template_key: "extract_votes").recent.first
  end

  test "for_template scope filters by key" do
    PromptRun.create!(
      prompt_template_key: "extract_votes",
      model_name: "gpt-5.2",
      messages: [{ "role" => "user", "content" => "a" }],
      response_body: "a"
    )
    PromptRun.create!(
      prompt_template_key: "extract_topics",
      model_name: "gpt-5.2",
      messages: [{ "role" => "user", "content" => "b" }],
      response_body: "b"
    )

    assert_equal 1, PromptRun.for_template("extract_votes").count
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/prompt_run_test.rb`
Expected: Error — `PromptRun` model and table don't exist yet.

- [ ] **Step 3: Create migration**

Run: `bin/rails generate migration CreatePromptRuns`

Then edit the generated migration file:

```ruby
class CreatePromptRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :prompt_runs do |t|
      t.string :prompt_template_key, null: false
      t.string :model_name, null: false
      t.jsonb :messages, null: false, default: []
      t.text :response_body, null: false
      t.string :response_format
      t.float :temperature
      t.integer :duration_ms
      t.jsonb :placeholder_values
      t.string :source_type
      t.bigint :source_id
      t.datetime :created_at, null: false
    end

    add_index :prompt_runs, [:prompt_template_key, :created_at]
    add_index :prompt_runs, [:source_type, :source_id]
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 4: Create the model**

Create `app/models/prompt_run.rb`:

```ruby
class PromptRun < ApplicationRecord
  belongs_to :source, polymorphic: true, optional: true

  validates :prompt_template_key, presence: true
  validates :model_name, presence: true
  validates :response_body, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :for_template, ->(key) { where(prompt_template_key: key) }

  after_create :prune_old_runs

  # Display label for the source record (used in the examples tab)
  def source_label
    case source
    when Meeting
      "#{source.body_name} — #{source.starts_at&.strftime('%b %d, %Y')}"
    when Topic
      source.name
    else
      source_type.present? ? "#{source_type} ##{source_id}" : "No source"
    end
  end

  private

  def prune_old_runs
    old_ids = PromptRun
      .where(prompt_template_key: prompt_template_key)
      .order(created_at: :desc)
      .offset(10)
      .pluck(:id)

    PromptRun.where(id: old_ids).delete_all if old_ids.any?
  end
end
```

- [ ] **Step 5: Run tests and verify they pass**

Run: `bin/rails test test/models/prompt_run_test.rb`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add db/migrate/*_create_prompt_runs.rb app/models/prompt_run.rb test/models/prompt_run_test.rb db/schema.rb
git commit -m "feat: add PromptRun model for capturing API call history"
```

---

## Task 2: Record prompt runs in OpenAiService

**Files:**
- Modify: `app/services/ai/open_ai_service.rb`

- [ ] **Step 1: Add `record_prompt_run` private method and update `extract_votes` as first example**

In `app/services/ai/open_ai_service.rb`, add the private helper method after `prepare_committee_context` (line 445), and update `extract_votes` (lines 36–54) to capture timing, placeholder values, and record the run:

Add to private section (after line 445):

```ruby
def record_prompt_run(template_key:, messages:, response_content:, model:, response_format: nil, temperature: nil, duration_ms: nil, source: nil, placeholder_values: nil)
  PromptRun.create!(
    prompt_template_key: template_key,
    model_name: model,
    messages: messages,
    response_body: response_content,
    response_format: response_format,
    temperature: temperature,
    duration_ms: duration_ms,
    source: source,
    placeholder_values: placeholder_values
  )
rescue => e
  Rails.logger.warn("Failed to record prompt run for #{template_key}: #{e.message}")
end
```

Replace `extract_votes` method (lines 36–54) with:

```ruby
def extract_votes(text, source: nil)
  template = PromptTemplate.find_by!(key: "extract_votes")
  system_role = template.system_role
  placeholders = { text: text.truncate(50_000) }
  prompt = template.interpolate(**placeholders)
  model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

  messages = [
    (system_role.present? ? { role: "system", content: system_role } : nil),
    { role: "user", content: prompt }
  ].compact

  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  response = @client.chat(
    parameters: {
      model: model,
      response_format: { type: "json_object" },
      messages: messages,
      temperature: 0.1
    }
  )
  duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

  content = response.dig("choices", 0, "message", "content")

  record_prompt_run(
    template_key: "extract_votes",
    messages: messages,
    response_content: content,
    model: model,
    response_format: "json_object",
    temperature: 0.1,
    duration_ms: duration_ms,
    source: source,
    placeholder_values: placeholders.transform_keys(&:to_s)
  )

  content
end
```

- [ ] **Step 2: Run tests to verify nothing broke**

Run: `bin/rails test`
Expected: All tests pass. (The `source:` keyword is optional so existing callers are unaffected.)

- [ ] **Step 3: Update `extract_committee_members`**

Replace `extract_committee_members` method (lines 56–73) with:

```ruby
def extract_committee_members(text, source: nil)
  template = PromptTemplate.find_by!(key: "extract_committee_members")
  system_role = template.system_role
  placeholders = { text: text.truncate(50_000) }
  prompt = template.interpolate(**placeholders)
  model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

  messages = [
    (system_role.present? ? { role: "system", content: system_role } : nil),
    { role: "user", content: prompt }
  ].compact

  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  response = @client.chat(
    parameters: {
      model: model,
      response_format: { type: "json_object" },
      messages: messages
    }
  )
  duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

  content = response.dig("choices", 0, "message", "content")

  record_prompt_run(
    template_key: "extract_committee_members",
    messages: messages,
    response_content: content,
    model: model,
    response_format: "json_object",
    duration_ms: duration_ms,
    source: source,
    placeholder_values: placeholders.transform_keys(&:to_s)
  )

  content
end
```

- [ ] **Step 4: Update `extract_topics`**

Replace `extract_topics` method (lines 75–100) with:

```ruby
def extract_topics(items_text, community_context: "", existing_topics: [], meeting_documents_context: "", source: nil)
  existing_topics_list = existing_topics.join("\n")

  template = PromptTemplate.find_by!(key: "extract_topics")
  system_role = template.system_role
  placeholders = {
    items_text: items_text.truncate(50_000),
    community_context: community_context,
    existing_topics: existing_topics_list,
    meeting_documents_context: meeting_documents_context.to_s.truncate(30_000, separator: " ")
  }
  prompt = template.interpolate(**placeholders)
  model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

  messages = [
    (system_role.present? ? { role: "system", content: system_role } : nil),
    { role: "user", content: prompt }
  ].compact

  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  response = @client.chat(
    parameters: {
      model: model,
      response_format: { type: "json_object" },
      messages: messages,
      temperature: 0.1
    }
  )
  duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

  content = response.dig("choices", 0, "message", "content")

  record_prompt_run(
    template_key: "extract_topics",
    messages: messages,
    response_content: content,
    model: model,
    response_format: "json_object",
    temperature: 0.1,
    duration_ms: duration_ms,
    source: source,
    placeholder_values: placeholders.transform_keys(&:to_s)
  )

  content
end
```

- [ ] **Step 5: Update `refine_catchall_topic`**

Replace `refine_catchall_topic` method (lines 102–126) with:

```ruby
def refine_catchall_topic(item_title:, item_summary:, catchall_topic:, document_text:, existing_topics: [], source: nil)
  template = PromptTemplate.find_by!(key: "refine_catchall_topic")
  system_role = template.system_role
  placeholders = {
    item_title: item_title,
    item_summary: item_summary.to_s,
    catchall_topic: catchall_topic,
    document_text: document_text.to_s.truncate(6000, separator: " "),
    existing_topics: existing_topics.join(", ")
  }
  prompt = template.interpolate(**placeholders)
  model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

  messages = [
    (system_role.present? ? { role: "system", content: system_role } : nil),
    { role: "user", content: prompt }
  ].compact

  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  response = @client.chat(
    parameters: {
      model: model,
      response_format: { type: "json_object" },
      messages: messages,
      temperature: 0.1
    }
  )
  duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

  content = response.dig("choices", 0, "message", "content")

  record_prompt_run(
    template_key: "refine_catchall_topic",
    messages: messages,
    response_content: content,
    model: model,
    response_format: "json_object",
    temperature: 0.1,
    duration_ms: duration_ms,
    source: source,
    placeholder_values: placeholders.transform_keys(&:to_s)
  )

  content
end
```

- [ ] **Step 6: Update `re_extract_item_topics`**

Replace `re_extract_item_topics` method (lines 128–152) with:

```ruby
def re_extract_item_topics(item_title:, item_summary:, document_text:, broad_topic_name:, existing_topics: [], source: nil)
  template = PromptTemplate.find_by!(key: "re_extract_item_topics")
  system_role = template.system_role
  placeholders = {
    item_title: item_title,
    item_summary: item_summary.to_s,
    document_text: document_text.to_s.truncate(6000, separator: " "),
    broad_topic_name: broad_topic_name,
    existing_topics: existing_topics.join(", ")
  }
  prompt = template.interpolate(**placeholders)
  model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

  messages = [
    (system_role.present? ? { role: "system", content: system_role } : nil),
    { role: "user", content: prompt }
  ].compact

  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  response = @client.chat(
    parameters: {
      model: model,
      response_format: { type: "json_object" },
      messages: messages,
      temperature: 0.1
    }
  )
  duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

  content = response.dig("choices", 0, "message", "content")

  record_prompt_run(
    template_key: "re_extract_item_topics",
    messages: messages,
    response_content: content,
    model: model,
    response_format: "json_object",
    temperature: 0.1,
    duration_ms: duration_ms,
    source: source,
    placeholder_values: placeholders.transform_keys(&:to_s)
  )

  content
end
```

- [ ] **Step 7: Update `triage_topics` (OpenAI path only)**

In the `triage_topics` method, update the `else` branch (OpenAI path, around lines 209-226). Add `source: nil` param to method signature and recording after the API call. The Gemini branch is left unchanged (no template to record against).

Change method signature to `def triage_topics(context_json, source: nil)` and update the else branch:

```ruby
else
  template = PromptTemplate.find_by!(key: "triage_topics")
  system_role = template.system_role
  placeholders = { context_json: context_json.to_json }
  prompt = template.interpolate(**placeholders)
  model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

  messages = [
    (system_role.present? ? { role: "system", content: system_role } : nil),
    { role: "user", content: prompt }
  ].compact

  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  response = @client.chat(
    parameters: {
      model: model,
      response_format: { type: "json_object" },
      messages: messages,
      temperature: 0.1
    }
  )
  duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

  content = response.dig("choices", 0, "message", "content")

  record_prompt_run(
    template_key: "triage_topics",
    messages: messages,
    response_content: content,
    model: model,
    response_format: "json_object",
    temperature: 0.1,
    duration_ms: duration_ms,
    source: source,
    placeholder_values: placeholders.transform_keys(&:to_s)
  )

  content
end
```

- [ ] **Step 8: Update `analyze_topic_summary`**

Replace `analyze_topic_summary` method (lines 229–251) with:

```ruby
def analyze_topic_summary(context_json, source: nil)
  template = PromptTemplate.find_by!(key: "analyze_topic_summary")
  committee_ctx = prepare_committee_context
  system_role = template.interpolate_system_role(committee_context: committee_ctx)
  placeholders = {
    committee_context: committee_ctx,
    context_json: context_json.to_json
  }
  prompt = template.interpolate(**placeholders)
  model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

  messages = [
    { role: "system", content: system_role },
    { role: "user", content: prompt }
  ]

  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  response = @client.chat(
    parameters: {
      model: model,
      response_format: { type: "json_object" },
      messages: messages,
      temperature: 0.1
    }
  )
  duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

  content = response.dig("choices", 0, "message", "content")

  record_prompt_run(
    template_key: "analyze_topic_summary",
    messages: messages,
    response_content: content,
    model: model,
    response_format: "json_object",
    temperature: 0.1,
    duration_ms: duration_ms,
    source: source,
    placeholder_values: placeholders.transform_keys(&:to_s)
  )

  content
end
```

- [ ] **Step 9: Update `render_topic_summary`**

Replace `render_topic_summary` method (lines 253–271) with:

```ruby
def render_topic_summary(plan_json, source: nil)
  template = PromptTemplate.find_by!(key: "render_topic_summary")
  system_role = template.interpolate_system_role
  placeholders = { plan_json: plan_json.to_s }
  prompt = template.interpolate(**placeholders)
  model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

  messages = [
    { role: "system", content: system_role },
    { role: "user", content: prompt }
  ]

  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  response = @client.chat(
    parameters: {
      model: model,
      messages: messages,
      temperature: 0.2
    }
  )
  duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

  content = response.dig("choices", 0, "message", "content")

  record_prompt_run(
    template_key: "render_topic_summary",
    messages: messages,
    response_content: content,
    model: model,
    temperature: 0.2,
    duration_ms: duration_ms,
    source: source,
    placeholder_values: placeholders.transform_keys(&:to_s)
  )

  content
end
```

- [ ] **Step 10: Update `analyze_topic_briefing`**

Replace `analyze_topic_briefing` method (lines 273–295) with:

```ruby
def analyze_topic_briefing(context, source: nil)
  template = PromptTemplate.find_by!(key: "analyze_topic_briefing")
  committee_ctx = prepare_committee_context
  system_role = template.interpolate_system_role(committee_context: committee_ctx)
  placeholders = {
    committee_context: committee_ctx,
    context: context.to_json
  }
  prompt = template.interpolate(**placeholders)
  model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

  messages = [
    { role: "system", content: system_role },
    { role: "user", content: prompt }
  ]

  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  response = @client.chat(
    parameters: {
      model: model,
      response_format: { type: "json_object" },
      messages: messages,
      temperature: 0.1
    }
  )
  duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

  content = response.dig("choices", 0, "message", "content")

  record_prompt_run(
    template_key: "analyze_topic_briefing",
    messages: messages,
    response_content: content,
    model: model,
    response_format: "json_object",
    temperature: 0.1,
    duration_ms: duration_ms,
    source: source,
    placeholder_values: placeholders.transform_keys(&:to_s)
  )

  content
end
```

- [ ] **Step 11: Update `render_topic_briefing`**

Replace `render_topic_briefing` method (lines 297–318) with:

```ruby
def render_topic_briefing(analysis_json, source: nil)
  template = PromptTemplate.find_by!(key: "render_topic_briefing")
  system_role = template.interpolate_system_role
  placeholders = { analysis_json: analysis_json.to_s }
  prompt = template.interpolate(**placeholders)
  model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

  messages = [
    { role: "system", content: system_role },
    { role: "user", content: prompt }
  ]

  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  response = @client.chat(
    parameters: {
      model: model,
      response_format: { type: "json_object" },
      messages: messages,
      temperature: 0.2
    }
  )
  duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

  content = response.dig("choices", 0, "message", "content")

  record_prompt_run(
    template_key: "render_topic_briefing",
    messages: messages,
    response_content: content,
    model: model,
    response_format: "json_object",
    temperature: 0.2,
    duration_ms: duration_ms,
    source: source,
    placeholder_values: placeholders.transform_keys(&:to_s)
  )

  JSON.parse(content)
rescue JSON::ParserError
  { "editorial_content" => "", "record_content" => "" }
end
```

- [ ] **Step 12: Update `generate_briefing_interim`**

Replace `generate_briefing_interim` method (lines 320–346) with:

```ruby
def generate_briefing_interim(context, source: nil)
  template = PromptTemplate.find_by!(key: "generate_briefing_interim")
  system_role = template.system_role
  placeholders = {
    topic_name: context[:topic_name].to_s,
    current_headline: context[:current_headline].to_s,
    meeting_body: context[:meeting_body].to_s,
    meeting_date: context[:meeting_date].to_s,
    agenda_items: context[:agenda_items].to_json
  }
  prompt = template.interpolate(**placeholders)
  model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

  messages = [
    (system_role.present? ? { role: "system", content: system_role } : nil),
    { role: "user", content: prompt }
  ].compact

  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  response = @client.chat(
    parameters: {
      model: model,
      response_format: { type: "json_object" },
      messages: messages
    }
  )
  duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

  content = response.dig("choices", 0, "message", "content")

  record_prompt_run(
    template_key: "generate_briefing_interim",
    messages: messages,
    response_content: content,
    model: model,
    response_format: "json_object",
    duration_ms: duration_ms,
    source: source,
    placeholder_values: placeholders.transform_keys(&:to_s)
  )

  JSON.parse(content)
rescue JSON::ParserError
  { "headline" => context[:current_headline], "upcoming_note" => "" }
end
```

- [ ] **Step 13: Update `generate_topic_description`**

Replace `generate_topic_description` method (lines 348–378) with:

```ruby
def generate_topic_description(topic_context, source: nil)
  topic_name = topic_context[:topic_name]
  agenda_items = topic_context[:agenda_items] || []
  headlines = topic_context[:headlines] || []

  activity_text = agenda_items.map { |ai| "- #{ai[:title]}#{ai[:summary].present? ? ": #{ai[:summary]}" : ""}" }.join("\n")
  headlines_text = headlines.any? ? "\nRecent headlines:\n#{headlines.map { |h| "- #{h}" }.join("\n")}" : ""

  key = agenda_items.size >= 3 ? "generate_topic_description_detailed" : "generate_topic_description_broad"
  template = PromptTemplate.find_by!(key: key)
  system_role = template.system_role
  placeholders = {
    topic_name: topic_name,
    activity_text: activity_text,
    headlines_text: headlines_text
  }
  user_prompt = template.interpolate(**placeholders)
  model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

  messages = [
    (system_role.present? ? { role: "system", content: system_role } : nil),
    { role: "user", content: user_prompt }
  ].compact

  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  response = @client.chat(
    parameters: {
      model: model,
      messages: messages
    }
  )
  duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

  content = response.dig("choices", 0, "message", "content")

  record_prompt_run(
    template_key: key,
    messages: messages,
    response_content: content.to_s,
    model: model,
    duration_ms: duration_ms,
    source: source,
    placeholder_values: placeholders.transform_keys(&:to_s)
  )

  content.present? ? content.strip : nil
end
```

- [ ] **Step 14: Update `analyze_meeting_content`**

Replace `analyze_meeting_content` method (lines 382–406) with:

```ruby
def analyze_meeting_content(doc_text, kb_context, type, source: nil)
  template = PromptTemplate.find_by!(key: "analyze_meeting_content")
  committee_ctx = prepare_committee_context
  system_role = template.interpolate_system_role(committee_context: committee_ctx)
  placeholders = {
    kb_context: kb_context.to_s,
    committee_context: committee_ctx,
    type: type.to_s,
    doc_text: doc_text.truncate(100_000)
  }
  prompt = template.interpolate(**placeholders)
  model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

  messages = [
    { role: "system", content: system_role },
    { role: "user", content: prompt }
  ]

  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  response = @client.chat(
    parameters: {
      model: model,
      response_format: { type: "json_object" },
      messages: messages,
      temperature: 0.1
    }
  )
  duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

  content = response.dig("choices", 0, "message", "content")

  record_prompt_run(
    template_key: "analyze_meeting_content",
    messages: messages,
    response_content: content,
    model: model,
    response_format: "json_object",
    temperature: 0.1,
    duration_ms: duration_ms,
    source: source,
    placeholder_values: placeholders.transform_keys(&:to_s)
  )

  content
end
```

- [ ] **Step 15: Update `render_meeting_summary`**

Replace `render_meeting_summary` private method (lines 485–506) with:

```ruby
def render_meeting_summary(doc_text, plan_json, type, source: nil)
  template = PromptTemplate.find_by!(key: "render_meeting_summary")
  system_role = template.interpolate_system_role
  placeholders = {
    plan_json: plan_json.to_s,
    doc_text: doc_text.truncate(50_000)
  }
  prompt = template.interpolate(**placeholders)
  model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

  messages = [
    { role: "system", content: system_role },
    { role: "user", content: prompt }
  ]

  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  response = @client.chat(
    parameters: {
      model: model,
      messages: messages,
      temperature: 0.2
    }
  )
  duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

  content = response.dig("choices", 0, "message", "content")

  record_prompt_run(
    template_key: "render_meeting_summary",
    messages: messages,
    response_content: content,
    model: model,
    temperature: 0.2,
    duration_ms: duration_ms,
    source: source,
    placeholder_values: placeholders.transform_keys(&:to_s)
  )

  content
end
```

- [ ] **Step 16: Run full test suite**

Run: `bin/rails test`
Expected: All tests pass. All `source:` params are optional so existing callers work unchanged.

- [ ] **Step 17: Commit**

```bash
git add app/services/ai/open_ai_service.rb
git commit -m "feat: record prompt runs in OpenAiService for all API calls"
```

---

## Task 3: Pass source records from jobs to OpenAiService

**Files:**
- Modify: `app/jobs/extract_votes_job.rb` (line ~17)
- Modify: `app/jobs/extract_committee_members_job.rb` (line ~14)
- Modify: `app/jobs/extract_topics_job.rb` (lines ~39, ~118)
- Modify: `app/jobs/summarize_meeting_job.rb` (lines ~27, ~42, ~61, ~74)
- Modify: `app/jobs/topics/generate_topic_briefing_job.rb` (lines ~17, ~21)
- Modify: `app/jobs/topics/generate_description_job.rb` (line ~20)

- [ ] **Step 1: Update `extract_votes_job.rb`**

Change line ~17 from:
```ruby
ai_service.extract_votes(minutes_doc.extracted_text)
```
to:
```ruby
ai_service.extract_votes(minutes_doc.extracted_text, source: meeting)
```

- [ ] **Step 2: Update `extract_committee_members_job.rb`**

Change line ~14 from:
```ruby
ai_service.extract_committee_members(minutes_doc.extracted_text)
```
to:
```ruby
ai_service.extract_committee_members(minutes_doc.extracted_text, source: meeting)
```

- [ ] **Step 3: Update `extract_topics_job.rb`**

Change the `extract_topics` call (line ~39-44) to add `source: meeting`:
```ruby
ai_service.extract_topics(
  items_text,
  community_context: community_context,
  existing_topics: existing_topics,
  meeting_documents_context: meeting_docs_context,
  source: meeting
)
```

Change the `refine_catchall_topic` call (line ~118-124) to add `source: meeting`:
```ruby
ai_service.refine_catchall_topic(
  item_title: item.title,
  item_summary: item.summary,
  catchall_topic: link.topic.name,
  document_text: doc_text,
  existing_topics: existing_topics,
  source: meeting
)
```

- [ ] **Step 4: Update `summarize_meeting_job.rb`**

For `analyze_meeting_content` calls (lines ~27, ~42), add `source: meeting`:
```ruby
ai_service.analyze_meeting_content(minutes_doc.extracted_text, kb_context, "minutes", source: meeting)
```
```ruby
ai_service.analyze_meeting_content(doc_text, kb_context, "packet", source: meeting)
```

For `analyze_topic_summary` call (line ~61), add `source: topic`:
```ruby
ai_service.analyze_topic_summary(context_json, source: topic)
```

For `render_topic_summary` call (line ~74), add `source: topic`:
```ruby
ai_service.render_topic_summary(analysis_json.to_json, source: topic)
```

- [ ] **Step 5: Update `topics/generate_topic_briefing_job.rb`**

For `analyze_topic_briefing` call (line ~17), add `source: topic`:
```ruby
ai_service.analyze_topic_briefing(context, source: topic)
```

For `render_topic_briefing` call (line ~21), add `source: topic`:
```ruby
ai_service.render_topic_briefing(analysis_json.to_json, source: topic)
```

- [ ] **Step 6: Update `topics/generate_description_job.rb`**

Change line ~20 from:
```ruby
Ai::OpenAiService.new.generate_topic_description(context)
```
to:
```ruby
Ai::OpenAiService.new.generate_topic_description(context, source: topic)
```

- [ ] **Step 7: Run tests**

Run: `bin/rails test`
Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
git add app/jobs/
git commit -m "feat: pass source records from jobs to OpenAiService for prompt run tracking"
```

---

## Task 4: Examples tab on the edit page

**Files:**
- Modify: `app/controllers/admin/prompt_templates_controller.rb`
- Modify: `app/views/admin/prompt_templates/edit.html.erb`
- Create: `app/views/admin/prompt_templates/_examples_tab.html.erb`
- Create: `app/views/admin/prompt_templates/_prompt_run_card.html.erb`
- Modify: `app/javascript/controllers/prompt_editor_controller.js`
- Modify: `app/assets/stylesheets/application.css`

- [ ] **Step 1: Write the controller test for edit loading examples**

Add to `test/controllers/admin/prompt_templates_controller_test.rb`:

```ruby
test "edit loads prompt run examples" do
  PromptRun.create!(
    prompt_template_key: @template.key,
    model_name: "gpt-5.2",
    messages: [{ "role" => "user", "content" => "test" }],
    response_body: '{"result": "test"}',
    response_format: "json_object"
  )

  get edit_admin_prompt_template_url(@template)
  assert_response :success
  assert_select "[data-tab='examples']"
end

test "edit shows empty state when no examples exist" do
  get edit_admin_prompt_template_url(@template)
  assert_response :success
  assert_select "[data-tab='examples']"
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/admin/prompt_templates_controller_test.rb`
Expected: Fail — no examples tab exists yet.

- [ ] **Step 3: Update controller edit action to load examples**

In `app/controllers/admin/prompt_templates_controller.rb`, update the `edit` action:

```ruby
def edit
  @versions = @template.versions.recent.limit(20)
  @examples = load_diverse_examples(@template.key)
end
```

Add to private section:

```ruby
def load_diverse_examples(template_key)
  runs = PromptRun.for_template(template_key).recent.limit(10).to_a
  return runs if runs.size <= 5

  # Prefer diversity: one per source, fill remaining with recency
  grouped = runs.group_by { |r| [r.source_type, r.source_id] }
  diverse = grouped.values.map(&:first).sort_by(&:created_at).reverse
  diverse.first(5)
end
```

- [ ] **Step 4: Add Examples tab button to edit view**

In `app/views/admin/prompt_templates/edit.html.erb`, replace the tab-bar div (lines 17-20) with:

```erb
<div class="tab-bar" data-controller="prompt-editor">
  <button class="tab active" data-action="click->prompt-editor#showTab" data-prompt-editor-tab-param="editor">Editor</button>
  <button class="tab" data-action="click->prompt-editor#showTab" data-prompt-editor-tab-param="examples">
    Examples
    <% if @examples.any? %>
      <span class="badge badge--muted"><%= @examples.size %></span>
    <% end %>
  </button>
  <button class="tab" data-action="click->prompt-editor#showTab" data-prompt-editor-tab-param="history">Version History</button>
</div>
```

Add the examples panel before the history panel (before the `<div id="tab-history"` line):

```erb
<div id="tab-examples" data-prompt-editor-target="panel" data-tab="examples" class="hidden">
  <%= render "examples_tab", examples: @examples, template: @template %>
</div>
```

- [ ] **Step 5: Create the examples tab partial**

Create `app/views/admin/prompt_templates/_examples_tab.html.erb`:

```erb
<% if examples.any? %>
  <div class="prompt-examples">
    <% examples.each do |run| %>
      <%= render "prompt_run_card", run: run, template: template %>
    <% end %>
  </div>
<% else %>
  <div class="card">
    <div class="card-body">
      <p class="section-empty">No examples yet. This prompt will capture examples the next time it runs in the pipeline.</p>
    </div>
  </div>
<% end %>
```

- [ ] **Step 6: Create the prompt run card partial**

Create `app/views/admin/prompt_templates/_prompt_run_card.html.erb`:

```erb
<%# Each card is collapsible — header always visible, body toggled %>
<div class="card prompt-run-card" data-prompt-run-id="<%= run.id %>">
  <div class="prompt-run-header" data-action="click->prompt-editor#toggleRunCard">
    <div class="prompt-run-meta">
      <span class="prompt-run-source"><%= run.source_label %></span>
      <span class="prompt-run-details">
        <span class="timestamp"><%= time_ago_in_words(run.created_at) %> ago</span>
        <span class="badge badge--muted"><%= run.model_name %></span>
        <% if run.duration_ms %>
          <span class="timestamp"><%= (run.duration_ms / 1000.0).round(1) %>s</span>
        <% end %>
      </span>
    </div>
    <svg class="prompt-run-chevron" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="16" height="16"><path d="M9 18l6-6-6-6"/></svg>
  </div>

  <div class="prompt-run-body hidden">
    <div class="prompt-run-sections">
      <% run.messages.each do |msg| %>
        <div class="prompt-run-message">
          <h4 class="prompt-run-message-role"><%= msg["role"]&.titleize %></h4>
          <pre class="prompt-run-message-content"><%= msg["content"]&.truncate(5000) %></pre>
        </div>
      <% end %>

      <div class="prompt-run-message">
        <h4 class="prompt-run-message-role">Output</h4>
        <pre class="prompt-run-message-content"><% if run.response_format == "json_object" %><%= JSON.pretty_generate(JSON.parse(run.response_body)).truncate(5000) rescue run.response_body.truncate(5000) %><% else %><%= run.response_body.truncate(5000) %><% end %></pre>
      </div>
    </div>

    <div class="prompt-run-actions">
      <button class="btn btn--primary btn--sm"
              data-action="click->prompt-editor#testRun"
              data-prompt-editor-run-id-param="<%= run.id %>"
              data-prompt-editor-test-url-param="<%= test_run_admin_prompt_template_path(template) %>">
        Test with this example
      </button>
    </div>

    <div class="prompt-run-comparison hidden" id="comparison-<%= run.id %>"></div>
  </div>
</div>
```

- [ ] **Step 7: Add CSS styles for examples tab**

Add to `app/assets/stylesheets/application.css` (at the end):

```css
/* Prompt editor — examples tab */
.prompt-examples {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
}

.prompt-run-card {
  overflow: hidden;
}

.prompt-run-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: var(--space-4);
  cursor: pointer;
  user-select: none;
}

.prompt-run-header:hover {
  background: var(--color-surface-hover, rgba(0, 0, 0, 0.02));
}

.prompt-run-meta {
  display: flex;
  flex-direction: column;
  gap: var(--space-1);
}

.prompt-run-source {
  font-family: var(--font-body);
  font-weight: 600;
  font-size: var(--text-sm);
}

.prompt-run-details {
  display: flex;
  gap: var(--space-3);
  align-items: center;
}

.prompt-run-chevron {
  transition: transform 0.2s;
  flex-shrink: 0;
}

.prompt-run-card.expanded .prompt-run-chevron {
  transform: rotate(90deg);
}

.prompt-run-body {
  border-top: 1px solid var(--color-border);
  padding: var(--space-4);
}

.prompt-run-sections {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
}

.prompt-run-message-role {
  font-family: var(--font-data);
  font-size: var(--text-xs);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--color-text-muted);
  margin-bottom: var(--space-1);
}

.prompt-run-message-content {
  font-family: var(--font-data);
  font-size: var(--text-xs);
  line-height: 1.6;
  background: var(--color-surface-raised, rgba(0, 0, 0, 0.03));
  border: 1px solid var(--color-border);
  border-radius: var(--radius-sm, 4px);
  padding: var(--space-3);
  max-height: 300px;
  overflow-y: auto;
  white-space: pre-wrap;
  word-break: break-word;
}

.prompt-run-actions {
  margin-top: var(--space-4);
  padding-top: var(--space-4);
  border-top: 1px solid var(--color-border);
}

.prompt-run-comparison {
  margin-top: var(--space-4);
}

/* Test comparison side-by-side */
.test-comparison {
  border-top: 1px solid var(--color-border);
  padding-top: var(--space-4);
}

.test-comparison-header {
  font-family: var(--font-display);
  font-size: var(--text-base);
  font-weight: 700;
  text-transform: uppercase;
  margin-bottom: var(--space-3);
}

.test-comparison-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: var(--space-4);
}

@media (max-width: 768px) {
  .test-comparison-grid {
    grid-template-columns: 1fr;
  }
}

.test-comparison-panel h4 {
  font-family: var(--font-data);
  font-size: var(--text-xs);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--color-text-muted);
  margin-bottom: var(--space-2);
}

.test-comparison-panel pre {
  font-family: var(--font-data);
  font-size: var(--text-xs);
  line-height: 1.6;
  background: var(--color-surface-raised, rgba(0, 0, 0, 0.03));
  border: 1px solid var(--color-border);
  border-radius: var(--radius-sm, 4px);
  padding: var(--space-3);
  max-height: 500px;
  overflow-y: auto;
  white-space: pre-wrap;
  word-break: break-word;
}

.test-comparison-error {
  color: var(--color-danger, #c0392b);
  font-family: var(--font-data);
  font-size: var(--text-sm);
  padding: var(--space-3);
  background: var(--color-danger-bg, #fdf0ed);
  border-radius: var(--radius-sm, 4px);
}
```

- [ ] **Step 8: Update Stimulus controller with `toggleRunCard`**

In `app/javascript/controllers/prompt_editor_controller.js`, add the `toggleRunCard` method:

```javascript
toggleRunCard(event) {
  const card = event.currentTarget.closest(".prompt-run-card")
  const body = card.querySelector(".prompt-run-body")
  const isExpanded = card.classList.contains("expanded")

  card.classList.toggle("expanded", !isExpanded)
  body.classList.toggle("hidden", isExpanded)
}
```

- [ ] **Step 9: Run tests**

Run: `bin/rails test test/controllers/admin/prompt_templates_controller_test.rb`
Expected: All tests pass.

- [ ] **Step 10: Commit**

```bash
git add app/controllers/admin/prompt_templates_controller.rb app/views/admin/prompt_templates/ app/javascript/controllers/prompt_editor_controller.js app/assets/stylesheets/application.css test/controllers/admin/prompt_templates_controller_test.rb
git commit -m "feat: add Examples tab to prompt template editor showing recent runs"
```

---

## Task 5: Test run action and comparison view

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/admin/prompt_templates_controller.rb`
- Create: `app/views/admin/prompt_templates/_test_comparison.html.erb`
- Modify: `app/javascript/controllers/prompt_editor_controller.js`
- Modify: `test/controllers/admin/prompt_templates_controller_test.rb`

- [ ] **Step 1: Write the controller test for test_run**

Add to `test/controllers/admin/prompt_templates_controller_test.rb`:

```ruby
test "test_run re-runs prompt and returns comparison" do
  run = PromptRun.create!(
    prompt_template_key: @template.key,
    model_name: "gpt-5.2",
    messages: [
      { "role" => "system", "content" => "You are a test assistant" },
      { "role" => "user", "content" => "Do something with stuff" }
    ],
    response_body: '{"original": true}',
    response_format: "json_object",
    temperature: 0.1,
    placeholder_values: { "thing" => "something", "stuff" => "stuff" }
  )

  # Stub OpenAI client to avoid real API calls
  mock_response = {
    "choices" => [{ "message" => { "content" => '{"test": true}' } }]
  }
  OpenAI::Client.any_instance.stubs(:chat).returns(mock_response)

  post test_run_admin_prompt_template_url(@template), params: {
    prompt_run_id: run.id,
    system_role: "You are an updated assistant",
    instructions: "Do {{thing}} with {{stuff}} differently"
  }, headers: { "Accept" => "text/html" }

  assert_response :success
end

test "test_run returns error for missing prompt run" do
  post test_run_admin_prompt_template_url(@template), params: {
    prompt_run_id: 999999,
    system_role: "test",
    instructions: "test"
  }, headers: { "Accept" => "text/html" }

  assert_response :not_found
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/admin/prompt_templates_controller_test.rb -n "/test_run/"`
Expected: Fail — route and action don't exist yet.

- [ ] **Step 3: Add route**

In `config/routes.rb`, update the prompt_templates resource (lines 69-73):

```ruby
resources :prompt_templates, controller: "admin/prompt_templates", as: :admin_prompt_templates, only: [ :index, :edit, :update ] do
  member do
    get :diff
    post :test_run
  end
end
```

- [ ] **Step 4: Add `test_run` action to controller**

In `app/controllers/admin/prompt_templates_controller.rb`, update `before_action` line 2:

```ruby
before_action :set_template, only: [ :edit, :update, :diff, :test_run ]
```

Add the `test_run` action (after `diff`):

```ruby
def test_run
  @run = PromptRun.find_by(id: params[:prompt_run_id])
  unless @run
    head :not_found
    return
  end

  # Build temporary template with edited text
  edited_system_role = params[:system_role].to_s
  edited_instructions = params[:instructions].to_s

  # Re-interpolate with stored placeholder values
  placeholder_values = (@run.placeholder_values || {}).symbolize_keys
  begin
    new_system_role = replace_template_placeholders(edited_system_role, placeholder_values)
    new_user_prompt = replace_template_placeholders(edited_instructions, placeholder_values)
  rescue KeyError => e
    @error = "Placeholder error: #{e.message}"
    render partial: "test_comparison", locals: { original: @run.response_body, result: nil, error: @error, run: @run, duration_ms: nil, response_format: @run.response_format }
    return
  end

  messages = [
    (new_system_role.present? ? { role: "system", content: new_system_role } : nil),
    { role: "user", content: new_user_prompt }
  ].compact

  model = @template.model_tier == "lightweight" ? Ai::OpenAiService::LIGHTWEIGHT_MODEL : Ai::OpenAiService::DEFAULT_MODEL

  begin
    client = OpenAI::Client.new(access_token: Rails.application.credentials.openai_access_token || ENV["OPENAI_ACCESS_TOKEN"])

    chat_params = {
      model: model,
      messages: messages
    }
    chat_params[:response_format] = { type: @run.response_format } if @run.response_format.present?
    chat_params[:temperature] = @run.temperature if @run.temperature.present?

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = client.chat(parameters: chat_params)
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

    result = response.dig("choices", 0, "message", "content")
    @error = nil
  rescue => e
    result = nil
    @error = "API error: #{e.message}"
    duration_ms = nil
  end

  render partial: "test_comparison", locals: {
    original: @run.response_body,
    result: result,
    error: @error,
    run: @run,
    duration_ms: duration_ms,
    response_format: @run.response_format
  }
end
```

Add to private section:

```ruby
def replace_template_placeholders(text, context)
  text.gsub(/\{\{(\w+)\}\}/) do
    key = $1.to_sym
    if context.key?(key)
      context[key].to_s
    else
      raise KeyError, "Missing placeholder: {{#{$1}}}"
    end
  end
end
```

- [ ] **Step 5: Create the comparison partial**

Create `app/views/admin/prompt_templates/_test_comparison.html.erb`:

```erb
<div class="test-comparison">
  <h3 class="test-comparison-header">Test Results</h3>

  <% if error %>
    <div class="test-comparison-error"><%= error %></div>
  <% else %>
    <% if duration_ms %>
      <p class="timestamp" style="margin-bottom: var(--space-3);">Completed in <%= (duration_ms / 1000.0).round(1) %>s</p>
    <% end %>

    <div class="test-comparison-grid">
      <div class="test-comparison-panel">
        <h4>Original Output</h4>
        <pre><% if run.response_format == "json_object" %><%= JSON.pretty_generate(JSON.parse(original)).truncate(8000) rescue original.truncate(8000) %><% else %><%= original.truncate(8000) %><% end %></pre>
      </div>
      <div class="test-comparison-panel">
        <h4>Test Output</h4>
        <pre><% if run.response_format == "json_object" %><%= JSON.pretty_generate(JSON.parse(result)).truncate(8000) rescue result.truncate(8000) %><% else %><%= result.truncate(8000) %><% end %></pre>
      </div>
    </div>
  <% end %>
</div>
```

- [ ] **Step 6: Add `testRun` to Stimulus controller**

In `app/javascript/controllers/prompt_editor_controller.js`, add the `testRun` method:

```javascript
async testRun(event) {
  event.stopPropagation()
  const runId = event.params.runId
  const testUrl = event.params.testUrl
  const button = event.currentTarget
  const comparisonDiv = document.getElementById(`comparison-${runId}`)

  // Grab current form values (possibly edited, unsaved)
  const systemRole = document.querySelector("textarea[name='prompt_template[system_role]']")?.value || ""
  const instructions = document.querySelector("textarea[name='prompt_template[instructions]']")?.value || ""

  // Show loading state
  const originalText = button.textContent
  button.textContent = "Running..."
  button.disabled = true

  try {
    const response = await fetch(testUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "text/html",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body: new URLSearchParams({
        prompt_run_id: runId,
        system_role: systemRole,
        instructions: instructions
      })
    })

    const html = await response.text()
    // Use template element + replaceChildren for safe DOM insertion
    const tmpl = document.createElement("template")
    tmpl.innerHTML = html
    comparisonDiv.replaceChildren(tmpl.content)
    comparisonDiv.classList.remove("hidden")
    comparisonDiv.scrollIntoView({ behavior: "smooth", block: "start" })
  } catch (err) {
    // Use safe textContent for error display
    const errorDiv = document.createElement("div")
    errorDiv.className = "test-comparison-error"
    errorDiv.textContent = `Request failed: ${err.message}`
    comparisonDiv.replaceChildren(errorDiv)
    comparisonDiv.classList.remove("hidden")
  } finally {
    button.textContent = originalText
    button.disabled = false
  }
}
```

- [ ] **Step 7: Run tests**

Run: `bin/rails test test/controllers/admin/prompt_templates_controller_test.rb`
Expected: All tests pass.

- [ ] **Step 8: Run full test suite**

Run: `bin/rails test`
Expected: All tests pass.

- [ ] **Step 9: Commit**

```bash
git add config/routes.rb app/controllers/admin/prompt_templates_controller.rb app/views/admin/prompt_templates/_test_comparison.html.erb app/javascript/controllers/prompt_editor_controller.js test/controllers/admin/prompt_templates_controller_test.rb
git commit -m "feat: add test run action for previewing prompt changes against real examples"
```

---

## Task 6: Manual smoke test

- [ ] **Step 1: Start the dev server**

Run: `bin/dev`

- [ ] **Step 2: Navigate to prompt templates admin**

Go to `/admin/prompt_templates` and verify the index loads.

- [ ] **Step 3: Click edit on any template**

Verify three tabs show: Editor, Examples, Version History.

- [ ] **Step 4: Check Examples tab**

Click Examples tab. If no pipeline has run since the migration, it should show the empty state message. If runs exist, verify cards display with source labels, timestamps, model names.

- [ ] **Step 5: Expand an example card (if available)**

Click a card header — verify it expands to show system role, user prompt, and output sections. Verify the "Test with this example" button is visible.

- [ ] **Step 6: Test the test run flow (if examples exist)**

Edit the prompt text slightly in the Editor tab, switch to Examples, expand a card, click "Test with this example." Verify spinner shows, then side-by-side comparison appears.

- [ ] **Step 7: Commit any fixes**

If any issues were found during smoke testing, fix and commit.
