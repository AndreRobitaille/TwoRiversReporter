# Topic Briefing Architecture — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace single-meeting topic snapshots with a rolling TopicBriefing model that synthesizes the full topic arc across all meetings, using three-tier event-driven generation and a new editorial voice.

**Architecture:** New `TopicBriefing` model (one per topic, updated in place) fed by three tiers: headline-only (free, on meeting scheduled), interim (1 cheap AI call, on agenda/packet), full (2 reasoning calls, on minutes). Existing `TopicSummary` per-meeting records kept as structured building blocks. Topic show page updated to display headline + "What's Going On" editorial + "Record" factual sections.

**Tech Stack:** Rails 8.1, PostgreSQL, Solid Queue, OpenAI API (gpt-5.2 reasoning, gpt-5-mini lightweight), Minitest

**Design Doc:** `docs/plans/2026-02-21-topic-briefing-architecture-design.md`

---

## Task 1: Create TopicBriefing Model and Migration

**Files:**
- Create: `db/migrate/XXXXXX_create_topic_briefings.rb`
- Create: `app/models/topic_briefing.rb`
- Modify: `app/models/topic.rb:10` (add `has_one :topic_briefing`)
- Create: `test/models/topic_briefing_test.rb`

**Step 1: Write the failing test**

Create `test/models/topic_briefing_test.rb`:

```ruby
require "test_helper"

class TopicBriefingTest < ActiveSupport::TestCase
  setup do
    @topic = Topic.create!(name: "Downtown Parking Changes", status: "approved")
    @meeting = Meeting.create!(
      body_name: "City Council",
      starts_at: 1.day.ago,
      detail_page_url: "http://example.com/meeting"
    )
  end

  test "valid with required fields" do
    briefing = TopicBriefing.new(
      topic: @topic,
      headline: "Council approved modified parking plan 4-3",
      generation_tier: "full"
    )
    assert briefing.valid?
  end

  test "requires topic" do
    briefing = TopicBriefing.new(headline: "Test", generation_tier: "full")
    assert_not briefing.valid?
    assert briefing.errors[:topic].any?
  end

  test "requires headline" do
    briefing = TopicBriefing.new(topic: @topic, generation_tier: "full")
    assert_not briefing.valid?
    assert briefing.errors[:headline].any?
  end

  test "requires generation_tier" do
    briefing = TopicBriefing.new(topic: @topic, headline: "Test")
    assert_not briefing.valid?
    assert briefing.errors[:generation_tier].any?
  end

  test "generation_tier must be valid value" do
    briefing = TopicBriefing.new(
      topic: @topic,
      headline: "Test",
      generation_tier: "invalid"
    )
    assert_not briefing.valid?
  end

  test "one briefing per topic" do
    TopicBriefing.create!(
      topic: @topic,
      headline: "First",
      generation_tier: "headline_only"
    )
    duplicate = TopicBriefing.new(
      topic: @topic,
      headline: "Second",
      generation_tier: "full"
    )
    assert_not duplicate.valid?
  end

  test "topic has_one topic_briefing" do
    briefing = TopicBriefing.create!(
      topic: @topic,
      headline: "Test headline",
      generation_tier: "headline_only"
    )
    assert_equal briefing, @topic.topic_briefing
  end

  test "stores triggering meeting" do
    briefing = TopicBriefing.create!(
      topic: @topic,
      headline: "Test",
      generation_tier: "full",
      triggering_meeting: @meeting,
      last_full_generation_at: Time.current
    )
    assert_equal @meeting, briefing.triggering_meeting
  end

  test "generation_data defaults to empty hash" do
    briefing = TopicBriefing.create!(
      topic: @topic,
      headline: "Test",
      generation_tier: "headline_only"
    )
    assert_equal({}, briefing.generation_data)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/topic_briefing_test.rb`
Expected: FAIL — `TopicBriefing` class doesn't exist yet.

**Step 3: Generate migration and model**

Run: `bin/rails generate model TopicBriefing topic:references headline:string editorial_content:text record_content:text generation_data:jsonb generation_tier:string last_full_generation_at:datetime triggering_meeting:references --no-fixture`

Then edit the generated migration to add constraints:

```ruby
class CreateTopicBriefings < ActiveRecord::Migration[8.1]
  def change
    create_table :topic_briefings do |t|
      t.references :topic, null: false, foreign_key: true, index: { unique: true }
      t.string :headline, null: false
      t.text :editorial_content
      t.text :record_content
      t.jsonb :generation_data, null: false, default: {}
      t.string :generation_tier, null: false
      t.datetime :last_full_generation_at
      t.references :triggering_meeting, null: true, foreign_key: { to_table: :meetings }

      t.timestamps
    end
  end
end
```

Edit `app/models/topic_briefing.rb`:

```ruby
class TopicBriefing < ApplicationRecord
  belongs_to :topic
  belongs_to :triggering_meeting, class_name: "Meeting", optional: true

  validates :headline, presence: true
  validates :generation_tier, presence: true,
    inclusion: { in: %w[headline_only interim full] }
  validates :topic_id, uniqueness: true
end
```

Add to `app/models/topic.rb` (after line 10, the `has_many :topic_summaries` line):

```ruby
has_one :topic_briefing, dependent: :destroy
```

**Step 4: Run migration**

Run: `bin/rails db:migrate`

**Step 5: Run tests to verify they pass**

Run: `bin/rails test test/models/topic_briefing_test.rb`
Expected: All 8 tests PASS.

**Step 6: Commit**

