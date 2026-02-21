# Auto-Generated Topic Descriptions — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Auto-generate short (max 80 char) static descriptions for approved topics, with periodic refresh and admin override support.

**Architecture:** A `Topics::GenerateDescriptionJob` calls a lightweight OpenAI model to produce one-sentence scope descriptions. It's triggered on topic approval (via TriageTool), on a weekly refresh schedule, and via backfill. A `description_generated_at` column distinguishes AI-generated descriptions from admin-edited ones.

**Tech Stack:** Rails 8.1, Solid Queue recurring jobs, OpenAI API via `ruby-openai`, Minitest

**Design doc:** `docs/plans/2026-02-21-auto-topic-descriptions-design.md`

---

### Task 1: Migration — Add `description_generated_at` to topics

**Files:**
- Create: `db/migrate/XXXXXX_add_description_generated_at_to_topics.rb`

**Step 1: Generate the migration**

Run:
```bash
bin/rails generate migration AddDescriptionGeneratedAtToTopics description_generated_at:datetime
```

**Step 2: Verify the migration file**

It should contain:
```ruby
class AddDescriptionGeneratedAtToTopics < ActiveRecord::Migration[8.1]
  def change
    add_column :topics, :description_generated_at, :datetime
  end
end
```

**Step 3: Run the migration**

Run: `bin/rails db:migrate`
Expected: schema.rb updated, `description_generated_at` column present on `topics` table.

**Step 4: Commit**

```bash
git add db/migrate/*_add_description_generated_at_to_topics.rb db/schema.rb
git commit -m "feat: add description_generated_at column to topics"
```

---

### Task 2: Add `LIGHTWEIGHT_MODEL` constant to `OpenAiService`

**Files:**
- Modify: `app/services/ai/open_ai_service.rb:4` (add new constant after DEFAULT_MODEL)

**Step 1: Add the constant**

In `app/services/ai/open_ai_service.rb`, after line 5 (`DEFAULT_GEMINI_MODEL`), add:

```ruby
LIGHTWEIGHT_MODEL = ENV.fetch("OPENAI_LIGHTWEIGHT_MODEL", "gpt-4.1-mini")
```

**Step 2: Commit**

```bash
git add app/services/ai/open_ai_service.rb
git commit -m "feat: add LIGHTWEIGHT_MODEL constant to OpenAiService"
```

---

### Task 3: Add `generate_topic_description` method to `OpenAiService`

**Files:**
- Test: `test/services/ai/open_ai_service_generate_description_test.rb`
- Modify: `app/services/ai/open_ai_service.rb`

**Step 1: Write the failing test**

Create `test/services/ai/open_ai_service_generate_description_test.rb`:

```ruby
require "test_helper"
require "minitest/mock"

class Ai::OpenAiServiceGenerateDescriptionTest < ActiveSupport::TestCase
  setup do
    @service = Ai::OpenAiService.new
  end

  test "generates description for topic with 3+ agenda items (activity-based)" do
    context = {
      topic_name: "senior center renovation",
      agenda_items: [
        { title: "Senior Center roof bid", summary: "Council reviewed bids for roof repair." },
        { title: "Senior Center HVAC replacement", summary: "Discussion of HVAC system quotes." },
        { title: "Senior Center funding update", summary: "Grant application status report." }
      ],
      headlines: ["Council approves $2.1M senior center contract"]
    }

    mock_response = {
      "choices" => [
        { "message" => { "content" => "Renovation plans and funding for the Two Rivers Senior Center." } }
      ]
    }

    mock_client = Minitest::Mock.new
    mock_client.expect :chat, mock_response do |params:|
      params[:model] == Ai::OpenAiService::LIGHTWEIGHT_MODEL &&
        params[:messages].last[:content].include?("senior center renovation") &&
        params[:messages].last[:content].include?("based on the following activity")
    end

    @service.stub :client, mock_client do
      result = @service.generate_topic_description(context)
      assert_equal "Renovation plans and funding for the Two Rivers Senior Center.", result
    end

    mock_client.verify
  end

  test "generates broad description for topic with fewer than 3 agenda items" do
    context = {
      topic_name: "alley vacation",
      agenda_items: [
        { title: "Alley vacation request - 100 block", summary: nil }
      ],
      headlines: []
    }

    mock_response = {
      "choices" => [
        { "message" => { "content" => "Requests to vacate city-owned alleys adjoining private property." } }
      ]
    }

    mock_client = Minitest::Mock.new
    mock_client.expect :chat, mock_response do |params:|
      params[:model] == Ai::OpenAiService::LIGHTWEIGHT_MODEL &&
        params[:messages].last[:content].include?("alley vacation") &&
        params[:messages].last[:content].include?("broad civic-concept")
    end

    @service.stub :client, mock_client do
      result = @service.generate_topic_description(context)
      assert_equal "Requests to vacate city-owned alleys adjoining private property.", result
    end

    mock_client.verify
  end

  test "returns nil on empty API response" do
    context = { topic_name: "test", agenda_items: [], headlines: [] }

    mock_response = { "choices" => [{ "message" => { "content" => "" } }] }

    mock_client = Minitest::Mock.new
    mock_client.expect :chat, mock_response, **[Hash]

    @service.stub :client, mock_client do
      result = @service.generate_topic_description(context)
      assert_nil result
    end
  end
end
```

**Step 2: Run the test to verify it fails**

Run: `bin/rails test test/services/ai/open_ai_service_generate_description_test.rb`
Expected: FAIL — `generate_topic_description` method does not exist.

**Step 3: Implement `generate_topic_description`**

Add this method to `app/services/ai/open_ai_service.rb` in the public section (after `analyze_topic_summary` ends around line 365):

```ruby
def generate_topic_description(topic_context)
  topic_name = topic_context[:topic_name]
  agenda_items = topic_context[:agenda_items] || []
  headlines = topic_context[:headlines] || []

  activity_section = if agenda_items.size >= 3
    items_text = agenda_items.map { |ai|
      line = "- #{ai[:title]}"
      line += ": #{ai[:summary]}" if ai[:summary].present?
      line
    }.join("\n")

    <<~TEXT
      This topic has appeared in #{agenda_items.size} agenda items. Based on the following activity, describe what this topic covers in Two Rivers:

      #{items_text}
    TEXT
  else
    "This topic has limited activity. Write a broad civic-concept description that a Two Rivers resident would understand."
  end

  headline_section = if headlines.any?
    "\nRecent headlines for context (do NOT copy these):\n#{headlines.map { |h| "- #{h}" }.join("\n")}\n"
  else
    ""
  end

  prompt = <<~PROMPT
    Topic name: "#{topic_name}"

    #{activity_section}
    #{headline_section}
    Write ONE sentence (max 80 characters) describing the scope of this topic.
    - Describe what this topic covers, not a specific event or decision.
    - Do not mention specific addresses, applicant names, dates, or vote counts.
    - Use plain language a neighbor would use, not bureaucratic jargon.
    - Do not start with "This topic" or "Covers".
    - Return ONLY the sentence, no quotes or extra text.
  PROMPT

  response = client.chat(
    params: {
      model: LIGHTWEIGHT_MODEL,
      messages: [
        { role: "system", content: "You write concise civic topic descriptions for a local government transparency site. Respond with JSON." },
        { role: "user", content: prompt }
      ],
      temperature: 0.3
    }
  )

  result = response.dig("choices", 0, "message", "content").to_s.strip
  result.presence
end
```

**Important:** The existing `OpenAiService` uses `@client.chat(parameters: {...})` (note: `parameters` key, not `params`). Match the existing pattern exactly. Check the actual method signature used in other methods (e.g., `analyze_topic_summary` at line 352) and use the same pattern. The `client` accessor may need to reference `@client` directly.

