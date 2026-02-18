# Topic Auto-Approval Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce manual admin intervention in topic management by making the AI community-aware at extraction and triage, lowering confidence thresholds with tiered risk, and shifting admin workflow from pre-approval gatekeeping to post-approval auditing.

**Architecture:** Inject Two Rivers community context (via KnowledgeSource RAG) into the extraction and triage AI prompts. Add `topic_worthy` filtering at extraction time. Replace the single 0.9 confidence gate with per-action thresholds. Fix the audit trail so auto-triage decisions are recorded. Add an admin audit view for reviewing AI decisions.

**Tech Stack:** Rails 8.1, PostgreSQL with pgvector, OpenAI API via `ruby-openai`, Minitest, Turbo/Stimulus

**Design doc:** `docs/plans/2026-02-17-topic-auto-approval-redesign.md`

**Binding docs (read before any topic work):**
- `docs/topics/TOPIC_GOVERNANCE.md`
- `docs/DEVELOPMENT_PLAN.md`

---

### Task 1: Seed Two Rivers Community Context KnowledgeSource

This provides the community context that all subsequent tasks depend on. The KnowledgeSource system already exists — we just need to create entries with the right content.

**Files:**
- Create: `db/seeds/community_context.rb`
- Modify: `db/seeds.rb`

**Step 1: Write the seed file**

Create `db/seeds/community_context.rb`:

```ruby
# Seed Two Rivers community context for AI extraction and triage.
# These KnowledgeSource entries give the AI understanding of what
# matters to Two Rivers residents vs. routine institutional noise.

COMMUNITY_CONTEXT_TITLE = "Two Rivers Community Context — Topic Extraction Guide"

COMMUNITY_CONTEXT_BODY = <<~CONTEXT
  ## Community Identity

  Two Rivers, WI is a small post-industrial city on Lake Michigan with a strong generational identity rooted in its manufacturing heritage (notably Hamilton Industries and Eggers Industries). Many residents have deep, multi-generational ties to the city and significant nostalgia for its industrial past. The community values stability, continuity, and the preservation of neighborhood character.

  ## What Residents Care About (High-Salience Topics)

  The following types of civic issues are likely to be important to Two Rivers residents. When these appear on agendas, they are strong candidates for topic creation:

  - Property tax increases, reassessments, or TIF district changes that affect household budgets
  - Development or zoning changes that alter the physical character of neighborhoods, downtown, or the lakefront
  - The tension between the city's manufacturing heritage and its transition toward a tourism-oriented economy — many residents did not choose and do not want this transition
  - School district decisions, closures, or funding changes
  - Infrastructure decay or major capital projects in established residential areas
  - Changes to Main Street or Washington Street businesses and character
  - Any item generating significant public comment volume — this is the strongest signal of resident concern
  - Decisions where residents feel excluded from the process or believe leadership is not listening
  - Narrow or divided votes on the council — these signal community disagreement
  - Items where it matters who benefits from a decision (developer interests vs. resident interests)
  - Historic preservation or demolition of landmarks
  - Utility rates, water/sewer infrastructure, and service reliability

  ## What Is Routine (Low-Salience / Not Topic-Worthy)

  The following types of items appear on agendas regularly but are typically routine institutional business, not persistent civic concerns. They should generally NOT become topics:

  - Standard license renewals for existing businesses (liquor, operator, etc.) with no controversy
  - Individual personnel actions (hiring, retirement) unless they affect a key leadership position
  - Routine budget approvals or line-item transfers with no tax impact
  - Procedural committee business (setting meeting dates, approving prior minutes)
  - Proclamations, ceremonial recognitions, and awards
  - Consent agenda items that are truly routine (not bundled controversial items)
  - Standard vendor contract renewals at similar terms
  - Routine report acceptances (monthly financial reports, department updates)

  ## Resident Disposition

  Two Rivers residents tend to:
  - Be skeptical of city leadership, both elected officials and appointed staff
  - Feel that decisions are often made before public input is genuinely considered
  - Pay close attention to who benefits from development and spending decisions
  - Value stability and preservation over growth and change
  - Have strong opinions about downtown character and lakefront use
  - Engage most actively when proposed changes affect their neighborhoods directly

  ## Signals of Resident Importance

  When evaluating whether a civic issue matters to residents, weight these signals:
  - Volume and intensity of public comment on an agenda item (strongest signal)
  - Items that change the physical, economic, or social character of the community
  - Divided or contentious votes (signal the community is not aligned)
  - Issues where institutional framing ("economic development", "revitalization") may not match resident priorities
  - Long-running disputes or concerns that residents keep raising
  - Items where transparency or process complaints arise
CONTEXT

existing = KnowledgeSource.find_by(title: COMMUNITY_CONTEXT_TITLE)
if existing
  puts "Community context KnowledgeSource already exists (ID: #{existing.id}), skipping."
else
  source = KnowledgeSource.create!(
    title: COMMUNITY_CONTEXT_TITLE,
    source_type: "note",
    body: COMMUNITY_CONTEXT_BODY,
    active: true,
    verification_notes: "Seeded from design discussion about Two Rivers resident values and concerns."
  )
  puts "Created community context KnowledgeSource (ID: #{source.id})."
  puts "Run IngestKnowledgeSourceJob.perform_now(#{source.id}) to generate embeddings."
end
```