```bash
git add db/migrate/*_create_topic_briefings.rb app/models/topic_briefing.rb app/models/topic.rb test/models/topic_briefing_test.rb db/schema.rb
git commit -m "feat: add TopicBriefing model with one-per-topic constraint

New model for rolling topic briefings that synthesize across all meetings.
Supports three generation tiers: headline_only, interim, full."
```

---

## Task 2: UpdateTopicBriefingJob (Tier 1 + 2)

Handles the cheap tiers: headline-only (no AI) and interim (one gpt-5-mini call).

**Files:**
- Create: `app/jobs/topics/update_topic_briefing_job.rb`
- Create: `test/jobs/topics/update_topic_briefing_job_test.rb`

**Step 1: Write the failing tests**

Create `test/jobs/topics/update_topic_briefing_job_test.rb`:

```ruby
require "test_helper"

class Topics::UpdateTopicBriefingJobTest < ActiveJob::TestCase
  setup do
    @topic = Topic.create!(name: "Downtown Parking", status: "approved")
    @future_meeting = Meeting.create!(
      body_name: "City Council",
      starts_at: 3.days.from_now,
      detail_page_url: "http://example.com/future"
    )
    @item = @future_meeting.agenda_items.create!(
      title: "Downtown Parking Discussion",
      order_index: 1
    )
  end

  test "tier headline_only creates briefing from meeting data without AI" do
    Topics::UpdateTopicBriefingJob.perform_now(
      topic_id: @topic.id,
      meeting_id: @future_meeting.id,
      tier: "headline_only"
    )

    briefing = @topic.reload.topic_briefing
    assert_not_nil briefing
    assert_includes briefing.headline, "City Council"
    assert_equal "headline_only", briefing.generation_tier
    assert_nil briefing.editorial_content
    assert_nil briefing.record_content
  end

  test "tier headline_only updates existing briefing without overwriting full" do
    # Pre-existing full briefing should not be downgraded
    TopicBriefing.create!(
      topic: @topic,
      headline: "Existing full headline",
      editorial_content: "Full editorial",
      record_content: "Full record",
      generation_tier: "full",
      last_full_generation_at: 1.day.ago
    )

    Topics::UpdateTopicBriefingJob.perform_now(
      topic_id: @topic.id,
      meeting_id: @future_meeting.id,
      tier: "headline_only"
    )

    briefing = @topic.reload.topic_briefing
    # Should NOT overwrite full-tier content
    assert_equal "full", briefing.generation_tier
    assert_equal "Full editorial", briefing.editorial_content
  end

  test "tier interim calls lightweight AI and updates headline and editorial" do
    mock_ai = Minitest::Mock.new
    mock_ai.expect :generate_briefing_interim, {
      "headline" => "Council to vote on parking plan, #{@future_meeting.starts_at.strftime('%b %-d')}",
      "upcoming_note" => "The revised proposal reduces conversion from 12 to 8 spots."
    } do |arg|
      arg.is_a?(Hash)
    end

    Ai::OpenAiService.stub :new, mock_ai do
      Topics::UpdateTopicBriefingJob.perform_now(
        topic_id: @topic.id,
        meeting_id: @future_meeting.id,
        tier: "interim"
      )
    end

    briefing = @topic.reload.topic_briefing
    assert_not_nil briefing
    assert_includes briefing.headline, "parking plan"
    assert_includes briefing.editorial_content, "revised proposal"
    assert_equal "interim", briefing.generation_tier

    mock_ai.verify
  end

  test "skips non-approved topics" do
    @topic.update!(status: "proposed")

    Topics::UpdateTopicBriefingJob.perform_now(
      topic_id: @topic.id,
      meeting_id: @future_meeting.id,
      tier: "headline_only"
    )

    assert_nil @topic.reload.topic_briefing
  end

  test "is idempotent for headline_only" do
    2.times do
      Topics::UpdateTopicBriefingJob.perform_now(
        topic_id: @topic.id,
        meeting_id: @future_meeting.id,
        tier: "headline_only"
      )
    end

    assert_equal 1, TopicBriefing.where(topic: @topic).count
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/jobs/topics/update_topic_briefing_job_test.rb`
Expected: FAIL — job class doesn't exist.

**Step 3: Implement the job**

Create `app/jobs/topics/update_topic_briefing_job.rb`:

```ruby
class Topics::UpdateTopicBriefingJob < ApplicationJob
  queue_as :default

  def perform(topic_id:, meeting_id:, tier:)
    topic = Topic.find(topic_id)
    meeting = Meeting.find(meeting_id)

    return unless topic.approved?

    case tier
    when "headline_only"
      update_headline_only(topic, meeting)
    when "interim"
      update_interim(topic, meeting)
    else
      Rails.logger.error("Unknown tier '#{tier}' for UpdateTopicBriefingJob")
    end
  end

  private

  def update_headline_only(topic, meeting)
    briefing = topic.topic_briefing || topic.build_topic_briefing

    # Don't downgrade a full or interim briefing
    return if briefing.persisted? && briefing.generation_tier.in?(%w[interim full])

    date_str = meeting.starts_at.strftime("%b %-d")
    briefing.headline = "Coming up at #{meeting.body_name}, #{date_str}"
    briefing.generation_tier = "headline_only"
    briefing.triggering_meeting = meeting
    briefing.save!
  end

  def update_interim(topic, meeting)
    briefing = topic.topic_briefing || topic.build_topic_briefing

    # Don't downgrade a full briefing
    return if briefing.persisted? && briefing.generation_tier == "full"

    # Gather context for the lightweight AI call
    agenda_items = meeting.agenda_items
      .joins(:agenda_item_topics)
      .where(agenda_item_topics: { topic_id: topic.id })

    context = {
      topic_name: topic.canonical_name,
      current_headline: briefing.headline,
      meeting_body: meeting.body_name,
      meeting_date: meeting.starts_at&.to_date&.to_s,
      agenda_items: agenda_items.map { |ai| { title: ai.title, summary: ai.summary } }
    }

    ai_service = Ai::OpenAiService.new
    result = ai_service.generate_briefing_interim(context)

    briefing.headline = result["headline"] if result["headline"].present?
    if result["upcoming_note"].present?
      briefing.editorial_content = [
        briefing.editorial_content,
        result["upcoming_note"]
      ].compact.join("\n\n")
    end
    briefing.generation_tier = "interim"
    briefing.triggering_meeting = meeting
    briefing.save!
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/jobs/topics/update_topic_briefing_job_test.rb`
Expected: Most tests pass. The `interim` test will fail because `generate_briefing_interim` doesn't exist yet — that's OK, we'll add it in Task 4.

