# Auto Knowledge Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically populate the knowledgebase with durable civic facts from meeting content, detect cross-meeting patterns, and auto-triage entries — all downstream of the existing pipeline.

**Architecture:** Per-meeting `ExtractKnowledgeJob` runs after `SummarizeMeetingJob`, reads summary + raw text + existing KB, creates proposed entries. `AutoTriageKnowledgeJob` approves/blocks them. Weekly `ExtractKnowledgePatternsJob` finds cross-meeting patterns from accumulated facts. `RetrievalService` labels entries by origin in prompts.

**Tech Stack:** Rails 8.1, OpenAI gpt-5.2, Solid Queue, existing KnowledgeSource/KnowledgeChunk/RetrievalService infrastructure.

**Spec:** `docs/superpowers/specs/2026-04-09-auto-knowledge-extraction-design.md`

---

### Task 1: Migration — Add origin, reasoning, confidence to KnowledgeSource

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_add_extraction_fields_to_knowledge_sources.rb`

- [ ] **Step 1: Generate migration**

Run:
```bash
bin/rails generate migration AddExtractionFieldsToKnowledgeSources origin:string reasoning:text confidence:float
```

- [ ] **Step 2: Edit migration to add defaults and index**

Replace the generated migration body with:

```ruby
class AddExtractionFieldsToKnowledgeSources < ActiveRecord::Migration[8.1]
  def change
    add_column :knowledge_sources, :origin, :string, default: "manual", null: false
    add_column :knowledge_sources, :reasoning, :text
    add_column :knowledge_sources, :confidence, :float

    # Backfill existing status column with "approved" for all existing records
    # (status column exists but was unused — now it drives triage workflow)
    change_column_default :knowledge_sources, :status, from: nil, to: "approved"
    reversible do |dir|
      dir.up do
        execute "UPDATE knowledge_sources SET status = 'approved' WHERE status IS NULL"
        execute "UPDATE knowledge_sources SET origin = 'manual'"
      end
    end

    add_index :knowledge_sources, :origin
    add_index :knowledge_sources, :status
  end
end
```

- [ ] **Step 3: Run migration**

Run: `bin/rails db:migrate`
Expected: Migration succeeds, schema.rb updated with new columns.

- [ ] **Step 4: Verify schema**

Run: `bin/rails runner "puts KnowledgeSource.column_names.sort.join(', ')"`
Expected: Output includes `confidence`, `origin`, `reasoning`, `status`.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/*_add_extraction_fields_to_knowledge_sources.rb db/schema.rb
git commit -m "db: add origin, reasoning, confidence to knowledge_sources"
```

---

### Task 2: KnowledgeSource model — validations, scopes, constants

**Files:**
- Modify: `app/models/knowledge_source.rb`
- Test: `test/models/knowledge_source_test.rb`

- [ ] **Step 1: Write failing tests for new validations and scopes**

```ruby
# test/models/knowledge_source_test.rb — append these tests

class KnowledgeSourceTest < ActiveSupport::TestCase
  test "origin must be one of manual, extracted, pattern" do
    source = KnowledgeSource.new(title: "Test", source_type: "note", body: "content", origin: "invalid")
    assert_not source.valid?
    assert_includes source.errors[:origin], "is not included in the list"
  end

  test "status must be one of proposed, approved, blocked" do
    source = KnowledgeSource.new(title: "Test", source_type: "note", body: "content", status: "invalid")
    assert_not source.valid?
    assert_includes source.errors[:status], "is not included in the list"
  end

  test "reasoning is required for extracted origin" do
    source = KnowledgeSource.new(title: "Test", source_type: "note", body: "content", origin: "extracted", reasoning: nil)
    assert_not source.valid?
    assert_includes source.errors[:reasoning], "can't be blank"
  end

  test "reasoning is required for pattern origin" do
    source = KnowledgeSource.new(title: "Test", source_type: "note", body: "content", origin: "pattern", reasoning: nil)
    assert_not source.valid?
    assert_includes source.errors[:reasoning], "can't be blank"
  end

  test "reasoning is not required for manual origin" do
    source = KnowledgeSource.new(title: "Test", source_type: "note", body: "content", origin: "manual")
    source.valid?
    assert_not_includes source.errors[:reasoning] || [], "can't be blank"
  end

  test "scope approved returns only approved sources" do
    approved = KnowledgeSource.create!(title: "Approved", source_type: "note", body: "x", status: "approved", origin: "manual")
    KnowledgeSource.create!(title: "Proposed", source_type: "note", body: "x", status: "proposed", origin: "extracted", reasoning: "test")

    assert_includes KnowledgeSource.approved, approved
    assert_equal 1, KnowledgeSource.approved.count
  end

  test "scope proposed returns only proposed sources" do
    KnowledgeSource.create!(title: "Approved", source_type: "note", body: "x", status: "approved", origin: "manual")
    proposed = KnowledgeSource.create!(title: "Proposed", source_type: "note", body: "x", status: "proposed", origin: "extracted", reasoning: "test")

    assert_includes KnowledgeSource.proposed, proposed
    assert_equal 1, KnowledgeSource.proposed.count
  end

  test "scope extracted returns only extracted origin" do
    KnowledgeSource.create!(title: "Manual", source_type: "note", body: "x", status: "approved", origin: "manual")
    extracted = KnowledgeSource.create!(title: "Extracted", source_type: "note", body: "x", status: "approved", origin: "extracted", reasoning: "test")

    assert_includes KnowledgeSource.extracted, extracted
    assert_equal 1, KnowledgeSource.extracted.count
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/knowledge_source_test.rb`
Expected: Failures for missing validations and scopes.

- [ ] **Step 3: Implement model changes**

```ruby
# app/models/knowledge_source.rb
class KnowledgeSource < ApplicationRecord
  ORIGINS = %w[manual extracted pattern].freeze
  STATUSES = %w[proposed approved blocked].freeze

  has_many :knowledge_chunks, dependent: :destroy
  has_many :knowledge_source_topics, dependent: :destroy
  has_many :topics, through: :knowledge_source_topics
  has_one_attached :file

  validates :title, presence: true
  validates :source_type, presence: true, inclusion: { in: %w[note pdf] }
  validates :origin, presence: true, inclusion: { in: ORIGINS }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :reasoning, presence: true, if: -> { origin.in?(%w[extracted pattern]) }

  scope :approved, -> { where(status: "approved") }
  scope :proposed, -> { where(status: "proposed") }
  scope :blocked, -> { where(status: "blocked") }
  scope :extracted, -> { where(origin: "extracted") }
  scope :pattern_derived, -> { where(origin: "pattern") }
  scope :manual, -> { where(origin: "manual") }

  after_save :ingest_later, if: -> { saved_change_to_body? || attachment_changes["file"].present? }

  def ingest_later
    IngestKnowledgeSourceJob.perform_later(id)
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/models/knowledge_source_test.rb`
Expected: All tests pass.

- [ ] **Step 5: Run full test suite to check for regressions**

Run: `bin/rails test`
Expected: No regressions. Existing tests may need `status: "approved"` added to KnowledgeSource fixtures if any exist.

- [ ] **Step 6: Run linter**

Run: `bin/rubocop app/models/knowledge_source.rb test/models/knowledge_source_test.rb`
Expected: No offenses.

- [ ] **Step 7: Commit**

```bash
git add app/models/knowledge_source.rb test/models/knowledge_source_test.rb
git commit -m "feat: add origin, status, reasoning validations to KnowledgeSource"
```

---

### Task 3: RetrievalService — status filtering and origin-based labels

**Files:**
- Modify: `app/services/retrieval_service.rb`
- Test: `test/services/retrieval_service_test.rb`

- [ ] **Step 1: Write failing tests for status filtering and origin labels**