**Step 2: Load the seed file from db/seeds.rb**

Add to the bottom of `db/seeds.rb`:

```ruby
load Rails.root.join("db/seeds/community_context.rb")
```

**Step 3: Run the seed and ingest**

```bash
bin/rails db:seed
bin/rails runner "ks = KnowledgeSource.find_by(title: 'Two Rivers Community Context — Topic Extraction Guide'); IngestKnowledgeSourceJob.perform_now(ks.id) if ks"
```

Expected: KnowledgeSource created, chunks generated with embeddings.

**Step 4: Commit**

```bash
git add db/seeds/community_context.rb db/seeds.rb
git commit -m "Seed Two Rivers community context KnowledgeSource for AI extraction/triage"
```

---

### Task 2: Fix Audit Trail for Automated Triage Decisions

The `TopicReviewEvent` model requires a `user` (NOT NULL FK). Auto-triage runs without a user, so events are silently skipped. Fix this so all AI decisions are recorded.

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_make_topic_review_event_user_optional.rb`
- Modify: `app/models/topic_review_event.rb:6`
- Modify: `app/services/topics/triage_tool.rb:247-256`
- Test: `test/services/topics/triage_tool_test.rb`

**Step 1: Write the failing test**

Create `test/services/topics/triage_tool_test.rb`:

```ruby
require "test_helper"

class Topics::TriageToolTest < ActiveSupport::TestCase
  test "record_review_event creates event without user for automated triage" do
    topic = Topic.create!(name: "test automated audit", status: "proposed")

    # Simulate what auto-triage does: call with no user
    tool = Topics::TriageTool.new(
      apply: true, dry_run: false,
      min_confidence: 0.5, max_topics: 10,
      similarity_threshold: 0.75, agenda_item_limit: 5,
      user_id: nil, user_email: nil
    )

    # Use send to test private method directly
    tool.send(:record_review_event, nil, topic, "approved", "Auto-approve via triage tool: test")

    event = topic.topic_review_events.last
    assert_not_nil event, "Event should be created even without a user"
    assert_nil event.user_id
    assert_equal "approved", event.action
    assert event.automated?, "Event should be marked as automated"
  end
end
```

**Step 2: Run test to verify it fails**

```bash
bin/rails test test/services/topics/triage_tool_test.rb -v
```

Expected: FAIL — `user` column is NOT NULL, and `automated` column/method doesn't exist yet.

**Step 3: Write the migration**

```bash
bin/rails generate migration MakeTopicReviewEventUserOptional
```

Edit the generated migration:

```ruby
class MakeTopicReviewEventUserOptional < ActiveRecord::Migration[8.1]
  def change
    change_column_null :topic_review_events, :user_id, true
    add_column :topic_review_events, :automated, :boolean, default: false, null: false
    add_column :topic_review_events, :confidence, :float
  end
end
```

```bash
bin/rails db:migrate
```

**Step 4: Update the TopicReviewEvent model**

In `app/models/topic_review_event.rb`, change `belongs_to :user` to optional:

```ruby
class TopicReviewEvent < ApplicationRecord
  ACTIONS = %w[approved blocked needs_review unblocked merged].freeze

  belongs_to :topic
  belongs_to :user, optional: true

  validates :action, presence: true, inclusion: { in: ACTIONS }

  scope :automated, -> { where(automated: true) }
  scope :recent, -> { where("created_at > ?", 7.days.ago) }
end
```

**Step 5: Update TriageTool to always record events**

In `app/services/topics/triage_tool.rb`, replace the `record_review_event` method (lines 247-256):

```ruby
def record_review_event(user, topic, action, reason, confidence: nil)
  TopicReviewEvent.create!(
    topic: topic,
    user: user,
    action: action,
    reason: reason,
    automated: user.nil?,
    confidence: confidence
  )