**Step 5: Commit**

```bash
git add app/jobs/topics/update_topic_briefing_job.rb test/jobs/topics/update_topic_briefing_job_test.rb
git commit -m "feat: add UpdateTopicBriefingJob for headline and interim tiers

Handles tier 1 (headline_only, no AI) and tier 2 (interim, one
lightweight AI call). Respects tier hierarchy — never downgrades
a full briefing."
```

---

## Task 3: GenerateTopicBriefingJob (Tier 3 — Full)

The expensive tier: two gpt-5.2 reasoning calls that synthesize across all meetings.

**Files:**
- Create: `app/jobs/topics/generate_topic_briefing_job.rb`
- Create: `test/jobs/topics/generate_topic_briefing_job_test.rb`

**Step 1: Write the failing tests**

Create `test/jobs/topics/generate_topic_briefing_job_test.rb`:

```ruby
require "test_helper"

class Topics::GenerateTopicBriefingJobTest < ActiveJob::TestCase
  setup do
    @topic = Topic.create!(name: "Downtown Parking", status: "approved")
    @meeting = Meeting.create!(
      body_name: "City Council",
      starts_at: 1.day.ago,
      detail_page_url: "http://example.com/meeting"
    )
    @item = @meeting.agenda_items.create!(title: "Parking Plan Vote", order_index: 1)
    @item.topics << @topic

    # Pre-existing per-meeting TopicSummary (the building block)
    @topic_summary = TopicSummary.create!(
      topic: @topic,
      meeting: @meeting,
      content: "## Parking\n- Council voted 4-3",
      summary_type: "topic_digest",
      generation_data: {
        "headline" => "Council approved parking plan 4-3",
        "factual_record" => [{ "statement" => "Approved 4-3", "citations" => [] }]
      }
    )
  end

  test "generates full briefing from topic summary building blocks" do
    analysis_json = {
      "headline" => "Council approved modified parking plan 4-3 on Feb 18",
      "editorial_analysis" => {
        "current_state" => "The city approved the plan.",
        "pattern_observations" => ["Deferred twice"],
        "process_concerns" => [],
        "what_to_watch" => nil
      },
      "factual_record" => [
        { "event" => "Approved 4-3", "date" => "2026-02-18", "citations" => ["Minutes p.7"] }
      ],
      "civic_sentiment" => [],
      "continuity_signals" => [],
      "resident_impact" => { "score" => 4, "rationale" => "Affects downtown" }
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :analyze_topic_briefing, analysis_json do |arg|
      arg.is_a?(Hash)
    end
    mock_ai.expect :render_topic_briefing, {
      "editorial_content" => "The city just approved converting 8 spots...",
      "record_content" => "- Feb 18 — Approved 4-3 [Minutes p.7]"
    } do |arg|
      arg.is_a?(String)
    end

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

    briefing = @topic.reload.topic_briefing
    assert_not_nil briefing
    assert_equal "Council approved modified parking plan 4-3 on Feb 18", briefing.headline
    assert_includes briefing.editorial_content, "8 spots"
    assert_includes briefing.record_content, "Minutes p.7"
    assert_equal "full", briefing.generation_tier
    assert_not_nil briefing.last_full_generation_at
    assert_equal @meeting, briefing.triggering_meeting
    assert briefing.generation_data.key?("editorial_analysis")

    mock_ai.verify
  end

  test "propagates resident impact score to topic" do
    analysis_json = {
      "headline" => "Test",
      "editorial_analysis" => { "current_state" => "Test" },
      "factual_record" => [],
      "resident_impact" => { "score" => 4, "rationale" => "Test" }
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :analyze_topic_briefing, analysis_json do |_| true end
    mock_ai.expect :render_topic_briefing, {
      "editorial_content" => "Test", "record_content" => "Test"
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

    assert_equal 4, @topic.reload.resident_impact_score
  end

  test "skips non-approved topics" do
    @topic.update!(status: "proposed")

    Topics::GenerateTopicBriefingJob.perform_now(
      topic_id: @topic.id,
      meeting_id: @meeting.id
    )

    assert_nil @topic.reload.topic_briefing
  end

  test "is idempotent — updates existing briefing" do
    TopicBriefing.create!(
      topic: @topic,
      headline: "Old headline",
      generation_tier: "interim"
    )

    analysis_json = {
      "headline" => "New headline",
      "editorial_analysis" => { "current_state" => "Updated" },
      "factual_record" => [],
      "resident_impact" => { "score" => 3, "rationale" => "Test" }
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :analyze_topic_briefing, analysis_json do |_| true end
    mock_ai.expect :render_topic_briefing, {
      "editorial_content" => "New editorial", "record_content" => "New record"
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

    assert_equal 1, TopicBriefing.where(topic: @topic).count
    assert_equal "New headline", @topic.reload.topic_briefing.headline
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/jobs/topics/generate_topic_briefing_job_test.rb`
Expected: FAIL — job class doesn't exist.