```ruby
# test/services/retrieval_service_test.rb — append these tests

class RetrievalServiceTest < ActiveSupport::TestCase
  test "retrieve_context only returns chunks from approved active sources" do
    service = RetrievalService.new

    approved_source = KnowledgeSource.create!(
      title: "Approved", source_type: "note", body: "test content about marina",
      status: "approved", active: true, origin: "manual"
    )
    proposed_source = KnowledgeSource.create!(
      title: "Proposed", source_type: "note", body: "test content about marina",
      status: "proposed", active: true, origin: "extracted", reasoning: "test"
    )
    inactive_source = KnowledgeSource.create!(
      title: "Inactive", source_type: "note", body: "test content about marina",
      status: "approved", active: false, origin: "manual"
    )

    # Trigger ingestion synchronously for each
    IngestKnowledgeSourceJob.perform_now(approved_source.id)
    IngestKnowledgeSourceJob.perform_now(proposed_source.id)
    IngestKnowledgeSourceJob.perform_now(inactive_source.id)

    results = service.retrieve_context("marina", limit: 10)
    source_ids = results.map { |r| r[:chunk].knowledge_source_id }.uniq

    assert_includes source_ids, approved_source.id
    assert_not_includes source_ids, proposed_source.id
    assert_not_includes source_ids, inactive_source.id
  end

  test "format_context uses origin-based labels" do
    service = RetrievalService.new

    manual_source = KnowledgeSource.create!(
      title: "Manual Note", source_type: "note", body: "manual content",
      status: "approved", active: true, origin: "manual"
    )
    extracted_source = KnowledgeSource.create!(
      title: "Extracted Fact", source_type: "note", body: "extracted content",
      status: "approved", active: true, origin: "extracted", reasoning: "test"
    )

    manual_chunk = manual_source.knowledge_chunks.create!(chunk_index: 0, content: "manual content", metadata: {})
    extracted_chunk = extracted_source.knowledge_chunks.create!(chunk_index: 0, content: "extracted content", metadata: {})

    results = [
      { chunk: manual_chunk },
      { chunk: extracted_chunk }
    ]

    formatted = service.format_context(results)
    assert_includes formatted, "[ADMIN NOTE: Manual Note]"
    assert_includes formatted, "[DOCUMENT-DERIVED: Extracted Fact]"
  end

  test "format_topic_context uses origin-based labels" do
    service = RetrievalService.new
    topic = topics(:one) # Use existing fixture or create

    pattern_source = KnowledgeSource.create!(
      title: "Pattern Insight", source_type: "note", body: "pattern content",
      status: "approved", active: true, origin: "pattern", reasoning: "test"
    )
    pattern_source.knowledge_source_topics.create!(topic: topic)

    chunk = pattern_source.knowledge_chunks.create!(chunk_index: 0, content: "pattern content", metadata: {})

    results = [{ chunk: chunk, topic: topic }]

    formatted = service.format_topic_context(results)
    assert_equal 1, formatted.length
    assert_includes formatted.first, "[PATTERN-DERIVED: Pattern Insight]"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/retrieval_service_test.rb`
Expected: Failures for missing status filter and old label format.

- [ ] **Step 3: Update RetrievalService**

```ruby
# app/services/retrieval_service.rb
class RetrievalService
  def initialize
    @embedding_service = ::Ai::EmbeddingService.new
  end

  def retrieve_context(query_text, limit: 10, candidate_scope: nil)
    return [] if query_text.blank?

    query_embedding = @embedding_service.embed(query_text)

    # Base scope: Approved AND active knowledge chunks
    scope = KnowledgeChunk.joins(:knowledge_source)
                          .where(knowledge_sources: { active: true, status: "approved" })

    # Apply candidate scope if provided (e.g. topic filter)
    scope = scope.merge(candidate_scope) if candidate_scope

    all_chunks = scope.to_a
    results = VectorService.nearest_neighbors(query_embedding, all_chunks, top_k: limit)

    results
  end

  # Topic-aware retrieval with strict caps and determinism
  def retrieve_topic_context(topic:, query_text:, limit: 5, max_chars: 6000)
    topic_scope = KnowledgeChunk.joins(knowledge_source: :knowledge_source_topics)
                                .where(knowledge_source_topics: { topic_id: topic.id })
                                .includes(knowledge_source: :knowledge_source_topics)

    candidates = retrieve_context(query_text, limit: limit * 3, candidate_scope: topic_scope)

    final_results = []
    current_chars = 0

    candidates.each do |result|
      chunk_size = result[:chunk].content.length
      break if final_results.size >= limit
      if current_chars + chunk_size > max_chars && final_results.any?
        break
      end
      result[:topic] = topic
      final_results << result
      current_chars += chunk_size
    end

    final_results
  end

  # Format with origin-based trust labels
  def format_context(results)
    return "No relevant background context found." if results.empty?

    results.map do |result|
      chunk = result[:chunk]
      source = chunk.knowledge_source
      label = origin_label(source)

      <<~TEXT
        #{label}
        #{chunk.content}
      TEXT
    end.join("\n\n")
  end

  # Topic context formatter with origin-based labels
  def format_topic_context(results)
    return [] if results.empty?

    results.map do |result|
      chunk = result[:chunk]
      source = chunk.knowledge_source
      label = origin_label(source)

      <<~TEXT
        #{label}
        #{chunk.content}
      TEXT
    end
  end

  private

  def origin_label(source)
    case source.origin
    when "manual"
      "[ADMIN NOTE: #{source.title}]"
    when "extracted"
      "[DOCUMENT-DERIVED: #{source.title}]"
    when "pattern"
      "[PATTERN-DERIVED: #{source.title}]"
    else
      "[#{source.title}]"
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/retrieval_service_test.rb`
Expected: All tests pass.

- [ ] **Step 5: Run full test suite for regressions**

Run: `bin/rails test`
Expected: No regressions. If other tests relied on the old format_context output format, update those assertions to use the new origin-based labels.

- [ ] **Step 6: Run linter**

Run: `bin/rubocop app/services/retrieval_service.rb`
Expected: No offenses.

- [ ] **Step 7: Commit**

```bash
git add app/services/retrieval_service.rb test/services/retrieval_service_test.rb
git commit -m "feat: filter retrieval by status, use origin-based trust labels"
```

---

### Task 4: OpenAiService — extract_knowledge method

**Files:**
- Modify: `app/services/ai/open_ai_service.rb`
- Test: `test/services/ai/open_ai_service_test.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test/services/ai/open_ai_service_test.rb — append

class Ai::OpenAiServiceExtractKnowledgeTest < ActiveSupport::TestCase
  test "extract_knowledge returns parsed JSON array" do
    # Seed the prompt template
    PromptTemplate.find_or_create_by!(key: "extract_knowledge") do |t|
      t.name = "Knowledge Extraction"
      t.model_tier = "default"
      t.system_role = "You extract civic knowledge."
      t.instructions = "Extract facts from: {{summary_json}}\n\nRaw text: {{raw_text}}\n\nExisting KB: {{existing_kb}}\n\nReturn json array."
    end

    service = Ai::OpenAiService.new

    mock_response = {
      "choices" => [{
        "message" => {
          "content" => '[{"title":"Smith owns marina","body":"John Smith owns Smiths Marina","reasoning":"Smith recused during item 7","confidence":0.9,"topic_names":["Marina Dock Permits"]}]'
        }
      }]
    }

    OpenAI::Client.any_instance.stubs(:chat).returns(mock_response)

    result = service.extract_knowledge(
      summary_json: '{"headline":"Test"}',
      raw_text: "Meeting minutes text...",
      existing_kb: "No existing entries.",
      source: nil
    )

    parsed = JSON.parse(result)
    assert_kind_of Array, parsed
    assert_equal "Smith owns marina", parsed.first["title"]
    assert parsed.first["confidence"] >= 0.7
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/ai/open_ai_service_test.rb -n "/extract_knowledge/"`
Expected: FAIL — method not defined.

- [ ] **Step 3: Implement extract_knowledge method**

Add to `app/services/ai/open_ai_service.rb` before the `private` keyword (before `prepare_committee_context`):

```ruby
    # Extract durable civic knowledge from a meeting's summary + raw text.
    # Returns raw JSON string (array of knowledge entry objects).
    def extract_knowledge(summary_json:, raw_text:, existing_kb:, source: nil)
      template = PromptTemplate.find_by!(key: "extract_knowledge")
      system_role = template.system_role
      placeholders = {
        summary_json: summary_json.to_s,
        raw_text: raw_text.to_s.truncate(25_000),
        existing_kb: existing_kb.to_s
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
        template_key: "extract_knowledge",
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

Note: The response_format `json_object` requires the prompt to contain the word "json" — ensure the prompt template instructions include it.

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/ai/open_ai_service_test.rb -n "/extract_knowledge/"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/ai/open_ai_service.rb test/services/ai/open_ai_service_test.rb
git commit -m "feat: add extract_knowledge method to OpenAiService"
```

---

### Task 5: OpenAiService — triage_knowledge and extract_knowledge_patterns methods