**Step 4: Run the test to verify it passes**

Run: `bin/rails test test/services/ai/open_ai_service_generate_description_test.rb`
Expected: All 3 tests PASS.

**Step 5: Commit**

```bash
git add test/services/ai/open_ai_service_generate_description_test.rb app/services/ai/open_ai_service.rb
git commit -m "feat: add generate_topic_description to OpenAiService"
```

---

### Task 4: Create `Topics::GenerateDescriptionJob`

**Files:**
- Test: `test/jobs/topics/generate_description_job_test.rb`
- Create: `app/jobs/topics/generate_description_job.rb`

**Step 1: Write the failing test**

Create `test/jobs/topics/generate_description_job_test.rb`:

```ruby
require "test_helper"
require "minitest/mock"

class Topics::GenerateDescriptionJobTest < ActiveJob::TestCase
  setup do
    @topic = Topic.create!(
      name: "senior center renovation",
      status: "approved",
      review_status: "approved"
    )
    3.times do |i|
      meeting = Meeting.create!(
        body_name: "City Council", meeting_type: "Regular",
        starts_at: i.days.ago, status: "agenda_posted",
        detail_page_url: "http://example.com/m/#{i}"
      )
      item = AgendaItem.create!(meeting: meeting, number: (i + 1).to_s, title: "Senior Center item #{i + 1}", order_index: i)
      AgendaItemTopic.create!(agenda_item: item, topic: @topic)
    end
  end

  test "generates and saves description for topic" do
    mock_service = Minitest::Mock.new
    mock_service.expect :generate_topic_description, "Renovation plans and funding for the Senior Center." do |context|
      context[:topic_name] == "senior center renovation" &&
        context[:agenda_items].size == 3
    end

    Ai::OpenAiService.stub :new, mock_service do
      Topics::GenerateDescriptionJob.perform_now(@topic.id)
    end

    @topic.reload
    assert_equal "Renovation plans and funding for the Senior Center.", @topic.description
    assert_not_nil @topic.description_generated_at

    mock_service.verify
  end

  test "skips topic with recent description_generated_at" do
    @topic.update!(description: "Existing desc.", description_generated_at: 1.day.ago)

    # Should not call AI at all
    Topics::GenerateDescriptionJob.perform_now(@topic.id)

    @topic.reload
    assert_equal "Existing desc.", @topic.description
  end

  test "regenerates if description_generated_at is older than threshold" do
    @topic.update!(description: "Old desc.", description_generated_at: 91.days.ago)

    mock_service = Minitest::Mock.new
    mock_service.expect :generate_topic_description, "Updated description for the Senior Center." do |context|
      true
    end

    Ai::OpenAiService.stub :new, mock_service do
      Topics::GenerateDescriptionJob.perform_now(@topic.id)
    end

    @topic.reload
    assert_equal "Updated description for the Senior Center.", @topic.description
    assert @topic.description_generated_at > 1.minute.ago

    mock_service.verify
  end

  test "skips if AI returns nil" do
    @topic.update!(description: nil, description_generated_at: nil)

    mock_service = Minitest::Mock.new
    mock_service.expect :generate_topic_description, nil do |context|
      true
    end

    Ai::OpenAiService.stub :new, mock_service do
      Topics::GenerateDescriptionJob.perform_now(@topic.id)
    end

    @topic.reload
    assert_nil @topic.description
    assert_nil @topic.description_generated_at
  end

  test "does not overwrite admin-edited description" do
    # Admin edited: description present, description_generated_at nil
    @topic.update!(description: "Admin wrote this.", description_generated_at: nil)

    # Should not call AI
    Topics::GenerateDescriptionJob.perform_now(@topic.id)

    @topic.reload
    assert_equal "Admin wrote this.", @topic.description
  end
end
```

**Step 2: Run the test to verify it fails**