end
```

Also update the callers in `apply_approvals`, `apply_blocks`, and `apply_merges` to pass confidence:

In `apply_approvals` (around line 189):
```ruby
record_review_event(user, topic, "approved", approval_reason(approval), confidence: confidence)
```

In `apply_blocks` (around line 208):
```ruby
record_review_event(user, topic, "blocked", block_reason(block), confidence: confidence)
```

In `apply_merges` (around line 171):
```ruby
record_review_event(user, target_topic, "merged", merge_reason(merge), confidence: confidence)
```

**Step 6: Run test to verify it passes**

```bash
bin/rails test test/services/topics/triage_tool_test.rb -v
```

Expected: PASS

**Step 7: Commit**

```bash
git add db/migrate/*_make_topic_review_event_user_optional.rb app/models/topic_review_event.rb app/services/topics/triage_tool.rb test/services/topics/triage_tool_test.rb
git commit -m "Fix audit trail: record auto-triage decisions without requiring a user"
```

---

### Task 3: Tiered Confidence Thresholds in TriageTool

Replace the single `@min_confidence` with per-action thresholds.

**Files:**
- Modify: `app/services/topics/triage_tool.rb:1-50,152-210`
- Modify: `app/jobs/topics/auto_triage_job.rb`
- Test: `test/services/topics/triage_tool_test.rb` (add tests)

**Step 1: Write the failing tests**

Add to `test/services/topics/triage_tool_test.rb`:

```ruby
test "tiered thresholds: blocks at 0.7 but does not approve at 0.7" do
  topic_block = Topic.create!(name: "routine procedural item", status: "proposed")
  topic_approve = Topic.create!(name: "important civic topic", status: "proposed")

  tool = Topics::TriageTool.new(
    apply: true, dry_run: false,
    min_confidence: { block: 0.7, merge: 0.75, approve: 0.8, approve_novel: 0.9 },
    max_topics: 10,
    similarity_threshold: 0.75, agenda_item_limit: 5,
    user_id: nil, user_email: nil
  )

  # Simulate applying results with confidence at 0.7
  results = {
    "merge_map" => [],
    "approvals" => [{ "topic" => "important civic topic", "approve" => true, "confidence" => 0.7, "rationale" => "test" }],
    "blocks" => [{ "topic" => "routine procedural item", "block" => true, "confidence" => 0.7, "rationale" => "test" }]
  }

  tool.send(:apply_results, results, nil)

  assert_equal "blocked", topic_block.reload.status, "Should block at 0.7"
  assert_equal "proposed", topic_approve.reload.status, "Should NOT approve at 0.7"
end
```

**Step 2: Run test to verify it fails**

```bash
bin/rails test test/services/topics/triage_tool_test.rb -v
```

Expected: FAIL — current code uses a single threshold for all actions.

**Step 3: Update TriageTool to accept and use tiered thresholds**

In `app/services/topics/triage_tool.rb`, update the constants and constructor:

```ruby
DEFAULT_MIN_CONFIDENCE = {
  block: 0.7,
  merge: 0.75,
  approve: 0.8,
  approve_novel: 0.9
}.freeze
```

Update `initialize` to handle both hash and numeric (backward compat):

```ruby
def initialize(apply:, dry_run:, min_confidence:, max_topics:, similarity_threshold:, agenda_item_limit:, user_id:, user_email:)
  @apply = apply
  @dry_run = dry_run
  @min_confidence = normalize_confidence(min_confidence)
  @max_topics = max_topics
  @similarity_threshold = similarity_threshold
  @agenda_item_limit = agenda_item_limit
  @user_id = user_id
  @user_email = user_email
  @log_path = DEFAULT_LOG_PATH
end
```

Add private helper:

```ruby
def normalize_confidence(conf)
  if conf.is_a?(Hash)
    conf.symbolize_keys
  else
    # Legacy: single number applies to all actions
    { block: conf, merge: conf, approve: conf, approve_novel: conf }
  end
end

def confidence_threshold_for(action)
  @min_confidence[action] || @min_confidence[:approve]
end
```

Update `apply_blocks` to use `confidence_threshold_for(:block)`:

```ruby
next if confidence < confidence_threshold_for(:block)
```

Update `apply_merges` to use `confidence_threshold_for(:merge)`:

```ruby
next if confidence < confidence_threshold_for(:merge)
```

Update `apply_approvals` to use `confidence_threshold_for(:approve)`:

```ruby
next if confidence < confidence_threshold_for(:approve)
```

**Step 4: Update AutoTriageJob to use tiered thresholds**

In `app/jobs/topics/auto_triage_job.rb`:

```ruby
def perform
  proposed_count = Topic.where(status: "proposed").count
  if proposed_count == 0
    Rails.logger.info "AutoTriageJob: No proposed topics to triage."
    return
  end

  Rails.logger.info "AutoTriageJob: Triaging #{proposed_count} proposed topics..."
  Topics::TriageTool.call(
    apply: true,
    dry_run: false,
    min_confidence: Topics::TriageTool::DEFAULT_MIN_CONFIDENCE,
    max_topics: 50
  )
end
```

**Step 5: Run tests**

```bash
bin/rails test test/services/topics/triage_tool_test.rb -v
```

Expected: PASS

**Step 6: Commit**

```bash
git add app/services/topics/triage_tool.rb app/jobs/topics/auto_triage_job.rb test/services/topics/triage_tool_test.rb
git commit -m "Replace single triage confidence gate with per-action tiered thresholds"
```

---

### Task 4: Community-Aware Extraction Prompt

Inject community context and existing approved topic names into the extraction prompt. Add `topic_worthy` field. Add `Routine` category.

**Files:**
- Modify: `app/services/ai/open_ai_service.rb:82-132`
- Modify: `app/jobs/extract_topics_job.rb`
- Test: `test/jobs/extract_topics_job_test.rb`

**Step 1: Write the failing test**

Create `test/jobs/extract_topics_job_test.rb`:

```ruby
require "test_helper"

class ExtractTopicsJobTest < ActiveSupport::TestCase
  test "skips items marked topic_worthy false" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/1"
    )
    item = AgendaItem.create!(meeting: meeting, number: "1", title: "Operator License Renewal - Jane Doe", order_index: 1)

    # Stub AI to return topic_worthy: false
    ai_response = {
      "items" => [{
        "id" => item.id,
        "category" => "Licensing",
        "tags" => ["operator license renewal"],
        "topic_worthy" => false,
        "confidence" => 0.9
      }]
    }.to_json

    Ai::OpenAiService.any_instance.stubs(:extract_topics).returns(ai_response)

    assert_no_difference "Topic.count" do
      ExtractTopicsJob.perform_now(meeting.id)
    end
  end

  test "skips items categorized as Routine" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/2"
    )
    item = AgendaItem.create!(meeting: meeting, number: "1", title: "Accept Monthly Financial Report", order_index: 1)

    ai_response = {
      "items" => [{
        "id" => item.id,
        "category" => "Routine",
        "tags" => ["monthly financial report"],
        "topic_worthy" => false,
        "confidence" => 0.8
      }]
    }.to_json

    Ai::OpenAiService.any_instance.stubs(:extract_topics).returns(ai_response)

    assert_no_difference "Topic.count" do
      ExtractTopicsJob.perform_now(meeting.id)
    end
  end

  test "creates topics for items marked topic_worthy true" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/3"
    )
    item = AgendaItem.create!(meeting: meeting, number: "1", title: "Lakefront Development Proposal", order_index: 1)

    ai_response = {
      "items" => [{
        "id" => item.id,
        "category" => "Zoning",
        "tags" => ["lakefront development"],
        "topic_worthy" => true,
        "confidence" => 0.85
      }]
    }.to_json

    Ai::OpenAiService.any_instance.stubs(:extract_topics).returns(ai_response)

    assert_difference "Topic.count", 1 do
      ExtractTopicsJob.perform_now(meeting.id)
    end
  end
end
```

**Step 2: Run tests to verify they fail**

```bash
bin/rails test test/jobs/extract_topics_job_test.rb -v
```

Expected: FAIL — `topic_worthy` not yet respected, `Routine` not yet skipped.

**Step 3: Update the extraction prompt**

In `app/services/ai/open_ai_service.rb`, modify `extract_topics` to accept community context and existing topic names:

```ruby
def extract_topics(items_text, community_context: "", existing_topics: [])
  existing_topics_text = if existing_topics.any?
    "\n<existing_topics>\nThese topics already exist in the system. Prefer tagging items to these existing topics rather than creating new similar names:\n#{existing_topics.join("\n")}\n</existing_topics>\n"
  else
    ""
  end

  community_context_text = if community_context.present?
    "\n<community_context>\n#{community_context}\n</community_context>\n"
  else
    ""
  end

  prompt = <<~PROMPT
    <governance_constraints>
    - Topics are long-lived civic concerns that may span multiple meetings, bodies, and extended periods.
    - Prefer agenda items as structural anchors for topic detection.
    - Distinguish routine procedural items from substantive civic issues.
    - If confidence in topic classification is low, set confidence below 0.5 and classify as "Other".
    - Do not infer motive or speculate about intent behind agenda item placement or wording.
    </governance_constraints>
    #{community_context_text}
    #{existing_topics_text}
    <extraction_spec>
    Classify agenda items into high-level topics. Return JSON matching the schema below.

    - Ignore "Minutes of Meetings" items if they refer to *previous* meetings (e.g. "Approve minutes of X"). Classify these as "Administrative".
    - Do NOT extract topics from the titles of previous meeting minutes (e.g. if item is "Minutes of Public Works", do not tag "Public Works").
    - If an item is purely administrative (Call to Order, Roll Call, Adjournment), classify as "Administrative".
    - If an item is routine institutional business (individual license renewals, standard report acceptances, routine personnel actions, proclamations), classify as "Routine".
    - For each tag, decide whether it represents a persistent civic concern worth tracking as a topic (topic_worthy: true) or a one-time routine item (topic_worthy: false).
    - When a tag matches or is very similar to an existing topic name, use the existing topic name exactly.

    Schema:
    {
      "items": [
        {
          "id": 123,
          "category": "Infrastructure|Public Safety|Parks & Rec|Finance|Zoning|Licensing|Personnel|Governance|Other|Administrative|Routine",
          "tags": ["Tag1", "Tag2"],
          "topic_worthy": true,
          "confidence": 0.9
        }
      ]
    }

    - "confidence" must be between 0.0 and 1.0.
    - "topic_worthy" must be true or false. Set to false for routine, one-off, or procedural items.
    - Use high confidence (>= 0.8) for clear, unambiguous civic topics.
    - Use low confidence (< 0.5) for items where the topic is unclear or could be procedural.
    </extraction_spec>

    Text:
    #{items_text.truncate(50000)}
  PROMPT

  response = @client.chat(
    parameters: {
      model: DEFAULT_MODEL,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: "You are a civic data classifier for Two Rivers, WI." },
        { role: "user", content: prompt }
      ],
      temperature: 0.1
    }
  )
  response.dig("choices", 0, "message", "content")
end
```

**Step 4: Update ExtractTopicsJob to use new features**

In `app/jobs/extract_topics_job.rb`:

```ruby
class ExtractTopicsJob < ApplicationJob
  queue_as :default

  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)
    items = meeting.agenda_items.order(:order_index)

    if items.empty?
      Rails.logger.info "No agenda items for Meeting #{meeting_id} to tag."
      return
    end

    # Format items for AI
    items_text = items.map do |item|
      "ID: #{item.id}\nTitle: #{item.title}\nSummary: #{item.summary}\n"
    end.join("\n---\n")

    # Retrieve community context for extraction
    community_context = retrieve_community_context

    # Get existing approved topic names to reduce duplicates
    existing_topics = Topic.approved.pluck(:name)

    ai_service = ::Ai::OpenAiService.new
    json_response = ai_service.extract_topics(
      items_text,
      community_context: community_context,
      existing_topics: existing_topics
    )

    begin
      data = JSON.parse(json_response)
      classifications = data["items"] || []

      classifications.each do |c_data|
        item_id = c_data["id"]
        category = c_data["category"]
        tags = c_data["tags"] || []
        confidence = c_data["confidence"]&.to_f
        topic_worthy = c_data.fetch("topic_worthy", true)

        # Find item
        item = AgendaItem.find_by(id: item_id)
        next unless item

        if confidence && confidence < 0.5
          Rails.logger.warn "Low-confidence topic classification (#{confidence}) for AgendaItem #{item_id}: category=#{category}, tags=#{tags.inspect}"
        end

        # Skip administrative/procedural/routine items — they don't produce substantive topics
        next if category == "Administrative"
        next if category == "Routine"

        # Skip items the AI determined are not topic-worthy
        next unless topic_worthy

        # Create topics from tags only (category is a broad grouping, not a topic)
        tags.each do |topic_name|
          next if topic_name.blank?

          # Find or Create Topic
          topic = Topics::FindOrCreateService.call(topic_name)
          next unless topic

          # Link
          AgendaItemTopic.find_or_create_by!(agenda_item: item, topic: topic)
        end
      end

      Rails.logger.info "Tagged #{classifications.size} items for Meeting #{meeting_id}"

      # Schedule auto-triage with delay so extraction jobs from the same scraper run
      # complete before triage fires. Multiple enqueues are safe — the job is idempotent.
      Topics::AutoTriageJob.set(wait: 3.minutes).perform_later

    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse topics JSON for Meeting #{meeting_id}: #{e.message}"
    end
  end

  private

  def retrieve_community_context
    retrieval = RetrievalService.new
    results = retrieval.retrieve_context("Two Rivers community values resident concerns topic extraction", limit: 5)
    retrieval.format_context(results)
  rescue => e
    Rails.logger.warn "Failed to retrieve community context for extraction: #{e.message}"
    ""
  end
end
```

**Step 5: Run tests**

```bash
bin/rails test test/jobs/extract_topics_job_test.rb -v
```

Expected: PASS

**Step 6: Run full test suite to check for regressions**

```bash
bin/rails test
```

Expected: All tests pass. The `extract_topics` signature change adds optional kwargs, so existing callers are unaffected.

**Step 7: Commit**

```bash
git add app/services/ai/open_ai_service.rb app/jobs/extract_topics_job.rb test/jobs/extract_topics_job_test.rb
git commit -m "Add community-aware extraction: topic_worthy filter, Routine category, existing topic context"
```

---

### Task 5: Community-Aware Triage Prompt

Inject the same community context into the triage prompt.

**Files:**
- Modify: `app/services/topics/triage_tool.rb:77-104`
- Modify: `app/services/ai/open_ai_service.rb:134-195`

**Step 1: Write the failing test**

Add to `test/services/topics/triage_tool_test.rb`:

```ruby
test "build_context includes community context" do
  Topic.create!(name: "test triage context topic", status: "proposed")

  tool = Topics::TriageTool.new(
    apply: false, dry_run: true,
    min_confidence: Topics::TriageTool::DEFAULT_MIN_CONFIDENCE,
    max_topics: 10,
    similarity_threshold: 0.75, agenda_item_limit: 5,
    user_id: nil, user_email: nil
  )

  context = tool.send(:build_context)
  assert context.key?(:community_context), "Context should include community_context key"
end
```

**Step 2: Run test to verify it fails**

```bash
bin/rails test test/services/topics/triage_tool_test.rb -v
```

Expected: FAIL — `build_context` doesn't include `:community_context` yet.

**Step 3: Update TriageTool.build_context**

In `app/services/topics/triage_tool.rb`, add community context retrieval to `build_context`:

```ruby
def build_context
  topics = Topic.where(status: "proposed")
                .order(last_activity_at: :desc)
                .limit(@max_topics)
                .includes(:agenda_items)

  topic_payloads = topics.map do |topic|
    agenda_items = topic.agenda_items.first(@agenda_item_limit)
    {
      id: topic.id,
      name: topic.name,
      canonical_name: topic.canonical_name,
      lifecycle_status: topic.lifecycle_status,
      status: topic.status,
      last_activity_at: topic.last_activity_at&.iso8601,
      agenda_items: agenda_items.map { |item| { id: item.id, title: item.title, summary: item.summary } }
    }
  end

  similarity_candidates = build_similarity_candidates(topics)

  {
    procedural_keywords: PROCEDURAL_KEYWORDS,
    similarity_threshold: @similarity_threshold,
    topics: topic_payloads,
    similarity_candidates: similarity_candidates,
    community_context: retrieve_community_context
  }
end
```

Add the private method:

```ruby
def retrieve_community_context
  retrieval = RetrievalService.new
  results = retrieval.retrieve_context("Two Rivers community values resident concerns topic triage approval", limit: 5)
  retrieval.format_context(results)
rescue => e
  Rails.logger.warn "Failed to retrieve community context for triage: #{e.message}"
  ""
end
```

**Step 4: Update the triage_topics prompt in OpenAiService**

In `app/services/ai/open_ai_service.rb`, update the `triage_topics` method to use community context from the input JSON. Add to the prompt after `<governance_constraints>`:

```ruby
def triage_topics(context_json)
  community_context = context_json.delete(:community_context) || context_json.delete("community_context") || ""

  community_section = if community_context.present?
    "\n<community_context>\nUse this context about Two Rivers residents to inform your approval and blocking decisions. Topics that matter to residents should be approved; routine institutional items should be blocked.\n#{community_context}\n</community_context>\n"
  else
    ""
  end

  prompt = <<~PROMPT
    You are assisting a civic transparency system. Propose topic merges, approvals, and procedural blocks.

    <governance_constraints>
    - Topic Governance is binding.
    - Prefer resident-facing canonical topics over granular variations (e.g., "Alcohol licensing" over "Beer"/"Wine").
    - Do NOT merge if scope is ambiguous or evidence conflicts.
    - Procedural/admin items should be blocked (Roberts Rules, roll call, adjournment, agenda approval, minutes).
    </governance_constraints>
    #{community_section}
    <input>
    The JSON includes:
    - topics: list of topic records with recent agenda items.
    - similarity_candidates: suggested similar topics.
    - procedural_keywords: keywords that indicate procedural items.
    </input>

    <output_schema>
    Return JSON with the exact schema below.
    {
      "merge_map": [
        { "canonical": "Topic Name", "aliases": ["Alt1", "Alt2"], "confidence": 0.0, "rationale": "..." }
      ],
      "approvals": [
        { "topic": "Topic Name", "approve": true, "confidence": 0.0, "rationale": "..." }
      ],
      "blocks": [
        { "topic": "Topic Name", "block": true, "confidence": 0.0, "rationale": "..." }
      ]
    }
    </output_schema>

    <rules>
    - "confidence" must be between 0.0 and 1.0.
    - Only include items you are confident about.
    - If unsure, omit the entry.
    - Rationale should be short and cite the evidence signals (agenda items/titles).
    </rules>

    INPUT JSON:
    #{context_json.to_json}
  PROMPT
  # ... rest of method unchanged
```

**Step 5: Run tests**

```bash
bin/rails test test/services/topics/triage_tool_test.rb -v
```

Expected: PASS

**Step 6: Commit**

```bash
git add app/services/topics/triage_tool.rb app/services/ai/open_ai_service.rb test/services/topics/triage_tool_test.rb
git commit -m "Inject community context into triage prompt for resident-aware approval decisions"
```

---

### Task 6: Blocklist Learning on Admin Block

When an admin blocks a topic, auto-add similar name variants to the blocklist.

**Files:**
- Modify: `app/controllers/admin/topics_controller.rb:97-101`
- Test: `test/controllers/admin/topics_controller_test.rb` (add test)

**Step 1: Write the failing test**

Add to `test/controllers/admin/topics_controller_test.rb` (or create if needed — check the existing file first for setup patterns):

```ruby
test "blocking a topic adds similar names to blocklist" do
  topic = Topic.create!(name: "public comment period", status: "proposed")
  # Create a similar-named topic that should get blocklisted
  Topic.create!(name: "public comments", status: "proposed")

  sign_in_as_admin # use whatever auth helper exists

  post block_admin_topic_path(topic)

  # The blocked topic's name should be on the blocklist
  assert TopicBlocklist.exists?(name: "public comment period")
end
```

Note: Check the existing test file for auth setup patterns before writing this test.

**Step 2: Run test to verify it fails**

```bash
bin/rails test test/controllers/admin/topics_controller_test.rb -n "/blocking.*blocklist/" -v
```

Expected: FAIL — block action doesn't touch the blocklist currently.

**Step 3: Update the block action**

In `app/controllers/admin/topics_controller.rb`, modify the `block` method:

```ruby
def block
  @topic.update(status: "blocked", review_status: "blocked")
  record_review_event(@topic, "blocked")
  expand_blocklist(@topic.name)
  render_turbo_update("Topic blocked.")
end
```

Add private method:

```ruby
def expand_blocklist(blocked_name)
  # Add the exact name
  TopicBlocklist.find_or_create_by(name: TopicBlocklist.new(name: blocked_name).tap(&:normalize_name).name)

  # Add similar variants via pg_trgm
  similar_names = Topic.similar_to(blocked_name, 0.8)
                       .where(status: "blocked")
                       .pluck(:name)

  similar_names.each do |variant|
    TopicBlocklist.find_or_create_by(name: TopicBlocklist.new(name: variant).tap(&:normalize_name).name)
  end
rescue => e
  Rails.logger.warn "Blocklist expansion failed for '#{blocked_name}': #{e.message}"
end
```

**Step 4: Run tests**

```bash
bin/rails test test/controllers/admin/topics_controller_test.rb -v
```

Expected: PASS

**Step 5: Commit**

```bash
git add app/controllers/admin/topics_controller.rb test/controllers/admin/topics_controller_test.rb
git commit -m "Auto-expand blocklist with similar name variants when admin blocks a topic"
```

---

### Task 7: Admin Audit View — "Recent AI Decisions" Tab

Add a tab to the admin topics index showing auto-triage decisions from the last 7 days.

**Files:**
- Modify: `app/controllers/admin/topics_controller.rb:5-38`
- Modify: `app/views/admin/topics/index.html.erb:12-36`
- Create: `app/views/admin/topics/_ai_decisions.html.erb`

**Step 1: Update the controller to support the new tab**

In `app/controllers/admin/topics_controller.rb`, add to the `index` method, after the existing filter logic:

```ruby
def index
  @preview_window = helpers.preview_window_from_params(params)

  if params[:view] == "ai_decisions"
    @ai_events = TopicReviewEvent.automated
                                 .recent
                                 .includes(:topic)
                                 .order(created_at: :desc)
    @ai_events_count = @ai_events.count
    return render :index
  end

  # ... rest of existing index logic unchanged
end
```

**Step 2: Add the tab button to the view**

In `app/views/admin/topics/index.html.erb`, add after the "All Topics" link (around line 25):

```erb
<%= link_to "AI Decisions", admin_topics_path(view: "ai_decisions"), class: "btn #{params[:view] == 'ai_decisions' ? 'btn--primary' : 'btn--secondary'}" %>
```

Update the `all_active` variable to exclude the ai_decisions view:

```erb
<% all_active = params[:review_status].blank? && params[:status].blank? && params[:view].blank? %>
```

**Step 3: Add conditional rendering for AI decisions view**

In `app/views/admin/topics/index.html.erb`, wrap the existing table in a condition and add the AI decisions view. After the search/filter card (around line 49), before the bulk update form:

```erb
<% if params[:view] == "ai_decisions" %>
  <%= render "ai_decisions" %>
<% else %>
  <%# ... existing bulk update form and table ... %>
<% end %>
```

**Step 4: Create the AI decisions partial**

Create `app/views/admin/topics/_ai_decisions.html.erb`:

```erb
<div class="card">
  <h2 class="text-lg font-bold mb-4">Recent AI Decisions (Last 7 Days)</h2>

  <% if @ai_events.any? %>
    <div class="table-wrapper">
      <table>
        <thead>
          <tr>
            <th>Date</th>
            <th>Topic</th>
            <th>Action</th>
            <th>Confidence</th>
            <th>Rationale</th>
            <th class="text-right">Undo</th>
          </tr>
        </thead>
        <tbody>
          <% @ai_events.each do |event| %>
            <% next unless event.topic %>
            <tr>
              <td class="text-sm"><%= event.created_at.strftime("%b %d, %H:%M") %></td>
              <td>
                <%= link_to event.topic.name, admin_topic_path(event.topic) %>
              </td>
              <td>
                <% badge_class = case event.action
                   when "approved" then "badge--success"
                   when "blocked" then "badge--danger"
                   when "merged" then "badge--info"
                   else "badge--default"
                end %>
                <span class="badge <%= badge_class %>"><%= event.action.capitalize %></span>
              </td>
              <td class="text-sm">
                <% if event.confidence %>
                  <%= (event.confidence * 100).round %>%%
                <% else %>
                  —
                <% end %>
              </td>
              <td class="text-sm text-secondary"><%= truncate(event.reason.to_s, length: 80) %></td>
              <td class="text-right">
                <% if event.action == "approved" %>
                  <%= button_to "Block", block_admin_topic_path(event.topic), method: :post, class: "btn btn--danger btn--sm" %>
                <% elsif event.action == "blocked" %>
                  <%= button_to "Approve", approve_admin_topic_path(event.topic), method: :post, class: "btn btn--success btn--sm" %>
                <% end %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  <% else %>
    <p class="text-secondary">No automated decisions in the last 7 days.</p>
  <% end %>
</div>
```

**Step 5: Test manually**

```bash
bin/dev
```

Navigate to `/admin/topics?view=ai_decisions`. Should show the new tab and (after tasks 2-5 are in place) display auto-triage decisions.

**Step 6: Commit**

```bash
git add app/controllers/admin/topics_controller.rb app/views/admin/topics/index.html.erb app/views/admin/topics/_ai_decisions.html.erb
git commit -m "Add AI Decisions audit tab to admin topics for reviewing auto-triage actions"
```

---

### Task 8: Integration Verification

Run the full suite and CI checks to verify nothing is broken.

**Step 1: Run full test suite**

```bash
bin/rails test
```

Expected: All tests pass.

**Step 2: Run CI checks**

```bash
bin/ci
```

Expected: RuboCop, Brakeman, bundler-audit, importmap audit all pass.

**Step 3: Verify seed works on fresh DB (optional)**

```bash
bin/rails db:seed
```

Expected: Community context KnowledgeSource created (or "already exists" message).

**Step 4: Commit any fixes needed**

If any linting or security issues surface, fix and commit.

---

### Dependency Order

```
Task 1 (seed community context) — no dependencies, other tasks need this for RAG
Task 2 (audit trail fix) — no dependencies, Task 3 builds on this
Task 3 (tiered thresholds) — depends on Task 2
Task 4 (extraction prompt) — depends on Task 1
Task 5 (triage prompt) — depends on Tasks 1, 2, 3
Task 6 (blocklist learning) — independent
Task 7 (admin audit view) — depends on Task 2 (needs automated events to display)
Task 8 (integration) — depends on all
```

Recommended execution order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8

Tasks 4 and 6 could run in parallel after their dependencies are met.