**Files:**
- Modify: `app/services/ai/open_ai_service.rb`
- Test: `test/services/ai/open_ai_service_test.rb`

- [ ] **Step 1: Write failing tests**

```ruby
# test/services/ai/open_ai_service_test.rb — append

class Ai::OpenAiServiceTriageKnowledgeTest < ActiveSupport::TestCase
  test "triage_knowledge returns parsed JSON with decisions" do
    PromptTemplate.find_or_create_by!(key: "triage_knowledge") do |t|
      t.name = "Knowledge Triage"
      t.model_tier = "default"
      t.system_role = "You triage knowledge entries."
      t.instructions = "Triage these entries: {{entries_json}}\n\nExisting KB: {{existing_kb}}\n\nReturn json with decisions."
    end

    service = Ai::OpenAiService.new

    mock_response = {
      "choices" => [{
        "message" => {
          "content" => '{"decisions":[{"knowledge_source_id":1,"action":"approve","rationale":"Well-grounded in meeting text"}]}'
        }
      }]
    }

    OpenAI::Client.any_instance.stubs(:chat).returns(mock_response)

    result = service.triage_knowledge(
      entries_json: '[{"id":1,"title":"Test","reasoning":"from minutes"}]',
      existing_kb: "No existing entries.",
      source: nil
    )

    parsed = JSON.parse(result)
    assert_kind_of Hash, parsed
    assert_equal "approve", parsed["decisions"].first["action"]
  end
end

class Ai::OpenAiServiceExtractKnowledgePatternsTest < ActiveSupport::TestCase
  test "extract_knowledge_patterns returns parsed JSON array" do
    PromptTemplate.find_or_create_by!(key: "extract_knowledge_patterns") do |t|
      t.name = "Knowledge Pattern Detection"
      t.model_tier = "default"
      t.system_role = "You detect patterns across meetings."
      t.instructions = "Find patterns in: {{knowledge_entries}}\n\nRecent summaries: {{recent_summaries}}\n\nReturn json array."
    end

    service = Ai::OpenAiService.new

    mock_response = {
      "choices" => [{
        "message" => {
          "content" => '[{"title":"Smith recuses on marina votes","body":"Pattern across 3 meetings","reasoning":"Recusal in meetings 101, 105, 112","confidence":0.85,"topic_names":["Marina Dock Permits"]}]'
        }
      }]
    }

    OpenAI::Client.any_instance.stubs(:chat).returns(mock_response)

    result = service.extract_knowledge_patterns(
      knowledge_entries: "Entry 1: Smith owns marina...",
      recent_summaries: "Meeting 101 summary...",
      topic_metadata: "Marina Dock Permits: 5 appearances",
      source: nil
    )

    parsed = JSON.parse(result)
    assert_kind_of Array, parsed
    assert_equal "Smith recuses on marina votes", parsed.first["title"]
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/ai/open_ai_service_test.rb -n "/triage_knowledge|extract_knowledge_patterns/"`
Expected: FAIL — methods not defined.

- [ ] **Step 3: Implement both methods**

Add to `app/services/ai/open_ai_service.rb` after the `extract_knowledge` method:

```ruby
    # Triage proposed knowledge entries — approve or block.
    # Returns raw JSON string with decisions array.
    def triage_knowledge(entries_json:, existing_kb:, source: nil)
      template = PromptTemplate.find_by!(key: "triage_knowledge")
      system_role = template.system_role
      placeholders = {
        entries_json: entries_json.to_s,
        existing_kb: existing_kb.to_s
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
        template_key: "triage_knowledge",
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

    # Detect cross-meeting patterns from accumulated knowledge entries.
    # Returns raw JSON string (array of pattern entry objects).
    def extract_knowledge_patterns(knowledge_entries:, recent_summaries:, topic_metadata:, source: nil)
      template = PromptTemplate.find_by!(key: "extract_knowledge_patterns")
      system_role = template.system_role
      placeholders = {
        knowledge_entries: knowledge_entries.to_s,
        recent_summaries: recent_summaries.to_s.truncate(50_000),
        topic_metadata: topic_metadata.to_s
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
        template_key: "extract_knowledge_patterns",
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

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/ai/open_ai_service_test.rb -n "/triage_knowledge|extract_knowledge_patterns/"`
Expected: PASS.

- [ ] **Step 5: Run linter**

Run: `bin/rubocop app/services/ai/open_ai_service.rb`
Expected: No offenses.

- [ ] **Step 6: Commit**

```bash
git add app/services/ai/open_ai_service.rb test/services/ai/open_ai_service_test.rb
git commit -m "feat: add triage_knowledge and extract_knowledge_patterns to OpenAiService"
```

---

### Task 6: Seed prompt templates

**Files:**
- Modify: `db/seeds/prompt_templates.rb`

- [ ] **Step 1: Add three new template entries**

Append to the `PROMPT_TEMPLATES_DATA` array in `db/seeds/prompt_templates.rb`:

```ruby
  {
    key: "extract_knowledge",
    name: "Knowledge Extraction",
    description: "Extracts durable civic facts from meeting summaries and raw document text",
    usage_context: "Pipeline: after meeting summarization, identifies institutional knowledge worth remembering — business ownership, relationships, sentiment signals, historical context. Never shown to residents; injected into future AI prompts as background context",
    model_tier: "default",
    placeholders: [
      { "name" => "summary_json", "description" => "Meeting summary generation_data JSON" },
      { "name" => "raw_text", "description" => "Raw meeting document text (truncated to 25k chars)" },
      { "name" => "existing_kb", "description" => "Existing relevant knowledge entries to avoid duplication" }
    ]
  },
  {
    key: "extract_knowledge_patterns",
    name: "Knowledge Pattern Detection",
    description: "Detects cross-meeting patterns from accumulated knowledge entries",
    usage_context: "Pipeline: weekly analysis of accumulated per-meeting knowledge entries to find behavioral patterns, escalation signals, and relationship inferences. Pattern entries are labeled differently in prompts to prevent compounding",
    model_tier: "default",
    placeholders: [
      { "name" => "knowledge_entries", "description" => "All approved extracted + manual knowledge entries" },
      { "name" => "recent_summaries", "description" => "Recent topic briefing data (last 90 days)" },
      { "name" => "topic_metadata", "description" => "Topic appearance counts, lifecycle status, committees" }
    ]
  },
  {
    key: "triage_knowledge",
    name: "Knowledge Triage",
    description: "Auto-approves or blocks proposed knowledge entries",
    usage_context: "Pipeline: evaluates whether extracted knowledge entries are grounded, durable, non-duplicative, and not misreading normal civic process. Blocked entries never enter prompts; approved entries become available for retrieval",
    model_tier: "default",
    placeholders: [
      { "name" => "entries_json", "description" => "Proposed knowledge entries with title, body, reasoning, confidence" },
      { "name" => "existing_kb", "description" => "Existing approved knowledge entries to check for duplicates" }
    ]
  }
```

- [ ] **Step 2: Run seeds to create the templates**

Run: `bin/rails db:seed`
Expected: Three new PromptTemplate records created (or skipped if already exist).

- [ ] **Step 3: Verify templates exist**

Run: `bin/rails runner "puts PromptTemplate.where(key: %w[extract_knowledge extract_knowledge_patterns triage_knowledge]).pluck(:key, :name).inspect"`
Expected: All three templates present.

- [ ] **Step 4: Commit**

```bash
git add db/seeds/prompt_templates.rb
git commit -m "feat: seed extract_knowledge, extract_knowledge_patterns, triage_knowledge prompt templates"
```

---

### Task 7: ExtractKnowledgeJob