Run: `bin/rails test test/jobs/topics/generate_description_job_test.rb`
Expected: FAIL — `Topics::GenerateDescriptionJob` does not exist.

**Step 3: Implement the job**

Create `app/jobs/topics/generate_description_job.rb`:

```ruby
module Topics
  class GenerateDescriptionJob < ApplicationJob
    queue_as :default

    REFRESH_THRESHOLD = 90.days

    def perform(topic_id)
      topic = Topic.find_by(id: topic_id)
      return unless topic

      # Skip admin-edited descriptions (present description with no generated_at)
      return if topic.description.present? && topic.description_generated_at.nil?

      # Skip recently generated descriptions
      if topic.description_generated_at.present? && topic.description_generated_at > REFRESH_THRESHOLD.ago
        return
      end

      context = build_context(topic)
      description = Ai::OpenAiService.new.generate_topic_description(context)
      return unless description

      topic.update!(description: description, description_generated_at: Time.current)
    end

    private

    def build_context(topic)
      agenda_items = topic.agenda_items
                         .includes(:meeting)
                         .order("meetings.starts_at DESC")
                         .limit(10)

      headlines = topic.topic_summaries
                       .where.not(generation_data: nil)
                       .order(created_at: :desc)
                       .limit(5)
                       .filter_map { |s| s.generation_data&.dig("headline") }

      {
        topic_name: topic.name,
        agenda_items: agenda_items.map { |ai|
          { title: ai.title, summary: ai.summary }
        },
        headlines: headlines
      }
    end
  end
end
```

**Step 4: Run the test to verify it passes**

Run: `bin/rails test test/jobs/topics/generate_description_job_test.rb`
Expected: All 5 tests PASS.

**Step 5: Commit**

```bash
git add test/jobs/topics/generate_description_job_test.rb app/jobs/topics/generate_description_job.rb
git commit -m "feat: add Topics::GenerateDescriptionJob"
```

---

### Task 5: Integrate with `TriageTool.apply_approvals`

**Files:**
- Test: `test/services/topics/triage_tool_description_test.rb`
- Modify: `app/services/topics/triage_tool.rb:203`

**Step 1: Write the failing test**

Create `test/services/topics/triage_tool_description_test.rb`:

```ruby
require "test_helper"
require "minitest/mock"

class Topics::TriageToolDescriptionTest < ActiveSupport::TestCase
  test "enqueues GenerateDescriptionJob after approving a topic" do
    topic = Topic.create!(
      name: "test topic for triage",
      status: "proposed",
      review_status: "proposed"
    )

    triage_results = {
      "merge_map" => [],
      "approvals" => [
        { "topic" => "test topic for triage", "confidence" => 0.95, "rationale" => "Substantive civic topic" }
      ],
      "blocks" => []
    }

    mock_ai = Minitest::Mock.new
    mock_ai.expect :triage_topics, triage_results.to_json, [Hash]

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end

    assert_enqueued_with(job: Topics::GenerateDescriptionJob) do
      RetrievalService.stub :new, retrieval_stub do
        Ai::OpenAiService.stub :new, mock_ai do
          Topics::TriageTool.call(
            apply: true,
            dry_run: false,
            min_confidence: { block: 0.5, merge: 0.5, approve: 0.5, approve_novel: 0.5 },
            max_topics: 10
          )
        end
      end
    end
  end
end
```

**Step 2: Run the test to verify it fails**

Run: `bin/rails test test/services/topics/triage_tool_description_test.rb`
Expected: FAIL — no job enqueued.

**Step 3: Add the enqueue call**

In `app/services/topics/triage_tool.rb`, in the `apply_approvals` method, after line 203 (`topic.update!(status: "approved", review_status: "approved")`), add:

```ruby
        Topics::GenerateDescriptionJob.perform_later(topic.id)
```

**Step 4: Run the test to verify it passes**