**Step 3: Implement the job**

Create `app/jobs/topics/generate_topic_briefing_job.rb`:

```ruby
class Topics::GenerateTopicBriefingJob < ApplicationJob
  queue_as :default

  # How many recent meetings get raw document context (vs. just generation_data)
  RAW_CONTEXT_MEETING_LIMIT = 3

  def perform(topic_id:, meeting_id:)
    topic = Topic.find(topic_id)
    meeting = Meeting.find(meeting_id)

    return unless topic.approved?

    ai_service = Ai::OpenAiService.new
    retrieval_service = RetrievalService.new

    # 1. Assemble hybrid context
    context = build_briefing_context(topic, meeting, retrieval_service)

    # 2. Pass 1: Structured analysis (gpt-5.2)
    analysis_json_str = ai_service.analyze_topic_briefing(context)
    analysis_json = parse_json_safely(analysis_json_str, topic)

    # 3. Pass 2: Render editorial + record (gpt-5.2)
    rendered = ai_service.render_topic_briefing(analysis_json.to_json)

    # 4. Save briefing
    save_briefing(topic, meeting, analysis_json, rendered)

    # 5. Propagate resident impact score
    propagate_impact(topic, analysis_json)
  end

  private

  def build_briefing_context(topic, meeting, retrieval_service)
    # Historical: all prior TopicSummary.generation_data
    prior_summaries = topic.topic_summaries
      .joins(:meeting)
      .order("meetings.starts_at ASC")
      .pluck(:generation_data)

    # Recent raw docs: agenda items + extractions from last N meetings
    recent_meeting_ids = topic.topic_appearances
      .joins(:meeting)
      .order("meetings.starts_at DESC")
      .limit(RAW_CONTEXT_MEETING_LIMIT)
      .pluck(:meeting_id)

    recent_raw_context = recent_meeting_ids.flat_map do |mid|
      builder = Topics::SummaryContextBuilder.new(topic, Meeting.find(mid))
      builder.build_context_json[:agenda_items]
    end

    # KB context
    query = "#{topic.canonical_name} #{topic.aliases.map(&:name).join(' ')}"
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
        aliases: topic.aliases.pluck(:name)
      },
      prior_meeting_analyses: prior_summaries,
      recent_raw_context: recent_raw_context,
      knowledgebase_context: formatted_kb,
      continuity_context: {
        status_events: topic.topic_status_events.order(occurred_at: :desc).limit(5).map do |e|
          { event_type: e.evidence_type, details: e.details, date: e.occurred_at&.iso8601 }
        end,
        total_appearances: topic.topic_appearances.count
      }
    }
  end

  def parse_json_safely(json_str, topic)
    JSON.parse(json_str)
  rescue JSON::ParserError
    Rails.logger.error("Failed to parse briefing analysis for Topic #{topic.id}")
    {}
  end

  def save_briefing(topic, meeting, analysis_json, rendered)
    briefing = topic.topic_briefing || topic.build_topic_briefing

    briefing.headline = analysis_json["headline"] || "Topic update"
    briefing.editorial_content = rendered["editorial_content"]
    briefing.record_content = rendered["record_content"]
    briefing.generation_data = analysis_json
    briefing.generation_tier = "full"
    briefing.last_full_generation_at = Time.current
    briefing.triggering_meeting = meeting
    briefing.save!
  end

  def propagate_impact(topic, analysis_json)
    return unless analysis_json["resident_impact"].is_a?(Hash)

    score = analysis_json["resident_impact"]["score"].to_i
    topic.update_resident_impact_from_ai(score) if score.between?(1, 5)
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/jobs/topics/generate_topic_briefing_job_test.rb`
Expected: Most tests pass. AI method tests will fail until Task 4.

**Step 5: Commit**

```bash
git add app/jobs/topics/generate_topic_briefing_job.rb test/jobs/topics/generate_topic_briefing_job_test.rb
git commit -m "feat: add GenerateTopicBriefingJob for full-tier briefing generation

Two-pass reasoning model pipeline: analyze across all meetings, then
render editorial + record sections. Uses hybrid context (generation_data
for history, raw docs for recent meetings)."
```

---

## Task 4: OpenAI Service Methods for Briefings

Add three new methods to `Ai::OpenAiService`: `analyze_topic_briefing`, `render_topic_briefing`, and `generate_briefing_interim`.

**Files:**
- Modify: `app/services/ai/open_ai_service.rb` (add 3 methods after `render_topic_summary`, around line 412)
- Create: `test/services/ai/open_ai_service_briefing_test.rb`

**Step 1: Write the failing tests**

Create `test/services/ai/open_ai_service_briefing_test.rb`:

```ruby
require "test_helper"

class Ai::OpenAiServiceBriefingTest < ActiveSupport::TestCase
  setup do
    @service = Ai::OpenAiService.new
  end

  test "analyze_topic_briefing sends correct prompt structure" do
    context = {
      topic_metadata: { canonical_name: "Downtown Parking", lifecycle_status: "active" },
      prior_meeting_analyses: [{ "headline" => "Prior meeting headline" }],
      recent_raw_context: [],
      knowledgebase_context: [],
      continuity_context: { status_events: [], total_appearances: 3 }
    }

    # Stub the OpenAI client
    mock_response = {
      "choices" => [{
        "message" => {
          "content" => {
            "headline" => "Test headline",
            "editorial_analysis" => { "current_state" => "Test" },
            "factual_record" => [],
            "resident_impact" => { "score" => 3, "rationale" => "Test" }
          }.to_json
        }
      }]
    }

    @service.instance_variable_get(:@client).stub :chat, mock_response do
      result = @service.analyze_topic_briefing(context)
      parsed = JSON.parse(result)
      assert parsed.key?("headline")
      assert parsed.key?("editorial_analysis")
    end
  end

  test "render_topic_briefing returns editorial and record content" do
    analysis_json = {
      "headline" => "Test headline",
      "editorial_analysis" => { "current_state" => "The city approved..." },
      "factual_record" => [{ "event" => "Approved 4-3", "date" => "2026-02-18" }]
    }.to_json

    mock_response = {
      "choices" => [{
        "message" => {
          "content" => {
            "editorial_content" => "The city just approved...",
            "record_content" => "- Feb 18 — Approved 4-3"
          }.to_json
        }
      }]
    }

    @service.instance_variable_get(:@client).stub :chat, mock_response do
      result = @service.render_topic_briefing(analysis_json)
      assert result.key?("editorial_content")
      assert result.key?("record_content")
    end
  end

  test "generate_briefing_interim uses lightweight model" do
    context = {
      topic_name: "Downtown Parking",
      current_headline: "Coming up at Council",
      meeting_body: "City Council",
      meeting_date: "2026-03-04",
      agenda_items: [{ title: "Parking Plan Vote" }]
    }

    mock_response = {
      "choices" => [{
        "message" => {
          "content" => {
            "headline" => "Council to vote on parking plan, Mar 4",
            "upcoming_note" => "The revised plan reduces conversion to 8 spots."
          }.to_json
        }
      }]
    }

    # Verify it uses LIGHTWEIGHT_MODEL by checking the parameters
    called_with_model = nil
    original_chat = @service.instance_variable_get(:@client).method(:chat)

    @service.instance_variable_get(:@client).stub :chat, ->(parameters:) {
      called_with_model = parameters[:model]
      mock_response
    } do
      result = @service.generate_briefing_interim(context)
      assert_equal Ai::OpenAiService::LIGHTWEIGHT_MODEL, called_with_model
      assert result.key?("headline")
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/ai/open_ai_service_briefing_test.rb`
Expected: FAIL — methods don't exist.

**Step 3: Add the three methods to OpenAiService**

Add the following after `render_topic_summary` (around line 412) in `app/services/ai/open_ai_service.rb`:

```ruby
    def analyze_topic_briefing(context)
      system_role = <<~ROLE
        You are a civic analyst writing for residents of Two Rivers, WI.
        You are skeptical of institutional process and framing, but you do not
        ascribe bad intent to individuals. You surface patterns, flag process
        concerns, and help residents understand what is really happening.
        You never use the word "locals" — always "residents."
      ROLE

      prompt = <<~PROMPT
        Analyze the full history of this topic across all meetings and return
        a JSON analysis that synthesizes the complete arc.

        <editorial_voice>
        - Be skeptical of process and decisions, not of people.
        - Surface patterns: deferrals, repeated framing, scope changes.
        - Flag when institutional framing doesn't match outcomes or resident concerns.
        - "Means to an end" analysis is appropriate — note who benefits from decisions.
        - Do not ascribe malice, corruption, or unethical behavior to individuals.
        - Use "residents" not "locals."
        </editorial_voice>

        <governance_constraints>
        - Factual Record: Must have citations. If no document evidence, do not state as fact.
        - Civic Sentiment: Use observational language ("appears to", "residents expressed").
        - Continuity: Explicitly note recurrence, deferrals, cross-body progression, and disappearance.
        - Do not manufacture historical continuity that doesn't exist in the source data.
        </governance_constraints>

        TOPIC CONTEXT (JSON):
        #{context.to_json}

        <extraction_spec>
        Return a JSON object matching this schema exactly:
        {
          "headline": "One plain-language sentence about current status",
          "editorial_analysis": {
            "current_state": "What just happened or where things stand",
            "pattern_observations": ["Observable patterns across meetings"],
            "process_concerns": ["Process issues worth noting, if any"],
            "what_to_watch": "Forward-looking note, or null"
          },
          "factual_record": [
            {"event": "What happened", "date": "YYYY-MM-DD", "citations": ["Source reference"]}
          ],
          "civic_sentiment": [
            {"observation": "What residents appear to think/want", "evidence": "Source", "citations": ["..."]}
          ],
          "continuity_signals": [
            {"signal": "recurrence|deferral|disappearance|cross_body_progression", "details": "...", "citations": ["..."]}
          ],
          "resident_impact": {"score": 1, "rationale": "Why this matters to residents"},
          "ambiguities": ["Unresolved questions"],
          "verification_notes": ["What to check"]
        }
        </extraction_spec>
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

    def render_topic_briefing(analysis_json)
      system_role = <<~ROLE
        You are a civic engagement writer for residents of Two Rivers, WI.
        You write in a direct, skeptical-but-fair editorial voice. You help
        residents understand what is happening and why it matters. You never
        use the word "locals" — always "residents."
      ROLE

      prompt = <<~PROMPT
        Using the TOPIC ANALYSIS below, generate two pieces of content and
        return them as a JSON object with keys "editorial_content" and
        "record_content".

        <editorial_content_guide>
        Write the "What's Going On" section as natural prose paragraphs.
        - Lead with what just happened or where things stand.
        - Weave in pattern observations and process concerns from the analysis.
        - Include civic sentiment where relevant.
        - Use inline citations like [Packet p.3] or [Minutes p.7].
        - Be direct and editorial — help readers who can't connect the dots.
        - If there's something worth watching, end with that.
        - Do NOT use section headers within this content.
        - Keep it 2-4 paragraphs.
        </editorial_content_guide>

        <record_content_guide>
        Write the "Record" section as a chronological bulleted markdown list.
        - Each bullet: date — what happened [citation]
        - Oldest first, newest last.
        - Every claim must have a citation.
        - Include vote tallies where available.
        - Pure facts, no editorializing in this section.
        </record_content_guide>

        TOPIC ANALYSIS (JSON):
        #{analysis_json}
      PROMPT

      response = @client.chat(
        parameters: {
          model: DEFAULT_MODEL,
          response_format: { type: "json_object" },
          messages: [
            { role: "system", content: system_role },
            { role: "user", content: prompt }
          ],
          temperature: 0.2
        }
      )

      JSON.parse(response.dig("choices", 0, "message", "content"))
    rescue JSON::ParserError
      { "editorial_content" => "", "record_content" => "" }
    end

    def generate_briefing_interim(context)
      prompt = <<~PROMPT
        You are updating a topic briefing headline and adding a brief note
        about an upcoming meeting. Return a JSON object with keys "headline"
        and "upcoming_note".

        Topic: #{context[:topic_name]}
        Current headline: #{context[:current_headline]}
        Meeting: #{context[:meeting_body]} on #{context[:meeting_date]}
        Agenda items: #{context[:agenda_items].to_json}

        <rules>
        - "headline": One sentence, plain language. Focus on what's coming.
          Example: "Council to vote on modified parking plan, Mar 4"
        - "upcoming_note": 1-2 sentences about what to expect at the meeting
          based on agenda items. Plain language, no jargon.
        - Use "residents" not "locals."
        </rules>
      PROMPT

      response = @client.chat(
        parameters: {
          model: LIGHTWEIGHT_MODEL,
          response_format: { type: "json_object" },
          messages: [
            { role: "user", content: prompt }
          ]
        }
      )

      JSON.parse(response.dig("choices", 0, "message", "content"))
    rescue JSON::ParserError
      { "headline" => context[:current_headline], "upcoming_note" => "" }
    end
```