**Files:**
- Create: `app/jobs/extract_knowledge_job.rb`
- Test: `test/jobs/extract_knowledge_job_test.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test/jobs/extract_knowledge_job_test.rb

require "test_helper"

class ExtractKnowledgeJobTest < ActiveSupport::TestCase
  test "creates proposed knowledge source from extraction results" do
    meeting = meetings(:one)  # Use existing fixture

    # Ensure meeting has a summary with generation_data
    summary = meeting.meeting_summaries.find_or_create_by!(summary_type: "minutes_recap") do |s|
      s.generation_data = { "headline" => "Council approves marina renovation" }
    end

    # Ensure meeting has a minutes document
    meeting.meeting_documents.find_or_create_by!(document_type: "minutes_pdf") do |d|
      d.extracted_text = "John Smith recused himself as owner of Smith's Marina during discussion of marina dock permits."
      d.title = "Minutes"
    end

    # Ensure an approved topic exists to link to
    topic = Topic.find_or_create_by!(name: "Marina Dock Permits") do |t|
      t.status = "approved"
      t.review_status = "approved"
    end

    # Mock AI response
    mock_response = [
      {
        "title" => "John Smith owns Smith's Marina",
        "body" => "John Smith disclosed ownership of Smith's Marina during recusal from marina-related votes.",
        "reasoning" => "Smith stated he needed to recuse as owner of Smith's Marina during agenda item 7.",
        "confidence" => 0.92,
        "topic_names" => ["Marina Dock Permits"]
      }
    ].to_json

    # Wrap in object since response_format: json_object returns an object
    wrapped_response = { "entries" => JSON.parse(mock_response) }.to_json
    Ai::OpenAiService.any_instance.stubs(:extract_knowledge).returns(wrapped_response)

    assert_difference "KnowledgeSource.count", 1 do
      ExtractKnowledgeJob.perform_now(meeting.id)
    end

    entry = KnowledgeSource.last
    assert_equal "John Smith owns Smith's Marina", entry.title
    assert_equal "extracted", entry.origin
    assert_equal "proposed", entry.status
    assert_equal 0.92, entry.confidence
    assert entry.reasoning.present?
    assert entry.active?
  end

  test "skips entries below confidence threshold" do
    meeting = meetings(:one)
    meeting.meeting_summaries.find_or_create_by!(summary_type: "minutes_recap") do |s|
      s.generation_data = { "headline" => "Test" }
    end
    meeting.meeting_documents.find_or_create_by!(document_type: "minutes_pdf") do |d|
      d.extracted_text = "Some text"
      d.title = "Minutes"
    end

    low_confidence_response = { "entries" => [
      { "title" => "Uncertain fact", "body" => "Maybe", "reasoning" => "Vague", "confidence" => 0.5, "topic_names" => [] }
    ] }.to_json

    Ai::OpenAiService.any_instance.stubs(:extract_knowledge).returns(low_confidence_response)

    assert_no_difference "KnowledgeSource.count" do
      ExtractKnowledgeJob.perform_now(meeting.id)
    end
  end

  test "skips extraction when no summary exists" do
    meeting = meetings(:one)
    meeting.meeting_summaries.destroy_all

    assert_no_difference "KnowledgeSource.count" do
      ExtractKnowledgeJob.perform_now(meeting.id)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/jobs/extract_knowledge_job_test.rb`
Expected: FAIL — job class not defined.

- [ ] **Step 3: Implement the job**

```ruby
# app/jobs/extract_knowledge_job.rb

class ExtractKnowledgeJob < ApplicationJob
  queue_as :default

  CONFIDENCE_THRESHOLD = 0.7
  RAW_TEXT_LIMIT = 25_000

  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)

    # Need at least one summary to extract from
    summary = meeting.meeting_summaries.order(updated_at: :desc).first
    return unless summary&.generation_data.present?

    ai_service = Ai::OpenAiService.new
    retrieval_service = RetrievalService.new

    summary_json = summary.generation_data.to_json
    raw_text = best_raw_text(meeting)
    existing_kb = retrieve_existing_kb(meeting, retrieval_service)

    response = ai_service.extract_knowledge(
      summary_json: summary_json,
      raw_text: raw_text,
      existing_kb: existing_kb,
      source: meeting
    )

    return if response.blank?

    parsed = parse_entries(response)
    return if parsed.empty?

    created_ids = []
    parsed.each do |entry|
      next if entry["confidence"].to_f < CONFIDENCE_THRESHOLD

      source = create_knowledge_source(entry)
      link_topics(source, entry["topic_names"])
      created_ids << source.id
    end

    # Enqueue triage if we created any entries
    if created_ids.any?
      AutoTriageKnowledgeJob.set(wait: 3.minutes).perform_later
    end
  end

  private

  def best_raw_text(meeting)
    # Prefer minutes, then transcript, then packet — same priority as summarization
    doc = meeting.meeting_documents.find_by(document_type: "minutes_pdf") ||
          meeting.meeting_documents.find_by(document_type: "transcript") ||
          meeting.meeting_documents.where("document_type LIKE ?", "%packet%").first

    doc&.extracted_text.to_s.truncate(RAW_TEXT_LIMIT)
  end

  def retrieve_existing_kb(meeting, retrieval_service)
    # Build a query from the meeting's topics
    topic_names = meeting.topics.approved.distinct.pluck(:name)
    return "No existing knowledge entries." if topic_names.empty?

    query = topic_names.join(", ")
    results = retrieval_service.retrieve_context(query, limit: 10)
    formatted = retrieval_service.format_context(results)
    formatted.presence || "No existing knowledge entries."
  rescue => e
    Rails.logger.warn("Knowledge extraction KB retrieval failed for Meeting #{meeting.id}: #{e.message}")
    "No existing knowledge entries."
  end

  def parse_entries(response)
    parsed = JSON.parse(response)

    # Handle both {"entries": [...]} wrapper and bare array
    entries = parsed.is_a?(Array) ? parsed : Array(parsed["entries"])
    entries.select { |e| e.is_a?(Hash) && e["title"].present? }
  rescue JSON::ParserError => e
    Rails.logger.error("ExtractKnowledgeJob: Failed to parse AI response: #{e.message}")
    []
  end

  def create_knowledge_source(entry)
    KnowledgeSource.create!(
      title: entry["title"].to_s.truncate(255),
      body: entry["body"].to_s,
      source_type: "note",
      origin: "extracted",
      status: "proposed",
      active: true,
      reasoning: entry["reasoning"].to_s,
      confidence: entry["confidence"].to_f
    )
  end

  def link_topics(source, topic_names)
    return if topic_names.blank?

    Array(topic_names).each do |name|
      topic = Topic.approved.find_by("LOWER(name) = ?", name.to_s.downcase.strip)
      next unless topic

      source.knowledge_source_topics.find_or_create_by!(topic: topic)
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/jobs/extract_knowledge_job_test.rb`
Expected: All tests pass.

- [ ] **Step 5: Run linter**

Run: `bin/rubocop app/jobs/extract_knowledge_job.rb test/jobs/extract_knowledge_job_test.rb`
Expected: No offenses.

- [ ] **Step 6: Commit**

```bash
git add app/jobs/extract_knowledge_job.rb test/jobs/extract_knowledge_job_test.rb
git commit -m "feat: add ExtractKnowledgeJob for per-meeting knowledge extraction"
```

---

### Task 8: AutoTriageKnowledgeJob

**Files:**
- Create: `app/jobs/auto_triage_knowledge_job.rb`
- Test: `test/jobs/auto_triage_knowledge_job_test.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test/jobs/auto_triage_knowledge_job_test.rb

require "test_helper"

class AutoTriageKnowledgeJobTest < ActiveSupport::TestCase
  test "approves entries that AI recommends approving" do
    entry = KnowledgeSource.create!(
      title: "Smith owns marina",
      body: "John Smith owns Smith's Marina.",
      source_type: "note",
      origin: "extracted",
      status: "proposed",
      active: true,
      reasoning: "Stated during recusal in meeting minutes",
      confidence: 0.9
    )

    # Seed prompt template
    PromptTemplate.find_or_create_by!(key: "triage_knowledge") do |t|
      t.name = "Knowledge Triage"
      t.model_tier = "default"
      t.system_role = "You triage knowledge."
      t.instructions = "Triage: {{entries_json}}\n\nExisting: {{existing_kb}}\n\nReturn json."
    end

    mock_response = { "decisions" => [
      { "knowledge_source_id" => entry.id, "action" => "approve", "rationale" => "Well-grounded" }
    ] }.to_json

    Ai::OpenAiService.any_instance.stubs(:triage_knowledge).returns(mock_response)

    AutoTriageKnowledgeJob.perform_now

    entry.reload
    assert_equal "approved", entry.status
  end

  test "blocks entries that AI recommends blocking" do
    entry = KnowledgeSource.create!(
      title: "Vague speculation",
      body: "Someone might be related.",
      source_type: "note",
      origin: "extracted",
      status: "proposed",
      active: true,
      reasoning: "Seemed like it based on context",
      confidence: 0.75
    )

    PromptTemplate.find_or_create_by!(key: "triage_knowledge") do |t|
      t.name = "Knowledge Triage"
      t.model_tier = "default"
      t.system_role = "You triage knowledge."
      t.instructions = "Triage: {{entries_json}}\n\nExisting: {{existing_kb}}\n\nReturn json."
    end

    mock_response = { "decisions" => [
      { "knowledge_source_id" => entry.id, "action" => "block", "rationale" => "Vague reasoning, not grounded" }
    ] }.to_json

    Ai::OpenAiService.any_instance.stubs(:triage_knowledge).returns(mock_response)

    AutoTriageKnowledgeJob.perform_now

    entry.reload
    assert_equal "blocked", entry.status
  end

  test "does nothing when no proposed entries exist" do
    assert_equal 0, KnowledgeSource.proposed.count

    # Should not call AI service
    Ai::OpenAiService.any_instance.expects(:triage_knowledge).never

    AutoTriageKnowledgeJob.perform_now
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/jobs/auto_triage_knowledge_job_test.rb`
Expected: FAIL — job class not defined.