Run: `bin/rails test test/services/topics/triage_tool_description_test.rb`
Expected: PASS.

**Step 5: Commit**

```bash
git add test/services/topics/triage_tool_description_test.rb app/services/topics/triage_tool.rb
git commit -m "feat: enqueue description generation on topic approval"
```

---

### Task 6: Admin override — nil out `description_generated_at` on manual edit

**Files:**
- Test: `test/controllers/admin/topics_controller_description_test.rb`
- Modify: `app/controllers/admin/topics_controller.rb:62-78`

**Step 1: Write the failing test**

Create `test/controllers/admin/topics_controller_description_test.rb`:

```ruby
require "test_helper"

class Admin::TopicsControllerDescriptionTest < ActionDispatch::IntegrationTest
  setup do
    @topic = Topic.create!(
      name: "test description override",
      status: "approved",
      review_status: "approved",
      description: "AI generated this.",
      description_generated_at: 1.day.ago
    )

    # Log in as admin — match existing auth pattern in test_helper or use the same approach as other admin controller tests
    user = User.create!(email_address: "admin@test.com", password: "password123456", admin: true)
    post admin_session_path, params: { email_address: user.email_address, password: "password123456" }
  end

  test "nils description_generated_at when admin edits description" do
    patch admin_topic_path(@topic), params: { topic: { description: "Admin wrote this instead." } }

    @topic.reload
    assert_equal "Admin wrote this instead.", @topic.description
    assert_nil @topic.description_generated_at
  end

  test "preserves description_generated_at when admin edits non-description fields" do
    original_generated_at = @topic.description_generated_at

    patch admin_topic_path(@topic), params: { topic: { importance: 5 } }

    @topic.reload
    assert_equal original_generated_at.to_i, @topic.description_generated_at.to_i
  end
end
```

**Note:** Check how existing admin controller tests handle auth. Look at `test/controllers/admin/` for the login pattern and adjust `setup` accordingly.

**Step 2: Run the test to verify it fails**

Run: `bin/rails test test/controllers/admin/topics_controller_description_test.rb`
Expected: FAIL — `description_generated_at` is not nil'd.

**Step 3: Add the override logic**

In `app/controllers/admin/topics_controller.rb`, in the `update` method, after line 63 (`@topic.assign_attributes(topic_params)`), add:

```ruby
      if @topic.will_save_change_to_attribute?(:description)
        @topic.description_generated_at = nil
      end
```

This follows the same pattern as the existing `resident_impact_overridden_at` logic at line 75-77.

**Step 4: Run the test to verify it passes**

Run: `bin/rails test test/controllers/admin/topics_controller_description_test.rb`
Expected: Both tests PASS.

**Step 5: Commit**

```bash
git add test/controllers/admin/topics_controller_description_test.rb app/controllers/admin/topics_controller.rb
git commit -m "feat: nil description_generated_at on admin manual edit"
```

---

### Task 7: Create `Topics::RefreshDescriptionsJob`

**Files:**
- Test: `test/jobs/topics/refresh_descriptions_job_test.rb`
- Create: `app/jobs/topics/refresh_descriptions_job.rb`

**Step 1: Write the failing test**

Create `test/jobs/topics/refresh_descriptions_job_test.rb`:

```ruby
require "test_helper"

class Topics::RefreshDescriptionsJobTest < ActiveJob::TestCase
  test "enqueues GenerateDescriptionJob for stale descriptions" do
    stale = Topic.create!(
      name: "stale topic",
      status: "approved",
      review_status: "approved",
      description: "Old.",
      description_generated_at: 91.days.ago
    )

    fresh = Topic.create!(
      name: "fresh topic",
      status: "approved",
      review_status: "approved",
      description: "Recent.",
      description_generated_at: 10.days.ago
    )

    assert_enqueued_with(job: Topics::GenerateDescriptionJob, args: [stale.id]) do
      Topics::RefreshDescriptionsJob.perform_now
    end
  end

  test "enqueues for topics with blank descriptions" do
    blank = Topic.create!(
      name: "blank description topic",
      status: "approved",
      review_status: "approved",
      description: nil,
      description_generated_at: nil
    )

    # Admin-edited topic (description present, generated_at nil) should be SKIPPED
    admin_edited = Topic.create!(
      name: "admin edited topic",
      status: "approved",
      review_status: "approved",
      description: "Admin wrote this.",
      description_generated_at: nil
    )

    assert_enqueued_with(job: Topics::GenerateDescriptionJob, args: [blank.id]) do
      Topics::RefreshDescriptionsJob.perform_now
    end
  end

  test "skips non-approved topics" do
    proposed = Topic.create!(
      name: "proposed topic",
      status: "proposed",
      review_status: "proposed",
      description: nil
    )

    # Should not enqueue anything for proposed topics
    assert_no_enqueued_jobs(only: Topics::GenerateDescriptionJob) do
      Topics::RefreshDescriptionsJob.perform_now
    end
  end
end
```

**Step 2: Run the test to verify it fails**

Run: `bin/rails test test/jobs/topics/refresh_descriptions_job_test.rb`
Expected: FAIL — `Topics::RefreshDescriptionsJob` does not exist.

**Step 3: Implement the job**

Create `app/jobs/topics/refresh_descriptions_job.rb`:

```ruby
module Topics
  class RefreshDescriptionsJob < ApplicationJob
    queue_as :default

    def perform
      stale_topics.find_each do |topic|
        Topics::GenerateDescriptionJob.perform_later(topic.id)
      end
    end

    private

    def stale_topics
      threshold = Topics::GenerateDescriptionJob::REFRESH_THRESHOLD.ago

      Topic.approved.where(
        "description_generated_at < :threshold OR (description IS NULL AND description_generated_at IS NULL)",
        threshold: threshold
      )
    end
  end
end
```

**Note:** The `(description IS NULL AND description_generated_at IS NULL)` clause catches topics that have never been generated. Topics with `description present + description_generated_at nil` (admin-edited) are excluded.

**Step 4: Run the test to verify it passes**

Run: `bin/rails test test/jobs/topics/refresh_descriptions_job_test.rb`
Expected: All 3 tests PASS.

**Step 5: Commit**

```bash
git add test/jobs/topics/refresh_descriptions_job_test.rb app/jobs/topics/refresh_descriptions_job.rb
git commit -m "feat: add Topics::RefreshDescriptionsJob for weekly refresh"
```

---

### Task 8: Add recurring schedule entry

**Files:**
- Modify: `config/recurring.yml`

**Step 1: Add the schedule entry**

In `config/recurring.yml`, add under the `production:` key:

```yaml
  refresh_topic_descriptions:
    class: Topics::RefreshDescriptionsJob
    queue: default
    schedule: every week on Monday at 3am
```

**Step 2: Commit**

```bash
git add config/recurring.yml
git commit -m "feat: schedule weekly topic description refresh"
```

---

### Task 9: Run full test suite and lint

**Step 1: Run RuboCop**

Run: `bin/rubocop`
Expected: No new offenses. Fix any that appear.

**Step 2: Run full test suite**

Run: `bin/rails test`
Expected: All tests pass, including the new ones.

**Step 3: Run CI checks**

Run: `bin/ci`
Expected: Clean.

**Step 4: Final commit (if any lint fixes needed)**

```bash
git add -A
git commit -m "fix: address lint issues from topic description feature"
```

---

### Task 10: Backfill existing topics

This is a manual step after deployment. Run in rails console:

```ruby
Topic.where(status: "approved").where(description: [nil, ""]).find_each do |t|
  Topics::GenerateDescriptionJob.perform_later(t.id)
end
```

Or create a one-time rake task if preferred. This enqueues ~331 jobs which will process through Solid Queue.