**Note:** `generate_briefing_interim` uses `LIGHTWEIGHT_MODEL` (gpt-5-mini) and does NOT pass `temperature` — gpt-5-mini does not support it.

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/ai/open_ai_service_briefing_test.rb`
Expected: PASS.

**Step 5: Run the full job tests now that AI methods exist**

Run: `bin/rails test test/jobs/topics/`
Expected: All job tests should pass.

**Step 6: Commit**

```bash
git add app/services/ai/open_ai_service.rb test/services/ai/open_ai_service_briefing_test.rb
git commit -m "feat: add OpenAI briefing methods — analyze, render, and interim

Three new methods on Ai::OpenAiService for the TopicBriefing pipeline.
analyze_topic_briefing and render_topic_briefing use gpt-5.2 (reasoning).
generate_briefing_interim uses gpt-5-mini (no temperature param).
All prompts use new editorial voice from AUDIENCE.md guidelines."
```

---

## Task 5: Wire Pipeline Triggers

Connect the three tiers to existing pipeline events.

**Files:**
- Modify: `app/models/agenda_item_topic.rb:9-26` (add tier 1 trigger)
- Modify: `app/jobs/summarize_meeting_job.rb:48-84` (add tier 3 trigger)
- Modify: `test/jobs/summarize_meeting_job_test.rb` (add assertion for briefing job enqueue)

**Step 1: Write the failing test for tier 1 trigger**

Add to a new file `test/models/agenda_item_topic_briefing_test.rb`:

```ruby
require "test_helper"

class AgendaItemTopicBriefingTest < ActiveSupport::TestCase
  test "creating agenda_item_topic for future meeting enqueues headline briefing" do
    topic = Topic.create!(name: "Test Topic", status: "approved")
    meeting = Meeting.create!(
      body_name: "City Council",
      starts_at: 3.days.from_now,
      detail_page_url: "http://example.com/future"
    )
    item = meeting.agenda_items.create!(title: "Test Item", order_index: 1)

    assert_enqueued_with(job: Topics::UpdateTopicBriefingJob) do
      AgendaItemTopic.create!(agenda_item: item, topic: topic)
    end
  end

  test "creating agenda_item_topic for past meeting does not enqueue headline briefing" do
    topic = Topic.create!(name: "Test Topic", status: "approved")
    meeting = Meeting.create!(
      body_name: "City Council",
      starts_at: 1.day.ago,
      detail_page_url: "http://example.com/past"
    )
    item = meeting.agenda_items.create!(title: "Test Item", order_index: 1)

    assert_no_enqueued_jobs(only: Topics::UpdateTopicBriefingJob) do
      AgendaItemTopic.create!(agenda_item: item, topic: topic)
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/agenda_item_topic_briefing_test.rb`
Expected: FAIL — no job enqueued.

**Step 3: Add tier 1 trigger to AgendaItemTopic callback**

Modify `app/models/agenda_item_topic.rb` — add after the existing `Topics::UpdateContinuityJob.perform_later` call (line 25):

```ruby
    # Trigger headline briefing for future meetings
    if meeting.starts_at&.future?
      Topics::UpdateTopicBriefingJob.perform_later(
        topic_id: topic.id,
        meeting_id: meeting.id,
        tier: "headline_only"
      )
    end
```

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/models/agenda_item_topic_briefing_test.rb`
Expected: PASS.

**Step 5: Add tier 3 trigger to SummarizeMeetingJob**

Modify `app/jobs/summarize_meeting_job.rb` — add after the `generate_topic_summaries` loop (after line 83, at the end of the `each` block):

```ruby
      # Trigger full briefing generation
      Topics::GenerateTopicBriefingJob.perform_later(
        topic_id: topic.id,
        meeting_id: meeting.id
      )
```