- [ ] **Step 3: Implement the job**

```ruby
# app/jobs/auto_triage_knowledge_job.rb

class AutoTriageKnowledgeJob < ApplicationJob
  queue_as :default

  def perform
    proposed = KnowledgeSource.proposed.where(origin: %w[extracted pattern])
    if proposed.none?
      Rails.logger.info "AutoTriageKnowledgeJob: No proposed knowledge entries to triage."
      return
    end

    Rails.logger.info "AutoTriageKnowledgeJob: Triaging #{proposed.count} proposed knowledge entries..."

    ai_service = Ai::OpenAiService.new
    retrieval_service = RetrievalService.new

    entries_payload = proposed.map do |entry|
      {
        id: entry.id,
        title: entry.title,
        body: entry.body,
        reasoning: entry.reasoning,
        confidence: entry.confidence,
        origin: entry.origin,
        topic_names: entry.topics.pluck(:name)
      }
    end

    # Retrieve existing approved KB for duplicate checking
    existing_kb = retrieval_service.format_context(
      retrieval_service.retrieve_context("civic knowledge Two Rivers", limit: 20)
    )

    response = ai_service.triage_knowledge(
      entries_json: entries_payload.to_json,
      existing_kb: existing_kb,
      source: nil
    )

    return if response.blank?

    parsed = JSON.parse(response)
    decisions = Array(parsed["decisions"])

    decisions.each do |decision|
      entry = proposed.find { |e| e.id == decision["knowledge_source_id"] }
      next unless entry

      action = decision["action"].to_s
      case action
      when "approve"
        entry.update!(status: "approved")
        Rails.logger.info "AutoTriageKnowledgeJob: Approved '#{entry.title}' — #{decision["rationale"]}"
      when "block"
        entry.update!(status: "blocked")
        Rails.logger.info "AutoTriageKnowledgeJob: Blocked '#{entry.title}' — #{decision["rationale"]}"
      end
    end
  rescue JSON::ParserError => e
    Rails.logger.error("AutoTriageKnowledgeJob: Failed to parse AI response: #{e.message}")
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/jobs/auto_triage_knowledge_job_test.rb`
Expected: All tests pass.

- [ ] **Step 5: Run linter**

Run: `bin/rubocop app/jobs/auto_triage_knowledge_job.rb`
Expected: No offenses.

- [ ] **Step 6: Commit**

```bash
git add app/jobs/auto_triage_knowledge_job.rb test/jobs/auto_triage_knowledge_job_test.rb
git commit -m "feat: add AutoTriageKnowledgeJob for auto-approving/blocking knowledge entries"
```

---

### Task 9: ExtractKnowledgePatternsJob

**Files:**
- Create: `app/jobs/extract_knowledge_patterns_job.rb`
- Test: `test/jobs/extract_knowledge_patterns_job_test.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test/jobs/extract_knowledge_patterns_job_test.rb

require "test_helper"

class ExtractKnowledgePatternsJobTest < ActiveSupport::TestCase
  test "creates proposed pattern entries from AI response" do
    # Create some approved extracted entries as input
    KnowledgeSource.create!(
      title: "Smith recused on marina item",
      body: "Smith recused during marina discussion at Jan meeting",
      source_type: "note", origin: "extracted", status: "approved",
      active: true, reasoning: "From Jan minutes", confidence: 0.9
    )
    KnowledgeSource.create!(
      title: "Smith recused on marina dock permits",
      body: "Smith recused during marina dock permits at Feb meeting",
      source_type: "note", origin: "extracted", status: "approved",
      active: true, reasoning: "From Feb minutes", confidence: 0.88
    )

    PromptTemplate.find_or_create_by!(key: "extract_knowledge_patterns") do |t|
      t.name = "Knowledge Pattern Detection"
      t.model_tier = "default"
      t.system_role = "You detect patterns."
      t.instructions = "Entries: {{knowledge_entries}}\n\nSummaries: {{recent_summaries}}\n\nTopics: {{topic_metadata}}\n\nReturn json."
    end

    mock_response = { "entries" => [
      {
        "title" => "Smith consistently recuses on marina topics",
        "body" => "John Smith has recused himself on marina-related items in 2 consecutive meetings.",
        "reasoning" => "Recusal noted in both Jan and Feb extracted entries about marina items.",
        "confidence" => 0.85,
        "topic_names" => ["Marina Dock Permits"]
      }
    ] }.to_json

    Ai::OpenAiService.any_instance.stubs(:extract_knowledge_patterns).returns(mock_response)

    assert_difference "KnowledgeSource.count", 1 do
      ExtractKnowledgePatternsJob.perform_now
    end

    entry = KnowledgeSource.last
    assert_equal "pattern", entry.origin
    assert_equal "proposed", entry.status
    assert_equal "Smith consistently recuses on marina topics", entry.title
  end

  test "does not read pattern-origin entries as input" do
    # Only extracted and manual should be read
    KnowledgeSource.create!(
      title: "A pattern entry", body: "Should not be input",
      source_type: "note", origin: "pattern", status: "approved",
      active: true, reasoning: "Old pattern", confidence: 0.8
    )

    PromptTemplate.find_or_create_by!(key: "extract_knowledge_patterns") do |t|
      t.name = "Knowledge Pattern Detection"
      t.model_tier = "default"
      t.system_role = "You detect patterns."
      t.instructions = "Entries: {{knowledge_entries}}\n\nSummaries: {{recent_summaries}}\n\nTopics: {{topic_metadata}}\n\nReturn json."
    end

    # Verify the entries passed to AI don't include pattern entries
    Ai::OpenAiService.any_instance.expects(:extract_knowledge_patterns).with(
      has_entry(:knowledge_entries, Not(regexp_matches(/A pattern entry/)))
    ).returns({ "entries" => [] }.to_json)

    ExtractKnowledgePatternsJob.perform_now
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/jobs/extract_knowledge_patterns_job_test.rb`
Expected: FAIL — job class not defined.

- [ ] **Step 3: Implement the job**

```ruby
# app/jobs/extract_knowledge_patterns_job.rb

class ExtractKnowledgePatternsJob < ApplicationJob
  queue_as :default

  CONFIDENCE_THRESHOLD = 0.7

  def perform
    # Only read extracted and manual entries — never pattern entries (guardrail 4)
    first_order_entries = KnowledgeSource.approved.where(origin: %w[extracted manual])
    if first_order_entries.none?
      Rails.logger.info "ExtractKnowledgePatternsJob: No first-order knowledge entries to analyze."
      return
    end

    ai_service = Ai::OpenAiService.new

    knowledge_text = format_entries_for_prompt(first_order_entries)
    recent_summaries = gather_recent_summaries
    topic_metadata = gather_topic_metadata

    response = ai_service.extract_knowledge_patterns(
      knowledge_entries: knowledge_text,
      recent_summaries: recent_summaries,
      topic_metadata: topic_metadata,
      source: nil
    )

    return if response.blank?

    parsed = parse_entries(response)
    return if parsed.empty?

    created_ids = []
    parsed.each do |entry|
      next if entry["confidence"].to_f < CONFIDENCE_THRESHOLD

      source = KnowledgeSource.create!(
        title: entry["title"].to_s.truncate(255),
        body: entry["body"].to_s,
        source_type: "note",
        origin: "pattern",
        status: "proposed",
        active: true,
        reasoning: entry["reasoning"].to_s,
        confidence: entry["confidence"].to_f
      )

      link_topics(source, entry["topic_names"])
      created_ids << source.id
    end

    if created_ids.any?
      AutoTriageKnowledgeJob.set(wait: 3.minutes).perform_later
    end
  end

  private

  def format_entries_for_prompt(entries)
    entries.includes(:topics).map do |entry|
      topics = entry.topics.pluck(:name).join(", ")
      "- #{entry.title}: #{entry.body} [Topics: #{topics}] [Origin: #{entry.origin}]"
    end.join("\n")
  end

  def gather_recent_summaries
    cutoff = 90.days.ago
    briefings = TopicBriefing.where("updated_at > ?", cutoff)
                             .where.not(generation_data: nil)
                             .includes(:topic)
                             .limit(50)

    briefings.map do |b|
      "Topic: #{b.topic.name} — #{b.headline}" if b.topic
    end.compact.join("\n")
  end

  def gather_topic_metadata
    topics = Topic.approved.where("topic_appearances_count > 0 OR resident_impact_score > 0")
                  .includes(:committee)
                  .order(topic_appearances_count: :desc)
                  .limit(50)

    topics.map do |t|
      committee = t.committee&.name || "Unknown"
      "#{t.name}: #{t.topic_appearances_count} appearances, impact #{t.resident_impact_score || 0}, lifecycle #{t.lifecycle_status}, committee #{committee}"
    end.join("\n")
  end

  def parse_entries(response)
    parsed = JSON.parse(response)
    entries = parsed.is_a?(Array) ? parsed : Array(parsed["entries"])
    entries.select { |e| e.is_a?(Hash) && e["title"].present? }
  rescue JSON::ParserError => e
    Rails.logger.error("ExtractKnowledgePatternsJob: Failed to parse AI response: #{e.message}")
    []
  end

  def link_topics(source, topic_names)
    return if topic_names.blank?

    Array(topic_names).each do |name|
      topic = Topic.approved.find_by("LOWER(name) = ?", name.to_s.downcase.strip)
      next unless topic

      source.knowledge_source_topics.find_or_create_by!(topic: topic)
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/jobs/extract_knowledge_patterns_job_test.rb`
Expected: All tests pass. The second test may need adjustment depending on how mocha handles `Not(regexp_matches(...))` — if it doesn't work, change to a simpler assertion that checks the entries passed don't include pattern entries.

- [ ] **Step 5: Run linter**

Run: `bin/rubocop app/jobs/extract_knowledge_patterns_job.rb`
Expected: No offenses.

- [ ] **Step 6: Commit**

```bash
git add app/jobs/extract_knowledge_patterns_job.rb test/jobs/extract_knowledge_patterns_job_test.rb
git commit -m "feat: add ExtractKnowledgePatternsJob for weekly cross-meeting pattern detection"
```

---

### Task 10: Wire ExtractKnowledgeJob into SummarizeMeetingJob

**Files:**
- Modify: `app/jobs/summarize_meeting_job.rb`
- Test: `test/jobs/summarize_meeting_job_test.rb`

- [ ] **Step 1: Write failing test**

```ruby
# test/jobs/summarize_meeting_job_test.rb — append

class SummarizeMeetingJobKnowledgeTest < ActiveSupport::TestCase
  test "enqueues ExtractKnowledgeJob after summarization" do
    meeting = meetings(:one)

    # Stub AI calls to avoid actual API calls
    Ai::OpenAiService.any_instance.stubs(:analyze_meeting_content).returns('{"headline":"Test","highlights":[],"public_input":[],"item_details":[]}')
    Ai::OpenAiService.any_instance.stubs(:analyze_topic_summary).returns('{"factual_record":[],"institutional_framing":[],"resident_impact":{"score":3}}')
    Ai::OpenAiService.any_instance.stubs(:render_topic_summary).returns("Summary text")

    # Ensure meeting has a minutes document
    meeting.meeting_documents.find_or_create_by!(document_type: "minutes_pdf") do |d|
      d.extracted_text = "Some minutes text"
      d.title = "Minutes"
    end

    assert_enqueued_with(job: ExtractKnowledgeJob, args: [meeting.id]) do
      SummarizeMeetingJob.perform_now(meeting.id)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/jobs/summarize_meeting_job_test.rb -n "/enqueues ExtractKnowledgeJob/"`
Expected: FAIL — no enqueue happens.

- [ ] **Step 3: Add the enqueue call to SummarizeMeetingJob**

In `app/jobs/summarize_meeting_job.rb`, add the knowledge extraction enqueue at the end of the `perform` method:

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

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/jobs/summarize_meeting_job_test.rb -n "/enqueues ExtractKnowledgeJob/"`
Expected: PASS.

- [ ] **Step 5: Run full test suite for regressions**

Run: `bin/rails test`
Expected: No regressions.

- [ ] **Step 6: Commit**

```bash
git add app/jobs/summarize_meeting_job.rb test/jobs/summarize_meeting_job_test.rb
git commit -m "feat: wire ExtractKnowledgeJob into SummarizeMeetingJob pipeline"
```

---

### Task 11: Add recurring job configuration

**Files:**
- Modify: `config/recurring.yml`

- [ ] **Step 1: Add weekly pattern extraction job**

Add to `config/recurring.yml` under the `production:` key:

```yaml
  extract_knowledge_patterns:
    class: ExtractKnowledgePatternsJob
    queue: default
    schedule: every Monday at 3:30am
```

This runs 30 minutes after the existing `refresh_topic_descriptions` job (Monday 3am), ensuring topic descriptions are fresh before pattern analysis.

- [ ] **Step 2: Verify YAML is valid**

Run: `bin/rails runner "puts SolidQueue::RecurringTask.from_configuration.map(&:key).sort"`
Expected: Output includes `extract_knowledge_patterns`.

- [ ] **Step 3: Commit**

```bash
git add config/recurring.yml
git commit -m "feat: schedule weekly ExtractKnowledgePatternsJob on Mondays at 3:30am"
```

---

### Task 12: Update prepare_kb_context with trust label instructions

**Files:**
- Modify: `app/services/ai/open_ai_service.rb`

- [ ] **Step 1: Update prepare_kb_context**

Replace the existing `prepare_kb_context` method in `app/services/ai/open_ai_service.rb`:

```ruby
    def prepare_kb_context(chunks)
      return "" if chunks.empty?
      <<~CONTEXT
        <context_handling>
        ### Relevant Context (Background Knowledge)
        The following information comes from the city knowledgebase.
        Use it to identify glossed-over details, but distinguish it from document content.

        **Trust levels:**
        - [ADMIN NOTE]: Authoritative background context from site administrators.
        - [DOCUMENT-DERIVED]: Background context extracted from meeting documents. Reference as "based on meeting records" — do not state as established fact.
        - [PATTERN-DERIVED]: System-identified pattern across meetings. Reference as "the system has noticed..." — do not state as confirmed fact.

        #{chunks.is_a?(Array) ? chunks.join("\n\n") : chunks}
        </context_handling>
      CONTEXT
    end
```

- [ ] **Step 2: Run full test suite**

Run: `bin/rails test`
Expected: No regressions. Tests that check `prepare_kb_context` output may need updated assertions.

- [ ] **Step 3: Run linter**

Run: `bin/rubocop app/services/ai/open_ai_service.rb`
Expected: No offenses.

- [ ] **Step 4: Commit**

```bash
git add app/services/ai/open_ai_service.rb
git commit -m "feat: add trust level labels to KB context injection in prompts"
```

---

### Task 13: Admin UI — filter tabs and origin/reasoning display

**Files:**
- Modify: `app/controllers/admin/knowledge_sources_controller.rb`
- Modify: `app/views/admin/knowledge_sources/index.html.erb`
- Modify: `app/views/admin/knowledge_sources/show.html.erb`
- Modify: `app/views/admin/knowledge_sources/_form.html.erb`

- [ ] **Step 1: Update controller with filtering**

```ruby
# app/controllers/admin/knowledge_sources_controller.rb