**Step 6: Add test for tier 3 trigger**

Add to `test/jobs/summarize_meeting_job_test.rb`:

```ruby
  test "enqueues GenerateTopicBriefingJob after topic summary generation" do
    mock_ai = Minitest::Mock.new
    mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg|
      arg.is_a?(Hash)
    end
    mock_ai.expect :render_topic_summary, "## Topic Summary" do |arg|
      arg.is_a?(String)
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        assert_enqueued_with(job: Topics::GenerateTopicBriefingJob) do
          SummarizeMeetingJob.perform_now(@meeting.id)
        end
      end
    end
  end
```

**Step 7: Run all affected tests**

Run: `bin/rails test test/jobs/summarize_meeting_job_test.rb test/models/agenda_item_topic_briefing_test.rb`
Expected: All PASS.

**Step 8: Commit**

```bash
git add app/models/agenda_item_topic.rb app/jobs/summarize_meeting_job.rb test/models/agenda_item_topic_briefing_test.rb test/jobs/summarize_meeting_job_test.rb
git commit -m "feat: wire briefing generation to pipeline events

Tier 1: AgendaItemTopic after_create triggers headline briefing for
future meetings. Tier 3: SummarizeMeetingJob enqueues full briefing
after per-meeting topic summary generation."
```

---

## Task 6: Update Topic Show Page

Replace the "What's Happening" and "Recent Activity" sections with the new TopicBriefing display.

**Files:**
- Modify: `app/controllers/topics_controller.rb:49` (swap `@summary` → `@briefing`)
- Modify: `app/views/topics/show.html.erb:51-98` (replace sections 3 and 4)
- Modify: `app/helpers/topics_helper.rb` (add `render_briefing_editorial` and `render_briefing_record` helpers)
- Modify: `app/assets/stylesheets/application.css` (add briefing-specific styles)

**Step 1: Update the controller**

In `app/controllers/topics_controller.rb`, replace line 49:

```ruby
    @summary = @topic.topic_summaries.order(created_at: :desc).first
```

With:

```ruby
    @briefing = @topic.topic_briefing
```

Also remove lines 52-58 (`@recent_activity` query) — this section is being removed.

**Step 2: Add helper methods**

Add to `app/helpers/topics_helper.rb` (before `render_topic_summary_content`):

```ruby
  def render_briefing_editorial(markdown_content)
    return "" if markdown_content.blank?

    # Convert markdown paragraphs to HTML paragraphs
    paragraphs = markdown_content.split(/\n{2,}/).map(&:strip).reject(&:blank?)
    safe_join(paragraphs.map { |p| content_tag(:p, p) })
  end

  def render_briefing_record(markdown_content)
    return "" if markdown_content.blank?

    lines = markdown_content.lines.map(&:chomp)
    items = lines.filter_map do |line|
      text = line.sub(/\A\s*[-*]\s*/, "").strip
      next if text.empty?
      content_tag(:li, text)
    end

    return "" if items.empty?
    content_tag(:ul, safe_join(items), class: "topic-record-list")
  end

  def briefing_freshness_badge(briefing)
    return unless briefing.updated_at > 7.days.ago

    label = briefing.created_at == briefing.updated_at ? "New" : "Updated"
    tag.span(label, class: "badge badge--primary")
  end
```

**Step 3: Update the view**

Replace sections 3 ("What's Happening", lines 51-61) and 4 ("Recent Activity", lines 63-98) in `app/views/topics/show.html.erb` with:

```erb
<%# === 3. Briefing Headline === %>
<% if @briefing&.headline.present? %>
  <section class="topic-briefing-headline section">
    <div class="card card--warm">
      <div class="card-body">
        <p class="briefing-headline-text"><%= @briefing.headline %></p>
        <%= briefing_freshness_badge(@briefing) %>
      </div>
    </div>
  </section>
<% end %>

<%# === 4. What's Going On (Editorial) === %>
<% if @briefing&.editorial_content.present? %>
  <section class="topic-briefing-editorial section topic-section">
    <h2 class="section-title">What's Going On</h2>
    <div class="card">
      <div class="card-body briefing-editorial-content">
        <%= sanitize(render_briefing_editorial(@briefing.editorial_content)) %>
      </div>
    </div>
  </section>
<% end %>

<%# === 5. Record (Factual) === %>
<% if @briefing&.record_content.present? %>
  <section class="topic-briefing-record section topic-section">
    <h2 class="section-title">Record</h2>
    <div class="card card--surface-raised">
      <div class="card-body">
        <%= sanitize(render_briefing_record(@briefing.record_content)) %>
      </div>
    </div>
  </section>
<% end %>
```

Also update the empty state check (line 139) to reference `@briefing` instead of `@summary`:

```erb
<% if @upcoming.empty? && @briefing.nil? && @decisions.empty? %>
```

And remove the `@recent_activity` reference from the empty state.

**Step 4: Add CSS styles**

Add to `app/assets/stylesheets/application.css`:

```css
/* Topic Briefing */
.briefing-headline-text {
  font-size: var(--font-lg);
  font-weight: var(--font-bold);
  line-height: var(--leading-tight);
  margin-bottom: 0;
}

.briefing-editorial-content {
  line-height: var(--leading-relaxed);
}

.briefing-editorial-content p {
  margin-bottom: var(--space-4);
}

.briefing-editorial-content p:last-child {
  margin-bottom: 0;
}

.card--surface-raised {
  background-color: var(--color-surface-raised);
}

.topic-record-list {
  list-style: disc;
  padding-left: var(--space-6);
}

.topic-record-list li {
  margin-bottom: var(--space-2);
  line-height: var(--leading-normal);
}

.topic-record-list li:last-child {
  margin-bottom: 0;
}
```