module Admin
  class KnowledgeSourcesController < BaseController
    before_action :set_source, only: %i[ show edit update destroy reingest ]

    def index
      @sources = KnowledgeSource.all.order(created_at: :desc)

      @sources = @sources.where(status: params[:status]) if params[:status].present?
      @sources = @sources.where(origin: params[:origin]) if params[:origin].present?
    end

    def show
    end

    def new
      @source = KnowledgeSource.new(source_type: "note")
    end

    def create
      @source = KnowledgeSource.new(source_params)
      @source.active = true
      @source.origin = "manual"
      @source.status = "approved"

      if @source.save
        redirect_to admin_knowledge_source_path(@source), notice: "Knowledge source created. Ingestion queued."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      # Editing an extracted/pattern entry elevates it to manual
      if @source.origin != "manual" && source_params[:body].present? && source_params[:body] != @source.body
        @source.origin = "manual"
      end

      if @source.update(source_params)
        redirect_to admin_knowledge_source_path(@source), notice: "Knowledge source updated. Re-ingestion queued if content changed."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @source.destroy
      redirect_to admin_knowledge_sources_path, notice: "Knowledge source deleted."
    end

    def reingest
      IngestKnowledgeSourceJob.perform_later(@source.id)
      redirect_to admin_knowledge_source_path(@source), notice: "Re-ingestion queued."
    end

    private

    def set_source
      @source = KnowledgeSource.find(params[:id])
    end

    def source_params
      params.require(:knowledge_source).permit(:title, :source_type, :body, :file, :status, :verification_notes, :verified_on, :active)
    end
  end
end
```

- [ ] **Step 2: Add filter tabs to index view**

Add the filter tabs section to the top of `app/views/admin/knowledge_sources/index.html.erb`, inside the existing card or as a new card before the table. Follow the topics admin pattern:

```erb
<div class="card mb-6">
  <% proposed_active = params[:status] == "proposed" %>
  <% approved_active = params[:status] == "approved" %>
  <% blocked_active = params[:status] == "blocked" %>
  <% all_status_active = params[:status].blank? && params[:origin].blank? %>

  <div class="flex items-center justify-between flex-wrap gap-4">
    <div>
      <div class="text-sm text-secondary">Status</div>
      <div class="flex gap-2 flex-wrap mt-2">
        <%= link_to "Proposed", admin_knowledge_sources_path(status: "proposed"), class: "btn #{proposed_active ? 'btn--primary' : 'btn--secondary'}" %>
        <%= link_to "Approved", admin_knowledge_sources_path(status: "approved"), class: "btn #{approved_active ? 'btn--primary' : 'btn--secondary'}" %>
        <%= link_to "Blocked", admin_knowledge_sources_path(status: "blocked"), class: "btn #{blocked_active ? 'btn--primary' : 'btn--secondary'}" %>
        <%= link_to "All", admin_knowledge_sources_path, class: "btn #{all_status_active ? 'btn--primary' : 'btn--secondary'}" %>
      </div>
    </div>
    <div>
      <div class="text-sm text-secondary">Origin</div>
      <div class="flex gap-2 flex-wrap mt-2">
        <%= link_to "Document-Derived", admin_knowledge_sources_path(origin: "extracted", status: params[:status]), class: "btn #{params[:origin] == 'extracted' ? 'btn--primary' : 'btn--secondary'}" %>
        <%= link_to "Pattern-Derived", admin_knowledge_sources_path(origin: "pattern", status: params[:status]), class: "btn #{params[:origin] == 'pattern' ? 'btn--primary' : 'btn--secondary'}" %>
        <%= link_to "Admin Notes", admin_knowledge_sources_path(origin: "manual", status: params[:status]), class: "btn #{params[:origin] == 'manual' ? 'btn--primary' : 'btn--secondary'}" %>
      </div>
    </div>
  </div>

  <div class="mt-4 text-sm text-secondary">
    <%= KnowledgeSource.proposed.count %> proposed &middot;
    <%= KnowledgeSource.approved.count %> approved &middot;
    <%= KnowledgeSource.blocked.count %> blocked &middot;
    <%= KnowledgeSource.where("created_at > ?", 30.days.ago).count %> new in last 30 days
  </div>
</div>
```

- [ ] **Step 3: Update index table to show origin and reasoning**

Update the table in the index view to add Origin column and show truncated reasoning. Add to the `<thead>`:

```erb
<th>Origin</th>
```

And in each row, add:

```erb
<td>
  <span class="badge badge--<%= source.origin %>"><%= source.origin.humanize %></span>
</td>
```

Also update the Status column to use the new `status` field values:

```erb
<td>
  <span class="badge badge--<%= source.status %>"><%= source.status.humanize %></span>
</td>
```

- [ ] **Step 4: Update show view with reasoning and confidence**

Add to `app/views/admin/knowledge_sources/show.html.erb` after the existing content section:

```erb
<% if @source.origin != "manual" %>
  <div class="card mb-4">
    <div class="flex items-center gap-2 mb-2">
      <span class="badge badge--<%= @source.origin %>"><%= @source.origin.humanize %></span>
      <span class="badge badge--<%= @source.status %>"><%= @source.status.humanize %></span>
      <% if @source.confidence %>
        <span class="text-sm text-secondary">Confidence: <%= (@source.confidence * 100).round %>%</span>
      <% end %>
    </div>
    <% if @source.reasoning.present? %>
      <div class="mt-2">
        <div class="text-sm font-medium text-secondary mb-1">AI Reasoning</div>
        <div class="prose prose--sm"><%= @source.reasoning %></div>
      </div>
    <% end %>
  </div>
<% end %>
```

- [ ] **Step 5: Run the app locally and verify the admin pages render**

Run: `bin/dev` and visit `/admin/knowledge_sources`
Expected: Filter tabs appear, page renders without errors.

- [ ] **Step 6: Run linter**

Run: `bin/rubocop app/controllers/admin/knowledge_sources_controller.rb`
Expected: No offenses.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/admin/knowledge_sources_controller.rb app/views/admin/knowledge_sources/
git commit -m "feat: add status/origin filter tabs and AI reasoning display to knowledge sources admin"
```

---

### Task 14: Populate prompt templates with real prompt text

**Files:**
- This is the prompt engineering step — populate the three seeded templates via admin UI or `rails runner`

- [ ] **Step 1: Populate extract_knowledge template**

Run:
```bash
bin/rails runner "
  t = PromptTemplate.find_by!(key: 'extract_knowledge')
  t.update!(
    system_role: 'You are a civic knowledge extraction system for Two Rivers, WI. You identify durable institutional facts from city meeting content — things a longtime city hall reporter would know but that are not obvious from any single document. You produce structured JSON.',
    instructions: <<~PROMPT
      You are analyzing a city meeting to extract durable civic facts worth remembering.

      ## Meeting Summary (what mattered)
      {{summary_json}}

      ## Raw Document Text (the details)
      {{raw_text}}

      ## Existing Knowledge Entries (what we already know)
      {{existing_kb}}

      ## Instructions

      Extract durable civic facts from this meeting. These are things that will still be true and useful months from now:
      - Business ownership or financial interests disclosed by officials
      - Family relationships or partnerships between public figures relevant to governance
      - Significant resident sentiment signals (e.g., unusually high public comment turnout, organized opposition/support)
      - Historical context that explains why something is happening (e.g., \"this parcel was rezoned in 2019\")
      - Disclosed conflicts of interest or recusal patterns

      **Rules:**
      - One fact per entry. Be specific and concise.
      - Every entry MUST be grounded in the meeting content provided above. Cite the specific text that supports the fact in your reasoning.
      - Existing knowledge entries are shown ONLY to avoid duplication. Do NOT treat them as evidence for new entries.
      - Returning an empty array is the correct answer most of the time. Do not force entries that aren't clearly supported.
      - Normal civic process is NOT noteworthy: committee referrals, multi-reading ordinances, tabling for information, consent agenda bundling — these are standard procedure.
      - Do not extract routine procedural facts (meeting started at 7pm, quorum was present, etc.)

      Return a JSON object with an \"entries\" key containing an array. Each entry:
      ```json
      {
        \"entries\": [
          {
            \"title\": \"Short fact title (max 100 chars)\",
            \"body\": \"One-paragraph explanation of the fact\",
            \"reasoning\": \"Specific text from the meeting that supports this — quote or closely paraphrase\",
            \"confidence\": 0.0,
            \"topic_names\": [\"Existing Approved Topic Name\"]
          }
        ]
      }
      ```

      Confidence scale: 0.7 = mentioned once but clear, 0.8 = explicitly stated, 0.9+ = formally disclosed or recorded in official action. Below 0.7 = do not include.

      If nothing worth extracting, return: {\"entries\": []}
    PROMPT
  )
  puts 'extract_knowledge template populated'
"
```

- [ ] **Step 2: Populate triage_knowledge template**