**Step 5: Verify the page renders**

Run: `bin/rails test` (full suite to catch any breakage)
Expected: All tests pass. Existing `render_topic_summary_content` tests won't break because that helper still exists (used on meeting pages).

**Step 6: Commit**

```bash
git add app/controllers/topics_controller.rb app/views/topics/show.html.erb app/helpers/topics_helper.rb app/assets/stylesheets/application.css
git commit -m "feat: update topic show page with briefing display

Replace 'What's Happening' and 'Recent Activity' sections with three-tier
TopicBriefing display: headline card, 'What's Going On' editorial section,
and 'Record' factual section. Progressive fill-in based on generation tier."
```

---

## Task 7: Update Per-Meeting TopicSummary Editorial Voice

Update the existing `analyze_topic_summary` and `render_topic_summary` prompts to use the new editorial voice.

**Files:**
- Modify: `app/services/ai/open_ai_service.rb:272-412`

**Step 1: Update `analyze_topic_summary` system role (line 273)**

Replace:

```ruby
      system_role = "You are a civic continuity analyst. Your goal is to separate factual record from institutional framing and civic sentiment."
```

With:

```ruby
      system_role = "You are a civic analyst writing for residents of Two Rivers, WI. You separate factual record from institutional framing and civic sentiment. You are skeptical of institutional process but do not ascribe bad intent to individuals."
```

**Step 2: Update `render_topic_summary` system role and style guide (lines 369-383)**

Replace:

```ruby
      system_role = "You are a civic engagement assistant. Write a Topic-First summary."
```

With:

```ruby
      system_role = "You are a civic engagement writer for residents of Two Rivers, WI. Write in a direct, skeptical-but-fair editorial voice. Help residents understand what is happening and why it matters. Use 'residents' not 'locals.'"
```

And update the style guide section to include editorial voice guidance:

```ruby
        <style_guide>
        - Heading 2 (##) for the Topic Name.
        - Section: **Factual Record** (Bulleted). Append citations like [Packet Page 12].
        - Section: **Institutional Framing** (Bulleted). Note where framing diverges from outcomes or resident concerns.
        - Section: **Civic Sentiment** (Bulleted, if any). Use observational language.
        - Section: **Resident-reported (no official record)** (Bulleted, if any).
        - Section: **Continuity** (If signals exist). Note deferrals, recurrence, disappearance.
        - Do NOT mix these categories.
        - Be direct and plain-spoken. No government jargon.
        - Use "residents" not "locals."
        - If a section is empty, omit it (except Factual Record, which should note "No new factual record" if empty).
        </style_guide>
```

**Step 3: Run existing tests to verify nothing breaks**

Run: `bin/rails test test/jobs/summarize_meeting_job_test.rb`
Expected: PASS — the tests mock the AI responses so prompt changes don't affect them.

**Step 4: Commit**

```bash
git add app/services/ai/open_ai_service.rb
git commit -m "feat: update per-meeting TopicSummary prompts to editorial voice

Shifts system roles and style guides for analyze_topic_summary and
render_topic_summary to the new resident-facing editorial tone.
Skeptical of process, not people. Uses 'residents' not 'locals.'"
```

---

## Task 8: Full Test Suite + Lint

**Step 1: Run full test suite**

Run: `bin/rails test`
Expected: All tests pass.

**Step 2: Run linter**

Run: `bin/rubocop`
Expected: No new offenses. Fix any that appear.

**Step 3: Run CI**

Run: `bin/ci`
Expected: Clean pass.

**Step 4: Commit any lint fixes**

```bash
git add -A
git commit -m "style: fix rubocop offenses from briefing implementation"
```

---

## Task 9: Backfill Existing Topics (Rake Task)

Create a rake task to generate briefings for existing approved topics that already have TopicSummary records.

**Files:**
- Create: `lib/tasks/briefings.rake`

**Step 1: Create the rake task**

```ruby
namespace :briefings do
  desc "Generate full briefings for all approved topics with existing summaries"
  task generate: :environment do
    topics = Topic.approved.joins(:topic_summaries).distinct.where.missing(:topic_briefing)

    puts "Found #{topics.count} topics needing briefings"

    topics.find_each do |topic|
      latest_summary = topic.topic_summaries.joins(:meeting).order("meetings.starts_at DESC").first
      next unless latest_summary

      puts "  Enqueuing briefing for: #{topic.canonical_name} (meeting: #{latest_summary.meeting.body_name})"
      Topics::GenerateTopicBriefingJob.perform_later(
        topic_id: topic.id,
        meeting_id: latest_summary.meeting_id
      )
    end

    puts "Done. Jobs enqueued — run bin/jobs to process."
  end
end
```

**Step 2: Commit**

```bash
git add lib/tasks/briefings.rake
git commit -m "feat: add briefings:generate rake task for backfilling

Enqueues GenerateTopicBriefingJob for all approved topics that have
existing TopicSummary records but no TopicBriefing yet."
```

---

## Summary

| Task | What | Key Files |
|------|------|-----------|
| 1 | TopicBriefing model + migration | model, migration, test |
| 2 | UpdateTopicBriefingJob (tier 1+2) | job, test |
| 3 | GenerateTopicBriefingJob (tier 3) | job, test |
| 4 | OpenAI service methods | 3 new methods, test |
| 5 | Wire pipeline triggers | agenda_item_topic callback, summarize_meeting_job |
| 6 | Topic show page update | controller, view, helpers, CSS |
| 7 | Per-meeting voice update | OpenAI prompts |
| 8 | Full test suite + lint | verification |
| 9 | Backfill rake task | rake task |