Run:
```bash
bin/rails runner "
  t = PromptTemplate.find_by!(key: 'triage_knowledge')
  t.update!(
    system_role: 'You are a quality gate for civic knowledge entries in Two Rivers, WI. You evaluate whether AI-extracted facts are reliable enough to be used as background context in future AI prompts. You produce structured JSON.',
    instructions: <<~PROMPT
      Evaluate the following proposed knowledge entries and decide whether to approve or block each one.

      ## Proposed Entries
      {{entries_json}}

      ## Existing Approved Knowledge
      {{existing_kb}}

      ## Evaluation Criteria

      For each entry, evaluate:
      1. **Grounded?** Does the reasoning cite specific meeting content, or is it vague/speculative? Vague reasoning (\"it seems like...\", \"based on context...\") = block.
      2. **Durable?** Will this fact still be useful months from now? Ephemeral details (\"meeting ran long\", \"item was discussed\") = block.
      3. **Not duplicative?** Is this genuinely new information, or does it restate something already in existing knowledge? Duplicates = block.
      4. **Not normal process?** Is this misreading standard civic procedure as noteworthy? Committee referrals, multi-reading ordinances, tabling = block.
      5. **Appropriate confidence?** Does the claimed confidence match the evidence strength? Overconfident entries with weak reasoning = block.

      When uncertain, block. False negatives (missing a fact) are acceptable; false positives (bad facts in the knowledge base) are not.

      Return a JSON object:
      ```json
      {
        \"decisions\": [
          {
            \"knowledge_source_id\": 123,
            \"action\": \"approve\",
            \"rationale\": \"Why this decision\"
          }
        ]
      }
      ```

      Valid actions: \"approve\" or \"block\". No other values.
    PROMPT
  )
  puts 'triage_knowledge template populated'
"
```

- [ ] **Step 3: Populate extract_knowledge_patterns template**

Run:
```bash
bin/rails runner "
  t = PromptTemplate.find_by!(key: 'extract_knowledge_patterns')
  t.update!(
    system_role: 'You are a civic pattern detection system for Two Rivers, WI. You analyze accumulated facts from individual meetings to identify cross-meeting behavioral patterns, escalation signals, and relationship inferences. You produce structured JSON.',
    instructions: <<~PROMPT
      Analyze the accumulated knowledge entries below to identify patterns that span multiple meetings.

      ## Knowledge Entries (first-order facts from individual meetings)
      {{knowledge_entries}}

      ## Recent Topic Briefings (last 90 days)
      {{recent_summaries}}

      ## Topic Metadata
      {{topic_metadata}}

      ## What to Look For

      - **Behavioral patterns**: Recurring recusals by the same person on the same topic, consistent voting blocs, members who always speak on certain topics
      - **Escalation signals**: Topics where public comment volume is increasing across meetings, same residents returning repeatedly
      - **Relationship inference**: Shared business interests, disclosed conflicts of interest appearing across multiple meetings
      - **Institutional stalling**: Items that keep getting tabled without progress (distinct from normal multi-reading process)

      ## What is NOT a Pattern

      - Committee referrals between bodies are standard procedure — NOT noteworthy
      - Multi-reading ordinance processes are required by law — NOT stalling
      - Tabling for more information is responsible governance — NOT avoidance
      - Consent agenda bundling is efficiency — NOT hiding items
      - Cross-committee topic movement is normal workflow — NOT evidence of dysfunction
      - Focus on things that would surprise or inform a resident, not things that are just how municipal government works

      ## Rules

      - Every pattern MUST be supported by multiple entries in the knowledge entries above. Cite which entries support the pattern in your reasoning.
      - Do NOT infer patterns from single entries. A pattern requires evidence from at least 2 different meetings.
      - Returning an empty array is the correct answer most of the time.
      - Confidence should reflect how clear the pattern is: 0.7 = suggestive, 0.8 = clear, 0.9+ = unmistakable across many meetings.

      Return a JSON object:
      ```json
      {
        \"entries\": [
          {
            \"title\": \"Short pattern title (max 100 chars)\",
            \"body\": \"Description of the pattern and why it matters to residents\",
            \"reasoning\": \"Which specific knowledge entries support this pattern — cite entry titles\",
            \"confidence\": 0.0,
            \"topic_names\": [\"Existing Approved Topic Name\"]
          }
        ]
      }
      ```

      If no patterns found, return: {\"entries\": []}
    PROMPT
  )
  puts 'extract_knowledge_patterns template populated'
"
```

- [ ] **Step 4: Validate all templates**

Run: `bin/rails prompt_templates:validate`
Expected: All templates valid, including the 3 new ones.

- [ ] **Step 5: Commit**

Note: Prompt template content lives in the database, not in files. This step populates them. The seed metadata was committed in Task 6. No file to commit here unless you want to add a populate script. Consider adding to the seeds file or a rake task for reproducibility.

---

### Task 15: End-to-end smoke test

**Files:**
- No new files — manual verification

- [ ] **Step 1: Run the full test suite**

Run: `bin/rails test`
Expected: All tests pass.

- [ ] **Step 2: Run linter**

Run: `bin/rubocop`
Expected: No offenses in changed files.

- [ ] **Step 3: Run CI**

Run: `bin/ci`
Expected: All checks pass (rubocop, bundler-audit, importmap audit, brakeman).

- [ ] **Step 4: Test the extraction job manually with an existing meeting**

Run:
```bash
bin/rails runner "
  meeting = Meeting.joins(:meeting_summaries).where.not(meeting_summaries: { generation_data: nil }).order('meetings.starts_at DESC').first
  puts \"Testing with Meeting #{meeting.id}: #{meeting.body_name} on #{meeting.starts_at&.to_date}\"
  ExtractKnowledgeJob.perform_now(meeting.id)
  proposed = KnowledgeSource.proposed.where(origin: 'extracted')
  puts \"Created #{proposed.count} proposed entries:\"
  proposed.each { |e| puts \"  - #{e.title} (confidence: #{e.confidence})\" }
"
```
Expected: Job runs without error. May create 0 or more proposed entries depending on meeting content.

- [ ] **Step 5: Test auto-triage manually**

Run:
```bash
bin/rails runner "
  if KnowledgeSource.proposed.any?
    AutoTriageKnowledgeJob.perform_now
    puts 'Triage complete:'
    puts \"  Approved: #{KnowledgeSource.approved.where(origin: %w[extracted pattern]).count}\"
    puts \"  Blocked: #{KnowledgeSource.blocked.count}\"
    puts \"  Still proposed: #{KnowledgeSource.proposed.count}\"
  else
    puts 'No proposed entries to triage'
  end
"
```
Expected: Entries get approved or blocked.

- [ ] **Step 6: Verify admin UI**

Run: `bin/dev` and visit `/admin/knowledge_sources`
Expected: Filter tabs work, any created entries show with origin badges and reasoning.

- [ ] **Step 7: Final commit if any fixes were needed**

```bash
git add -A && git commit -m "fix: address smoke test issues in knowledge extraction pipeline"
```

---

## Summary

| Task | What it does | Files |
|------|-------------|-------|
| 1 | Migration: origin, reasoning, confidence | `db/migrate/`, `db/schema.rb` |
| 2 | KnowledgeSource model validations + scopes | `app/models/knowledge_source.rb` |
| 3 | RetrievalService status filter + origin labels | `app/services/retrieval_service.rb` |
| 4 | OpenAiService.extract_knowledge | `app/services/ai/open_ai_service.rb` |
| 5 | OpenAiService.triage_knowledge + extract_knowledge_patterns | `app/services/ai/open_ai_service.rb` |
| 6 | Seed 3 prompt templates | `db/seeds/prompt_templates.rb` |
| 7 | ExtractKnowledgeJob | `app/jobs/extract_knowledge_job.rb` |
| 8 | AutoTriageKnowledgeJob | `app/jobs/auto_triage_knowledge_job.rb` |
| 9 | ExtractKnowledgePatternsJob | `app/jobs/extract_knowledge_patterns_job.rb` |
| 10 | Wire into SummarizeMeetingJob | `app/jobs/summarize_meeting_job.rb` |
| 11 | Recurring job config | `config/recurring.yml` |
| 12 | Trust label instructions in prepare_kb_context | `app/services/ai/open_ai_service.rb` |
| 13 | Admin UI filter tabs + reasoning display | `app/controllers/admin/`, `app/views/admin/knowledge_sources/` |
| 14 | Populate prompt templates with real text | Database (via rails runner) |
| 15 | End-to-end smoke test | Manual verification |
