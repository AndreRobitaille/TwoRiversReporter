# Generated Civic Images Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build automatic, provenance-backed generated civic images for homepage/topic social previews and meeting feature/social images.

**Architecture:** Add a polymorphic `GeneratedImage` model with ActiveStorage, focused eligibility/fingerprinting services, background jobs for topic and meeting generation, and admin repair controls. Image generation stays behind `Ai::OpenAiService`; views read only ready images and fall back cleanly when none exist.

**Tech Stack:** Rails 8.1, ActiveRecord, ActiveStorage, ActiveJob/Solid Queue, Minitest, OpenAI via existing `ruby-openai` client wrapper.

**Commit note:** Repository policy requires explicit user permission before committing. Treat each task's verification point as a commit checkpoint, but do not run `git commit` unless the user asks.

---

## File Structure

### New files

- `db/migrate/*_create_generated_images.rb` — creates generated image provenance table.
- `app/models/generated_image.rb` — status/purpose validation, ActiveStorage attachment, current-image scopes.
- `app/services/generated_images/config.rb` — feature/config gate for automatic generation.
- `app/services/generated_images/homepage_topic_selector.rb` — single source of truth for the homepage top-six image-eligible topic pool.
- `app/services/generated_images/content_fingerprint.rb` — stable digest of summary/briefing source content.
- `app/services/generated_images/meeting_eligibility.rb` — substantive meeting image eligibility and primary-item selection.
- `app/services/generated_images/topic_eligibility.rb` — homepage top-six topic eligibility.
- `app/services/generated_images/visual_brief_builder.rb` — structured brief generation wrapper around `Ai::OpenAiService`.
- `app/services/generated_images/generator.rb` — orchestration service that creates/supersedes records and attaches generated files.
- `app/jobs/generated_images/generate_for_meeting_job.rb` — idempotent meeting image generation job.
- `app/jobs/generated_images/generate_for_topic_job.rb` — idempotent topic image generation job.
- `app/jobs/generated_images/refresh_homepage_topics_job.rb` — checks current top-six pool and enqueues missing/stale topic images.
- `app/controllers/admin/generated_images_controller.rb` — admin repair actions for regenerate/custom prompt/upload/disable.
- `app/views/admin/generated_images/_panel.html.erb` — reusable admin inspection/control panel.
- `test/fixtures/files/generated-image-placeholder.jpg` — tiny valid JPEG fixture for upload/attachment tests.
- `test/models/generated_image_test.rb`
- `test/services/generated_images/content_fingerprint_test.rb`
- `test/services/generated_images/homepage_topic_selector_test.rb`
- `test/services/generated_images/meeting_eligibility_test.rb`
- `test/services/generated_images/generator_test.rb`
- `test/jobs/generated_images/generate_for_meeting_job_test.rb`
- `test/jobs/generated_images/generate_for_topic_job_test.rb`
- `test/jobs/generated_images/refresh_homepage_topics_job_test.rb`
- `test/controllers/admin/generated_images_controller_test.rb`

### Modified files

- `config/routes.rb` — add admin generated image member actions under meetings/topics or a shallow resource.
- `app/models/meeting.rb` — associate generated images and expose `current_generated_image`.
- `app/models/topic.rb` — associate generated images and expose `current_generated_image`.
- `app/controllers/home_controller.rb` — use `GeneratedImages::HomepageTopicSelector` for top story/wire pool and preload ready images.
- `app/controllers/meetings_controller.rb` — preload current generated image.
- `app/controllers/topics_controller.rb` — preload current generated image.
- `app/views/home/_top_story.html.erb` — render ready topic image when present.
- `app/views/home/_wire_card.html.erb` — render ready topic image when present if included in top-six image pool.
- `app/views/meetings/show.html.erb` — set generated OG image and render feature image.
- `app/views/topics/show.html.erb` — set generated OG image.
- `app/assets/stylesheets/home.css` — topic card image styling.
- `app/assets/stylesheets/application.css` — meeting feature image and admin panel styling.
- `app/jobs/summarize_meeting_job.rb` — enqueue meeting image generation after summary creation/update.
- `app/jobs/topics/generate_topic_briefing_job.rb` — enqueue topic image generation when refreshed topic is currently homepage-eligible.
- `app/services/ai/open_ai_service.rb` — add `build_generated_image_brief` and `generate_civic_image` methods.
- `test/controllers/home_controller_test.rb` — image rendering/fallback coverage.
- `test/controllers/meetings_controller_test.rb` — feature image and OG coverage.
- `test/controllers/topics_controller_test.rb` — topic OG coverage.
- `test/jobs/summarize_meeting_job_test.rb` — enqueue coverage.
- `test/services/ai/open_ai_service_test.rb` — brief/image API method coverage.

---

## Task 1: GeneratedImage model and associations

**Files:**
- Create: `db/migrate/*_create_generated_images.rb`
- Create: `app/models/generated_image.rb`
- Modify: `app/models/meeting.rb`
- Modify: `app/models/topic.rb`
- Test: `test/models/generated_image_test.rb`

- [ ] **Step 1: Write the failing model test**

Create `test/models/generated_image_test.rb`:

```ruby
require "test_helper"

class GeneratedImageTest < ActiveSupport::TestCase
  test "validates status and purpose" do
    topic = topics(:one)
    image = GeneratedImage.new(imageable: topic, status: "ready", purpose: "feature_and_og")

    assert image.valid?

    image.status = "unknown"
    assert_not image.valid?
    assert_includes image.errors[:status], "is not included in the list"

    image.status = "ready"
    image.purpose = "unknown"
    assert_not image.valid?
    assert_includes image.errors[:purpose], "is not included in the list"
  end

  test "current_for returns newest ready image for purpose" do
    topic = topics(:one)

    old_image = GeneratedImage.create!(
      imageable: topic,
      status: "ready",
      purpose: "feature_and_og",
      source_content_fingerprint: "old",
      generated_at: 2.days.ago
    )
    new_image = GeneratedImage.create!(
      imageable: topic,
      status: "ready",
      purpose: "feature_and_og",
      source_content_fingerprint: "new",
      generated_at: 1.hour.ago
    )
    GeneratedImage.create!(
      imageable: topic,
      status: "failed",
      purpose: "feature_and_og",
      source_content_fingerprint: "failed",
      generated_at: Time.current
    )

    assert_equal new_image, topic.current_generated_image(:og)
    assert_not_equal old_image, topic.current_generated_image(:og)
  end
end
```

- [ ] **Step 2: Run the model test and verify it fails**

Run: `bin/rails test test/models/generated_image_test.rb`

Expected: FAIL with `uninitialized constant GeneratedImage`.

- [ ] **Step 3: Generate and edit the migration**

Run:

```bash
bin/rails generate model GeneratedImage imageable:references{polymorphic} status:string purpose:string visual_brief:jsonb prompt:text source_summary:references source_briefing:references source_generation_tier:string source_content_fingerprint:string model:string requested_size:string output_format:string retry_count:integer failure_reason:text generated_at:datetime admin_override:boolean custom_prompt:text uploaded_by:references
```

Edit the generated migration so the table definition is:

```ruby
class CreateGeneratedImages < ActiveRecord::Migration[8.1]
  def change
    create_table :generated_images do |t|
      t.references :imageable, polymorphic: true, null: false, index: true
      t.string :status, null: false, default: "pending"
      t.string :purpose, null: false, default: "feature_and_og"
      t.jsonb :visual_brief, null: false, default: {}
      t.text :prompt
      t.references :source_summary, foreign_key: { to_table: :meeting_summaries }
      t.references :source_briefing, foreign_key: { to_table: :topic_briefings }
      t.string :source_generation_tier
      t.string :source_content_fingerprint
      t.string :model
      t.string :requested_size
      t.string :output_format
      t.integer :retry_count, null: false, default: 0
      t.text :failure_reason
      t.datetime :generated_at
      t.boolean :admin_override, null: false, default: false
      t.text :custom_prompt
      t.references :uploaded_by

      t.timestamps
    end

    add_index :generated_images, [ :imageable_type, :imageable_id, :status, :purpose ], name: "index_generated_images_current_lookup"
    add_index :generated_images, :source_content_fingerprint
  end
end
```

- [ ] **Step 4: Implement the model**

Replace `app/models/generated_image.rb` with:

```ruby
class GeneratedImage < ApplicationRecord
  STATUSES = %w[pending processing ready failed superseded disabled].freeze
  PURPOSES = %w[feature og feature_and_og].freeze

  belongs_to :imageable, polymorphic: true
  belongs_to :source_summary, class_name: "MeetingSummary", optional: true
  belongs_to :source_briefing, class_name: "TopicBriefing", optional: true
  belongs_to :uploaded_by, class_name: "User", optional: true

  has_one_attached :file

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :purpose, presence: true, inclusion: { in: PURPOSES }
  validates :retry_count, numericality: { greater_than_or_equal_to: 0 }

  scope :ready, -> { where(status: "ready") }
  scope :usable_for, ->(surface) {
    surface = surface.to_s
    purposes = surface == "og" ? %w[og feature_and_og] : %w[feature feature_and_og]
    ready.where(purpose: purposes).order(generated_at: :desc, created_at: :desc)
  }

  def ready?
    status == "ready"
  end

  def failed?
    status == "failed"
  end

  def retry_available?
    failed? && retry_count < 1
  end
end
```

- [ ] **Step 5: Add associations to Meeting and Topic**

In `app/models/meeting.rb`, inside the class body, add:

```ruby
has_many :generated_images, as: :imageable, dependent: :destroy

def current_generated_image(surface = :feature)
  generated_images.usable_for(surface).first
end
```

In `app/models/topic.rb`, inside the class body, add:

```ruby
has_many :generated_images, as: :imageable, dependent: :destroy

def current_generated_image(surface = :feature)
  generated_images.usable_for(surface).first
end
```

- [ ] **Step 6: Migrate and verify tests**

Run:

```bash
bin/rails db:migrate
bin/rails test test/models/generated_image_test.rb
```

Expected: PASS.

---

## Task 2: Eligibility and fingerprinting services

**Files:**
- Create: `app/services/generated_images/config.rb`
- Create: `app/services/generated_images/homepage_topic_selector.rb`
- Create: `app/services/generated_images/content_fingerprint.rb`
- Create: `app/services/generated_images/topic_eligibility.rb`
- Create: `app/services/generated_images/meeting_eligibility.rb`
- Modify: `app/controllers/home_controller.rb`
- Test: `test/services/generated_images/content_fingerprint_test.rb`
- Test: `test/services/generated_images/homepage_topic_selector_test.rb`
- Test: `test/services/generated_images/meeting_eligibility_test.rb`

- [ ] **Step 1: Write service tests**

Create `test/services/generated_images/content_fingerprint_test.rb`:

```ruby
require "test_helper"

class GeneratedImages::ContentFingerprintTest < ActiveSupport::TestCase
  test "meeting fingerprint changes when summary content changes" do
    summary = MeetingSummary.create!(
      meeting: meetings(:one),
      summary_type: "agenda_preview",
      content: "",
      generation_data: { "headline" => "A", "highlights" => [ { "text" => "One" } ] }
    )

    first = GeneratedImages::ContentFingerprint.for_meeting_summary(summary)
    summary.update!(generation_data: { "headline" => "B", "highlights" => [ { "text" => "Two" } ] })
    second = GeneratedImages::ContentFingerprint.for_meeting_summary(summary)

    assert_not_equal first, second
  end

  test "topic fingerprint uses briefing content" do
    topic = topics(:one)
    briefing = TopicBriefing.create!(
      topic: topic,
      headline: "Residents will watch sidewalk bills",
      generation_tier: "full",
      generation_data: { "editorial_analysis" => { "what_to_watch" => "Assessments" } }
    )

    assert_match(/\A[a-f0-9]{64}\z/, GeneratedImages::ContentFingerprint.for_topic_briefing(briefing))
  end
end
```

Create `test/services/generated_images/homepage_topic_selector_test.rb`:

```ruby
require "test_helper"

class GeneratedImages::HomepageTopicSelectorTest < ActiveSupport::TestCase
  test "returns only top six reusable recent high impact topics" do
    7.times do |i|
      Topic.create!(
        canonical_name: "Image Topic #{i}",
        status: "approved",
        review_status: "approved",
        resident_impact_score: 4,
        last_activity_at: i.hours.ago
      )
    end

    topics = GeneratedImages::HomepageTopicSelector.new.call

    assert_equal 6, topics.size
    assert topics.all? { |topic| topic.resident_impact_score >= 4 }
  end
end
```

Create `test/services/generated_images/meeting_eligibility_test.rb`:

```ruby
require "test_helper"

class GeneratedImages::MeetingEligibilityTest < ActiveSupport::TestCase
  test "eligible with substantive highlight" do
    summary = MeetingSummary.create!(
      meeting: meetings(:one),
      summary_type: "minutes_recap",
      content: "",
      generation_data: {
        "headline" => "Council weighs sidewalk assessments",
        "highlights" => [ { "text" => "Council approved a sidewalk pilot that may bill nearby property owners.", "vote" => "7-0" } ],
        "item_details" => [ { "agenda_item_title" => "Sidewalk replacement program", "summary" => "Repair and billing policy" } ]
      }
    )

    result = GeneratedImages::MeetingEligibility.new(summary.meeting, summary: summary).call

    assert result.eligible?
    assert_equal "Council approved a sidewalk pilot that may bill nearby property owners.", result.primary_text
  end

  test "not eligible with only procedural placeholder content" do
    summary = MeetingSummary.create!(
      meeting: meetings(:one),
      summary_type: "agenda_preview",
      content: "",
      generation_data: {
        "headline" => "The board will meet for routine reports.",
        "highlights" => [ { "text" => "The agenda includes call to order, roll call, approval of minutes, and reports." } ],
        "item_details" => [ { "agenda_item_title" => "Reports and updates" } ]
      }
    )

    result = GeneratedImages::MeetingEligibility.new(summary.meeting, summary: summary).call

    assert_not result.eligible?
    assert_equal "no substantive visual hook", result.reason
  end
end
```

- [ ] **Step 2: Run tests and verify failures**

Run:

```bash
bin/rails test test/services/generated_images/content_fingerprint_test.rb test/services/generated_images/homepage_topic_selector_test.rb test/services/generated_images/meeting_eligibility_test.rb
```

Expected: FAIL with missing constants under `GeneratedImages`.

- [ ] **Step 3: Implement config and selector**

Create `app/services/generated_images/config.rb`:

```ruby
module GeneratedImages
  class Config
    def self.enabled?
      ENV.fetch("GENERATED_IMAGES_ENABLED", "false") == "true"
    end
  end
end
```

Create `app/services/generated_images/homepage_topic_selector.rb`:

```ruby
module GeneratedImages
  class HomepageTopicSelector
    ACTIVITY_WINDOW = 30.days
    MIN_IMPACT = 4
    LIMIT = 6

    def call
      Topic.reusable
        .where("resident_impact_score >= ?", MIN_IMPACT)
        .where("last_activity_at > ?", ACTIVITY_WINDOW.ago)
        .order(resident_impact_score: :desc, last_activity_at: :desc, id: :desc)
        .limit(LIMIT)
        .to_a
    end

    def include?(topic)
      call.map(&:id).include?(topic.id)
    end
  end
end
```

- [ ] **Step 4: Implement fingerprinting**

Create `app/services/generated_images/content_fingerprint.rb`:

```ruby
require "digest"

module GeneratedImages
  class ContentFingerprint
    def self.for_meeting_summary(summary)
      new(summary_payload(summary)).hexdigest
    end

    def self.for_topic_briefing(briefing)
      new(topic_payload(briefing)).hexdigest
    end

    def self.summary_payload(summary)
      {
        type: "meeting_summary",
        id: summary.id,
        summary_type: summary.summary_type,
        generation_data: summary.generation_data,
        updated_at: summary.updated_at&.to_i
      }
    end

    def self.topic_payload(briefing)
      {
        type: "topic_briefing",
        id: briefing.id,
        generation_tier: briefing.generation_tier,
        headline: briefing.headline,
        upcoming_headline: briefing.respond_to?(:upcoming_headline) ? briefing.upcoming_headline : nil,
        generation_data: briefing.generation_data,
        updated_at: briefing.updated_at&.to_i
      }
    end

    def initialize(payload)
      @payload = payload
    end

    def hexdigest
      Digest::SHA256.hexdigest(JSON.generate(@payload.deep_stringify_keys))
    end
  end
end
```

- [ ] **Step 5: Implement topic and meeting eligibility**

Create `app/services/generated_images/topic_eligibility.rb`:

```ruby
module GeneratedImages
  class TopicEligibility
    Result = Data.define(:eligible?, :reason)

    def initialize(topic, selector: HomepageTopicSelector.new)
      @topic = topic
      @selector = selector
    end

    def call
      return Result.new(false, "not in homepage top six") unless @selector.include?(@topic)
      return Result.new(false, "missing briefing") unless @topic.topic_briefing&.headline.present?

      Result.new(true, nil)
    end
  end
end
```

Create `app/services/generated_images/meeting_eligibility.rb`:

```ruby
module GeneratedImages
  class MeetingEligibility
    Result = Data.define(:eligible?, :reason, :primary_text, :composite?)

    WEAK_PATTERNS = /\b(call to order|roll call|approval of minutes|adjourn|reports?|updates?|routine|no assessment appeals|reschedule)\b/i
    STRONG_PATTERNS = /\b(vote|approved|denied|contract|tax|levy|assessment|utility|shutoff|rezon|ordinance|sidewalk|street|water|sewer|budget|grant|hearing|development|policy|funding|rate|fee|permit)\b/i

    def initialize(meeting, summary: nil)
      @meeting = meeting
      @summary = summary || preferred_summary
    end

    def call
      return Result.new(false, "missing summary", nil, false) unless @summary

      candidates = candidate_texts
      primary = candidates.find { |text| substantive?(text) }
      return Result.new(false, "no substantive visual hook", nil, false) unless primary

      strong_count = candidates.count { |text| substantive?(text) }
      Result.new(true, nil, primary, strong_count >= 3)
    end

    private

    def preferred_summary
      @meeting.meeting_summaries.to_a.min_by do |summary|
        %w[minutes_recap transcript_recap packet_analysis agenda_preview].index(summary.summary_type) || 99
      end
    end

    def candidate_texts
      gd = @summary.generation_data || {}
      highlights = Array(gd["highlights"]).map { |h| h["text"].to_s }
      item_texts = Array(gd["item_details"]).flat_map do |item|
        [ item["agenda_item_title"], item["summary"], item["decision"] ].compact.map(&:to_s)
      end
      [ gd["headline"].to_s, *highlights, *item_texts ].map(&:strip).reject(&:blank?)
    end

    def substantive?(text)
      return false if text.length < 40
      return false if text.match?(WEAK_PATTERNS) && !text.match?(STRONG_PATTERNS)

      text.match?(STRONG_PATTERNS)
    end
  end
end
```

- [ ] **Step 6: Reuse selector in HomeController**

In `app/controllers/home_controller.rb`, replace `build_top_stories` with:

```ruby
def build_top_stories
  GeneratedImages::HomepageTopicSelector.new.call.first(TOP_STORY_LIMIT)
end
```

Leave `build_wire` unchanged for now so homepage display behavior remains stable; later view tasks will use the selector to determine which six cards can show images.

- [ ] **Step 7: Run service and homepage tests**

Run:

```bash
bin/rails test test/services/generated_images/content_fingerprint_test.rb test/services/generated_images/homepage_topic_selector_test.rb test/services/generated_images/meeting_eligibility_test.rb test/controllers/home_controller_test.rb
```

Expected: PASS.

---

## Task 3: OpenAI service methods for brief and image generation

**Files:**
- Modify: `app/services/ai/open_ai_service.rb`
- Test: `test/services/ai/open_ai_service_test.rb`

- [ ] **Step 1: Add failing OpenAI service tests**

Append to `test/services/ai/open_ai_service_test.rb`:

```ruby
test "build_generated_image_brief returns parsed JSON" do
  service = Ai::OpenAiService.new
  mock_client = Minitest::Mock.new
  response = {
    "choices" => [
      {
        "message" => {
          "content" => JSON.generate({
            civic_issue: "sidewalk assessments",
            civic_tension: "property owners may be billed for repairs",
            visual_teaching_point: "show repair work connected to a homeowner notice",
            composition: "sidewalk repair area beside a notice envelope",
            avoid: [ "generic coins", "fake city hall" ],
            single_focus: true
          })
        }
      }
    ]
  }

  mock_client.expect :chat, response do |parameters:|
    parameters[:model] == Ai::OpenAiService::LIGHTWEIGHT_MODEL &&
      parameters[:response_format] == { type: "json_object" }
  end

  service.instance_variable_set(:@client, mock_client)

  brief = service.build_generated_image_brief(
    imageable_type: "Meeting",
    source_text: "Council approved sidewalk assessment policy.",
    composite: false
  )

  assert_equal "sidewalk assessments", brief["civic_issue"]
  assert_equal true, brief["single_focus"]
  mock_client.verify
end

test "generate_civic_image returns binary image data and metadata" do
  service = Ai::OpenAiService.new
  fake_client = Object.new

  def fake_client.images
    self
  end

  def fake_client.generate(parameters:)
    {
      "data" => [
        {
          "b64_json" => Base64.strict_encode64("jpeg-bytes"),
          "revised_prompt" => "revised civic illustration prompt"
        }
      ]
    }
  end

  service.instance_variable_set(:@client, fake_client)

  result = service.generate_civic_image(prompt: "Draw a useful civic image", size: "1200x640", output_format: "jpeg")

  assert_equal "jpeg-bytes", result.fetch(:bytes)
  assert_equal "revised civic illustration prompt", result.fetch(:revised_prompt)
  assert_equal "jpeg", result.fetch(:format)
end
```

- [ ] **Step 2: Run tests and verify failure**

Run: `bin/rails test test/services/ai/open_ai_service_test.rb`

Expected: FAIL with missing `build_generated_image_brief` and `generate_civic_image`.

- [ ] **Step 3: Implement OpenAI methods**

In `app/services/ai/open_ai_service.rb`, add methods inside `Ai::OpenAiService`:

```ruby
IMAGE_MODEL = "gpt-image-2".freeze

def build_generated_image_brief(imageable_type:, source_text:, composite: false)
  messages = [
    {
      role: "system",
      content: "You create structured visual briefs for civic editorial illustrations. Return JSON only. Do not invent facts, places, people, or readable document text."
    },
    {
      role: "user",
      content: <<~PROMPT
        Entity type: #{imageable_type}
        Composite image allowed: #{composite}

        Source content:
        #{source_text}

        Return JSON with keys: civic_issue, civic_tension, visual_teaching_point, composition, avoid, single_focus.
        The image should teach the civic issue visually. Avoid generic symbols like coins, gavels, fake documents, and papers under dramatic light.
      PROMPT
    }
  ]

  response = @client.chat(parameters: {
    model: LIGHTWEIGHT_MODEL,
    messages: messages,
    response_format: { type: "json_object" }
  })

  JSON.parse(response.dig("choices", 0, "message", "content"))
end

def generate_civic_image(prompt:, size: "1200x640", output_format: "jpeg")
  response = @client.images.generate(parameters: {
    model: IMAGE_MODEL,
    prompt: prompt,
    size: size,
    output_format: output_format
  })

  data = response.fetch("data").first
  {
    bytes: Base64.decode64(data.fetch("b64_json")),
    revised_prompt: data["revised_prompt"],
    model: IMAGE_MODEL,
    size: size,
    format: output_format
  }
end
```

Add `require "base64"` near the top of the file if not already present.

- [ ] **Step 4: Run tests**

Run: `bin/rails test test/services/ai/open_ai_service_test.rb`

Expected: PASS.

---

## Task 4: Generator orchestration service

**Files:**
- Create: `app/services/generated_images/visual_brief_builder.rb`
- Create: `app/services/generated_images/generator.rb`
- Test: `test/services/generated_images/generator_test.rb`

- [ ] **Step 1: Add failing generator tests**

Create `test/services/generated_images/generator_test.rb`:

```ruby
require "test_helper"

class GeneratedImages::GeneratorTest < ActiveSupport::TestCase
  test "creates ready meeting image and supersedes older ready image" do
    meeting = meetings(:one)
    summary = MeetingSummary.create!(
      meeting: meeting,
      summary_type: "minutes_recap",
      content: "",
      generation_data: {
        "headline" => "Council approved sidewalk assessment policy",
        "highlights" => [ { "text" => "Council approved a sidewalk pilot that may bill nearby property owners." } ]
      }
    )
    old_image = GeneratedImage.create!(imageable: meeting, status: "ready", purpose: "feature_and_og", generated_at: 1.day.ago)

    ai = Minitest::Mock.new
    ai.expect :build_generated_image_brief, {
      "civic_issue" => "sidewalk assessments",
      "civic_tension" => "owners may be billed",
      "visual_teaching_point" => "repair zone plus notice",
      "composition" => "sidewalk repair and notice",
      "avoid" => [ "coins" ],
      "single_focus" => true
    }, [ Hash ]
    ai.expect :generate_civic_image, {
      bytes: file_fixture("generated-image-placeholder.jpg").binread,
      revised_prompt: "revised prompt",
      model: "gpt-image-2",
      size: "1200x640",
      format: "jpeg"
    }, [ Hash ]

    image = GeneratedImages::Generator.new(meeting, source: summary, ai_service: ai).call

    assert_equal "ready", image.status
    assert image.file.attached?
    assert_equal "superseded", old_image.reload.status
    assert_equal image, meeting.current_generated_image(:feature)
    ai.verify
  end

  test "marks failed and increments retry count on image error" do
    meeting = meetings(:one)
    summary = MeetingSummary.create!(
      meeting: meeting,
      summary_type: "minutes_recap",
      content: "",
      generation_data: { "headline" => "Council approved utility rate changes" }
    )

    ai = Object.new
    def ai.build_generated_image_brief(**)
      { "civic_issue" => "utility rates", "composition" => "meter and bill" }
    end
    def ai.generate_civic_image(**)
      raise StandardError, "image blocked"
    end

    image = GeneratedImages::Generator.new(meeting, source: summary, ai_service: ai).call

    assert_equal "failed", image.status
    assert_equal 1, image.retry_count
    assert_match "image blocked", image.failure_reason
  end
end
```

- [ ] **Step 2: Add image fixture**

Create `test/fixtures/files/generated-image-placeholder.jpg` as a tiny valid JPEG. Use this Ruby one-liner if no fixture-writing tool is available:

```bash
ruby -e 'File.binwrite("test/fixtures/files/generated-image-placeholder.jpg", [255,216,255,217].pack("C*"))'
```

- [ ] **Step 3: Run test and verify failure**

Run: `bin/rails test test/services/generated_images/generator_test.rb`

Expected: FAIL with missing `GeneratedImages::Generator`.

- [ ] **Step 4: Implement visual brief builder**

Create `app/services/generated_images/visual_brief_builder.rb`:

```ruby
module GeneratedImages
  class VisualBriefBuilder
    def initialize(imageable, source:, eligibility: nil, ai_service: Ai::OpenAiService.new)
      @imageable = imageable
      @source = source
      @eligibility = eligibility
      @ai_service = ai_service
    end

    def call
      @ai_service.build_generated_image_brief(
        imageable_type: @imageable.class.name,
        source_text: source_text,
        composite: composite?
      )
    end

    private

    def source_text
      if @source.is_a?(MeetingSummary)
        gd = @source.generation_data || {}
        ([ gd["headline"] ] + Array(gd["highlights"]).map { |h| h["text"] } + Array(gd["item_details"]).map { |i| [ i["agenda_item_title"], i["summary"], i["decision"] ].compact.join(" — ") }).compact.join("\n")
      elsif @source.is_a?(TopicBriefing)
        [ @source.headline, @source.respond_to?(:upcoming_headline) ? @source.upcoming_headline : nil, @source.generation_data ].compact.join("\n")
      else
        @source.to_s
      end
    end

    def composite?
      @eligibility.respond_to?(:composite?) && @eligibility.composite?
    end
  end
end
```

- [ ] **Step 5: Implement generator**

Create `app/services/generated_images/generator.rb`:

```ruby
module GeneratedImages
  class Generator
    DEFAULT_SIZE = "1200x640".freeze
    DEFAULT_FORMAT = "jpeg".freeze

    def initialize(imageable, source:, purpose: "feature_and_og", custom_prompt: nil, ai_service: Ai::OpenAiService.new)
      @imageable = imageable
      @source = source
      @purpose = purpose
      @custom_prompt = custom_prompt
      @ai_service = ai_service
    end

    def call
      generated_image = build_record
      generated_image.update!(status: "processing")

      brief = VisualBriefBuilder.new(@imageable, source: @source, ai_service: @ai_service).call
      prompt = @custom_prompt.presence || prompt_from_brief(brief)
      result = @ai_service.generate_civic_image(prompt: prompt, size: DEFAULT_SIZE, output_format: DEFAULT_FORMAT)

      GeneratedImage.transaction do
        supersede_existing_ready_images(except: generated_image)
        generated_image.update!(
          status: "ready",
          visual_brief: brief,
          prompt: result[:revised_prompt].presence || prompt,
          model: result[:model],
          requested_size: result[:size],
          output_format: result[:format],
          generated_at: Time.current,
          failure_reason: nil,
          admin_override: @custom_prompt.present?,
          custom_prompt: @custom_prompt
        )
        generated_image.file.attach(
          io: StringIO.new(result.fetch(:bytes)),
          filename: filename_for(generated_image, result[:format]),
          content_type: "image/#{result[:format]}"
        )
      end

      generated_image
    rescue StandardError => e
      generated_image ||= build_record
      generated_image.update!(status: "failed", retry_count: generated_image.retry_count + 1, failure_reason: e.message)
      generated_image
    end

    private

    def build_record
      GeneratedImage.create!(
        imageable: @imageable,
        status: "pending",
        purpose: @purpose,
        source_summary: @source.is_a?(MeetingSummary) ? @source : nil,
        source_briefing: @source.is_a?(TopicBriefing) ? @source : nil,
        source_generation_tier: source_generation_tier,
        source_content_fingerprint: source_fingerprint,
        retry_count: 0
      )
    end

    def source_generation_tier
      return @source.summary_type if @source.respond_to?(:summary_type)
      return @source.generation_tier if @source.respond_to?(:generation_tier)

      nil
    end

    def source_fingerprint
      if @source.is_a?(MeetingSummary)
        ContentFingerprint.for_meeting_summary(@source)
      elsif @source.is_a?(TopicBriefing)
        ContentFingerprint.for_topic_briefing(@source)
      end
    end

    def prompt_from_brief(brief)
      <<~PROMPT.squish
        Create a mostly unbranded civic editorial illustration for a local government accountability website.
        Civic issue: #{brief["civic_issue"]}.
        Civic tension: #{brief["civic_tension"]}.
        Visual teaching point: #{brief["visual_teaching_point"]}.
        Composition: #{brief["composition"]}.
        Avoid: #{Array(brief["avoid"]).join(", ")}.
        Do not include fake readable document text, recognizable invented people, fake local landmarks, logos, or headline typography.
        Make the issue visually understandable without using generic coins, gavels, or dramatic paperwork clichés.
      PROMPT
    end

    def supersede_existing_ready_images(except:)
      @imageable.generated_images.ready.where.not(id: except.id).update_all(status: "superseded", updated_at: Time.current)
    end

    def filename_for(generated_image, format)
      "generated-image-#{generated_image.id}.#{format}"
    end
  end
end
```

- [ ] **Step 6: Run tests**

Run: `bin/rails test test/services/generated_images/generator_test.rb`

Expected: PASS.

---

## Task 5: Background jobs and summary/briefing hooks

**Files:**
- Create: `app/jobs/generated_images/generate_for_meeting_job.rb`
- Create: `app/jobs/generated_images/generate_for_topic_job.rb`
- Create: `app/jobs/generated_images/refresh_homepage_topics_job.rb`
- Modify: `app/jobs/summarize_meeting_job.rb`
- Modify: `app/jobs/topics/generate_topic_briefing_job.rb`
- Test: `test/jobs/generated_images/generate_for_meeting_job_test.rb`
- Test: `test/jobs/generated_images/generate_for_topic_job_test.rb`
- Test: `test/jobs/generated_images/refresh_homepage_topics_job_test.rb`
- Test: `test/jobs/summarize_meeting_job_test.rb`

- [ ] **Step 1: Write job tests**

Create `test/jobs/generated_images/generate_for_meeting_job_test.rb`:

```ruby
require "test_helper"

class GeneratedImages::GenerateForMeetingJobTest < ActiveJob::TestCase
  test "skips when feature disabled" do
    ENV.stub :fetch, "false" do
      assert_no_difference -> { GeneratedImage.count } do
        GeneratedImages::GenerateForMeetingJob.perform_now(meetings(:one).id)
      end
    end
  end

  test "generates for eligible meeting" do
    meeting = meetings(:one)
    summary = MeetingSummary.create!(
      meeting: meeting,
      summary_type: "minutes_recap",
      content: "",
      generation_data: { "headline" => "Council approved a utility rate policy", "highlights" => [ { "text" => "Council approved a utility rate policy that changes resident bills." } ] }
    )
    generator = Minitest::Mock.new
    generator.expect :call, GeneratedImage.new(imageable: meeting, source_summary: summary)

    ENV.stub :fetch, "true" do
      GeneratedImages::Generator.stub :new, generator do
        GeneratedImages::GenerateForMeetingJob.perform_now(meeting.id)
      end
    end

    generator.verify
  end
end
```

Create `test/jobs/generated_images/generate_for_topic_job_test.rb`:

```ruby
require "test_helper"

class GeneratedImages::GenerateForTopicJobTest < ActiveJob::TestCase
  test "generates for homepage eligible topic with briefing" do
    topic = Topic.create!(canonical_name: "Homepage Image Topic", status: "approved", review_status: "approved", resident_impact_score: 4, last_activity_at: Time.current)
    briefing = TopicBriefing.create!(topic: topic, headline: "Sidewalk bills return", generation_tier: "full")
    generator = Minitest::Mock.new
    generator.expect :call, GeneratedImage.new(imageable: topic, source_briefing: briefing)

    ENV.stub :fetch, "true" do
      GeneratedImages::Generator.stub :new, generator do
        GeneratedImages::GenerateForTopicJob.perform_now(topic.id)
      end
    end

    generator.verify
  end
end
```

Create `test/jobs/generated_images/refresh_homepage_topics_job_test.rb`:

```ruby
require "test_helper"

class GeneratedImages::RefreshHomepageTopicsJobTest < ActiveJob::TestCase
  test "enqueues generation for top six topics" do
    topics = 2.times.map do |i|
      topic = Topic.create!(canonical_name: "Refresh Image Topic #{i}", status: "approved", review_status: "approved", resident_impact_score: 4, last_activity_at: i.minutes.ago)
      TopicBriefing.create!(topic: topic, headline: "Headline #{i}", generation_tier: "full")
      topic
    end

    ENV.stub :fetch, "true" do
      assert_enqueued_with(job: GeneratedImages::GenerateForTopicJob, args: [ topics.first.id ]) do
        GeneratedImages::RefreshHomepageTopicsJob.perform_now
      end
    end
  end
end
```

- [ ] **Step 2: Run job tests and verify failure**

Run:

```bash
bin/rails test test/jobs/generated_images/generate_for_meeting_job_test.rb test/jobs/generated_images/generate_for_topic_job_test.rb test/jobs/generated_images/refresh_homepage_topics_job_test.rb
```

Expected: FAIL with missing job constants.

- [ ] **Step 3: Implement jobs**

Create `app/jobs/generated_images/generate_for_meeting_job.rb`:

```ruby
module GeneratedImages
  class GenerateForMeetingJob < ApplicationJob
    queue_as :default

    def perform(meeting_id, custom_prompt: nil)
      return unless Config.enabled?

      meeting = Meeting.find(meeting_id)
      summary = preferred_summary(meeting)
      eligibility = MeetingEligibility.new(meeting, summary: summary).call
      return unless eligibility.eligible?
      return if current_image_fresh?(meeting, summary)

      Generator.new(meeting, source: summary, custom_prompt: custom_prompt).call
    end

    private

    def preferred_summary(meeting)
      meeting.meeting_summaries.to_a.min_by do |summary|
        %w[minutes_recap transcript_recap packet_analysis agenda_preview].index(summary.summary_type) || 99
      end
    end

    def current_image_fresh?(meeting, summary)
      image = meeting.current_generated_image(:feature)
      return false unless image&.source_content_fingerprint.present?

      image.source_content_fingerprint == ContentFingerprint.for_meeting_summary(summary)
    end
  end
end
```

Create `app/jobs/generated_images/generate_for_topic_job.rb`:

```ruby
module GeneratedImages
  class GenerateForTopicJob < ApplicationJob
    queue_as :default

    def perform(topic_id, custom_prompt: nil)
      return unless Config.enabled?

      topic = Topic.find(topic_id)
      eligibility = TopicEligibility.new(topic).call
      return unless eligibility.eligible?

      briefing = topic.topic_briefing
      return if current_image_fresh?(topic, briefing)

      Generator.new(topic, source: briefing, custom_prompt: custom_prompt).call
    end

    private

    def current_image_fresh?(topic, briefing)
      image = topic.current_generated_image(:feature)
      return false unless image&.source_content_fingerprint.present?

      image.source_content_fingerprint == ContentFingerprint.for_topic_briefing(briefing)
    end
  end
end
```

Create `app/jobs/generated_images/refresh_homepage_topics_job.rb`:

```ruby
module GeneratedImages
  class RefreshHomepageTopicsJob < ApplicationJob
    queue_as :default

    def perform
      return unless Config.enabled?

      HomepageTopicSelector.new.call.each do |topic|
        next unless topic.topic_briefing&.headline.present?

        GenerateForTopicJob.perform_later(topic.id)
      end
    end
  end
end
```

- [ ] **Step 4: Hook meeting generation after summaries**

In `app/jobs/summarize_meeting_job.rb`, after a `MeetingSummary` is successfully created or updated, add:

```ruby
GeneratedImages::GenerateForMeetingJob.perform_later(meeting.id) if GeneratedImages::Config.enabled?
```

Place this after the code path that persists the preferred summary so the image job sees the latest `generation_data`.

- [ ] **Step 5: Hook topic generation after briefing refresh**

In `app/jobs/topics/generate_topic_briefing_job.rb`, after the briefing is saved, add:

```ruby
GeneratedImages::GenerateForTopicJob.perform_later(topic.id) if GeneratedImages::Config.enabled?
```

- [ ] **Step 6: Run job tests**

Run:

```bash
bin/rails test test/jobs/generated_images/generate_for_meeting_job_test.rb test/jobs/generated_images/generate_for_topic_job_test.rb test/jobs/generated_images/refresh_homepage_topics_job_test.rb test/jobs/summarize_meeting_job_test.rb
```

Expected: PASS. If existing summarize tests assert exact enqueued jobs, update them to stub `GeneratedImages::Config.enabled?` as false unless the test is specifically checking image enqueueing.

---

## Task 6: Public rendering and OG meta tags

**Files:**
- Modify: `app/controllers/home_controller.rb`
- Modify: `app/controllers/meetings_controller.rb`
- Modify: `app/controllers/topics_controller.rb`
- Modify: `app/views/home/_top_story.html.erb`
- Modify: `app/views/home/_wire_card.html.erb`
- Modify: `app/views/meetings/show.html.erb`
- Modify: `app/views/topics/show.html.erb`
- Modify: `app/assets/stylesheets/home.css`
- Modify: `app/assets/stylesheets/application.css`
- Test: `test/controllers/home_controller_test.rb`
- Test: `test/controllers/meetings_controller_test.rb`
- Test: `test/controllers/topics_controller_test.rb`

- [ ] **Step 1: Add controller rendering tests**

Add to `test/controllers/home_controller_test.rb`:

```ruby
test "homepage renders ready generated topic images" do
  topic = Topic.create!(canonical_name: "Image Ready Topic", status: "approved", review_status: "approved", resident_impact_score: 4, last_activity_at: Time.current, description: "A visible civic issue")
  TopicBriefing.create!(topic: topic, headline: "Residents face sidewalk bills", generation_tier: "full")
  image = GeneratedImage.create!(imageable: topic, status: "ready", purpose: "feature_and_og", generated_at: Time.current)
  image.file.attach(io: File.open(file_fixture("generated-image-placeholder.jpg")), filename: "topic.jpg", content_type: "image/jpeg")

  get root_path

  assert_response :success
  assert_select ".story-image img[src*='topic.jpg']"
end
```

Add to `test/controllers/meetings_controller_test.rb`:

```ruby
test "meeting show renders generated feature image and og image" do
  meeting = meetings(:one)
  image = GeneratedImage.create!(imageable: meeting, status: "ready", purpose: "feature_and_og", generated_at: Time.current)
  image.file.attach(io: File.open(file_fixture("generated-image-placeholder.jpg")), filename: "meeting.jpg", content_type: "image/jpeg")

  get meeting_path(meeting)

  assert_response :success
  assert_select ".meeting-feature-image img[src*='meeting.jpg']"
  assert_select "meta[property='og:image'][content*='meeting.jpg']", visible: false
end
```

Add to `test/controllers/topics_controller_test.rb`:

```ruby
test "topic show uses generated og image when ready" do
  topic = topics(:one)
  image = GeneratedImage.create!(imageable: topic, status: "ready", purpose: "feature_and_og", generated_at: Time.current)
  image.file.attach(io: File.open(file_fixture("generated-image-placeholder.jpg")), filename: "topic-og.jpg", content_type: "image/jpeg")

  get topic_path(topic)

  assert_response :success
  assert_select "meta[property='og:image'][content*='topic-og.jpg']", visible: false
end
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
bin/rails test test/controllers/home_controller_test.rb test/controllers/meetings_controller_test.rb test/controllers/topics_controller_test.rb
```

Expected: FAIL because views do not render generated images or OG URLs yet.

- [ ] **Step 3: Preload image maps in HomeController**

In `app/controllers/home_controller.rb#index`, after the existing `load_meeting_refs(@top_stories + @wire_cards + @wire_rows)` call, add:

```ruby
load_generated_images(@top_stories + @wire_cards)
```

Add private method:

```ruby
def load_generated_images(topics)
  @generated_images = GeneratedImage
    .with_attached_file
    .where(imageable: topics, status: "ready", purpose: %w[feature feature_and_og])
    .order(generated_at: :desc, created_at: :desc)
    .each_with_object({}) { |image, h| h[image.imageable_id] ||= image }
end
```

- [ ] **Step 4: Render topic images in homepage cards**

In `app/views/home/_top_story.html.erb`, inside `.story-inner` before `.story-topic`, add:

```erb
<% generated_image = defined?(@generated_images) ? @generated_images&.dig(topic.id) : nil %>
<% if generated_image&.file&.attached? %>
  <div class="story-image">
    <%= image_tag generated_image.file, alt: "Illustration for #{topic.name}" %>
  </div>
<% end %>
```

In `app/views/home/_wire_card.html.erb`, inside the link before `.wire-topic`, add:

```erb
<% generated_image = defined?(@generated_images) ? @generated_images&.dig(topic.id) : nil %>
<% if generated_image&.file&.attached? %>
  <div class="wire-image">
    <%= image_tag generated_image.file, alt: "Illustration for #{topic.name}" %>
  </div>
<% end %>
```

- [ ] **Step 5: Add homepage image CSS**

Append to `app/assets/stylesheets/home.css`:

```css
.story-image,
.wire-image {
  margin: calc(var(--space-6) * -1) calc(var(--space-6) * -1) var(--space-4);
  aspect-ratio: 16 / 9;
  overflow: hidden;
  border-bottom: 1px solid var(--color-border);
  background: var(--color-surface-raised);
}

.story-image img,
.wire-image img {
  display: block;
  width: 100%;
  height: 100%;
  object-fit: cover;
}
```

- [ ] **Step 6: Add meeting/topic OG and feature rendering**

In `app/controllers/meetings_controller.rb#show`, set:

```ruby
@generated_image = @meeting.current_generated_image(:feature)
```

In `app/controllers/topics_controller.rb#show`, set:

```ruby
@generated_image = @topic.current_generated_image(:og)
```

In `app/views/meetings/show.html.erb`, after existing `content_for(:og_type)`, add:

```erb
<% if @generated_image&.file&.attached? %>
  <% content_for(:og_image) { url_for(@generated_image.file) } %>
  <% content_for(:og_image_alt) { "Illustration for #{@meeting.body_name.sub(/ Meeting\z/i, '')}" } %>
<% end %>
```

Then after the meeting header closing tag, before source-status banners, add:

```erb
<% if @generated_image&.file&.attached? %>
  <figure class="meeting-feature-image">
    <%= image_tag @generated_image.file, alt: "Illustration for #{@meeting.body_name.sub(/ Meeting\z/i, '')}" %>
  </figure>
<% end %>
```

In `app/views/topics/show.html.erb`, after existing content_for metadata, add:

```erb
<% if @generated_image&.file&.attached? %>
  <% content_for(:og_image) { url_for(@generated_image.file) } %>
  <% content_for(:og_image_alt) { "Illustration for #{@topic.name}" } %>
<% end %>
```

- [ ] **Step 7: Add meeting feature CSS**

Append to `app/assets/stylesheets/application.css`:

```css
.meeting-feature-image {
  margin: var(--space-8) 0;
  border-radius: var(--radius-lg);
  overflow: hidden;
  border: 1px solid var(--color-border);
  background: var(--color-surface-raised);
  box-shadow: var(--shadow-sm);
}

.meeting-feature-image img {
  display: block;
  width: 100%;
  aspect-ratio: 1200 / 640;
  object-fit: cover;
}
```

- [ ] **Step 8: Run rendering tests**

Run:

```bash
bin/rails test test/controllers/home_controller_test.rb test/controllers/meetings_controller_test.rb test/controllers/topics_controller_test.rb
```

Expected: PASS.

---

## Task 7: Admin generated image controls

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/admin/generated_images_controller.rb`
- Create: `app/views/admin/generated_images/_panel.html.erb`
- Modify: relevant admin topic/meeting show/edit views
- Test: `test/controllers/admin/generated_images_controller_test.rb`

- [ ] **Step 1: Add controller tests**

Create `test/controllers/admin/generated_images_controller_test.rb`:

```ruby
require "test_helper"

class Admin::GeneratedImagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    admin_login
  end

  test "regenerate enqueues topic image job" do
    topic = topics(:one)

    assert_enqueued_with(job: GeneratedImages::GenerateForTopicJob, args: [ topic.id ]) do
      post admin_generated_images_regenerate_path(imageable_type: "Topic", imageable_id: topic.id)
    end

    assert_redirected_to admin_topic_path(topic)
  end

  test "disable marks current image disabled" do
    topic = topics(:one)
    image = GeneratedImage.create!(imageable: topic, status: "ready", purpose: "feature_and_og", generated_at: Time.current)

    patch admin_generated_image_disable_path(image)

    assert_redirected_to admin_topic_path(topic)
    assert_equal "disabled", image.reload.status
  end
end
```

If this app uses a different admin-login helper name, copy the setup pattern from `test/controllers/admin/topics_controller_test.rb` exactly.

- [ ] **Step 2: Add admin routes**

In `config/routes.rb`, inside the admin scope, add:

```ruby
post "generated_images/regenerate", to: "admin/generated_images#regenerate", as: :admin_generated_images_regenerate
patch "generated_images/:id/disable", to: "admin/generated_images#disable", as: :admin_generated_image_disable
post "generated_images/upload", to: "admin/generated_images#upload", as: :admin_generated_images_upload
```

- [ ] **Step 3: Implement controller**

Create `app/controllers/admin/generated_images_controller.rb`:

```ruby
module Admin
  class GeneratedImagesController < Admin::BaseController
    def regenerate
      imageable = find_imageable
      custom_prompt = params[:custom_prompt].presence

      if imageable.is_a?(Meeting)
        GeneratedImages::GenerateForMeetingJob.perform_later(imageable.id, custom_prompt: custom_prompt)
      else
        GeneratedImages::GenerateForTopicJob.perform_later(imageable.id, custom_prompt: custom_prompt)
      end

      redirect_back fallback_location: fallback_location_for(imageable), notice: "Image regeneration queued."
    end

    def upload
      imageable = find_imageable
      uploaded = params.require(:generated_image).require(:file)

      GeneratedImage.transaction do
        imageable.generated_images.ready.update_all(status: "superseded", updated_at: Time.current)
        image = imageable.generated_images.create!(
          status: "ready",
          purpose: "feature_and_og",
          admin_override: true,
          generated_at: Time.current,
          visual_brief: { "admin_upload" => true },
          prompt: "Admin-uploaded replacement image"
        )
        image.file.attach(uploaded)
      end

      redirect_back fallback_location: fallback_location_for(imageable), notice: "Replacement image uploaded."
    end

    def disable
      image = GeneratedImage.find(params[:id])
      image.update!(status: "disabled")
      redirect_back fallback_location: fallback_location_for(image.imageable), notice: "Generated image disabled."
    end

    private

    def find_imageable
      type = params.require(:imageable_type)
      id = params.require(:imageable_id)
      raise ActiveRecord::RecordNotFound unless type.in?(%w[Meeting Topic])

      type.constantize.find(id)
    end

    def fallback_location_for(imageable)
      if imageable.is_a?(Meeting)
        admin_job_runs_path
      else
        admin_topic_path(imageable)
      end
    end
  end
end
```

- [ ] **Step 4: Add reusable admin panel partial**

Create `app/views/admin/generated_images/_panel.html.erb`:

```erb
<% current_image = imageable.current_generated_image(:feature) %>

<section class="admin-generated-image-panel card">
  <h2>Generated Image</h2>

  <% if current_image&.file&.attached? %>
    <div class="admin-generated-image-preview">
      <%= image_tag current_image.file, alt: "Generated image preview" %>
    </div>
  <% else %>
    <p class="section-empty">No ready generated image.</p>
  <% end %>

  <% latest_image = imageable.generated_images.order(created_at: :desc).first %>
  <% if latest_image %>
    <dl class="admin-generated-image-meta">
      <dt>Status</dt><dd><%= latest_image.status %></dd>
      <dt>Purpose</dt><dd><%= latest_image.purpose %></dd>
      <dt>Model</dt><dd><%= latest_image.model.presence || "Not generated yet" %></dd>
      <dt>Fingerprint</dt><dd><%= latest_image.source_content_fingerprint.presence || "None" %></dd>
      <dt>Failure</dt><dd><%= latest_image.failure_reason.presence || "None" %></dd>
    </dl>
    <details>
      <summary>Prompt and visual brief</summary>
      <pre><%= JSON.pretty_generate(latest_image.visual_brief || {}) %></pre>
      <pre><%= latest_image.prompt %></pre>
    </details>
  <% end %>

  <%= form_with url: admin_generated_images_regenerate_path, method: :post, class: "admin-generated-image-actions" do |form| %>
    <%= hidden_field_tag :imageable_type, imageable.class.name %>
    <%= hidden_field_tag :imageable_id, imageable.id %>
    <%= form.label :custom_prompt, "Custom prompt" %>
    <%= form.text_area :custom_prompt, rows: 4 %>
    <%= form.submit "Regenerate image", class: "button" %>
  <% end %>

  <%= form_with url: admin_generated_images_upload_path, method: :post, multipart: true, class: "admin-generated-image-actions" do |form| %>
    <%= hidden_field_tag :imageable_type, imageable.class.name %>
    <%= hidden_field_tag :imageable_id, imageable.id %>
    <%= form.label :file, "Upload replacement" %>
    <%= form.file_field :file, name: "generated_image[file]", accept: "image/png,image/jpeg,image/webp" %>
    <%= form.submit "Upload replacement", class: "button button--secondary" %>
  <% end %>

  <% if current_image %>
    <%= button_to "Disable image", admin_generated_image_disable_path(current_image), method: :patch, class: "button button--danger" %>
  <% end %>
</section>
```

- [ ] **Step 5: Render panel in admin topic view and meeting repair surface**

In the admin topic show/edit template that already displays topic details, add:

```erb
<%= render "admin/generated_images/panel", imageable: @topic %>
```

For meetings, if there is no dedicated admin meeting show page, add a generated-image section to `app/views/admin/job_runs/index.html.erb` or the meeting-targeted job run UI only when a meeting is selected. Use:

```erb
<%= render "admin/generated_images/panel", imageable: @meeting if defined?(@meeting) && @meeting.present? %>
```

If the job-runs UI does not expose a single `@meeting`, add a small meeting lookup form to the job-run page that posts to the same regenerate/upload routes with `imageable_type` set to `Meeting` and the selected meeting id. The controller actions are the source of truth for meeting repair behavior.

- [ ] **Step 6: Add admin CSS**

Append to `app/assets/stylesheets/application.css`:

```css
.admin-generated-image-panel {
  margin-block: var(--space-8);
}

.admin-generated-image-preview {
  max-width: 480px;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  overflow: hidden;
  margin-bottom: var(--space-4);
}

.admin-generated-image-preview img {
  display: block;
  width: 100%;
  height: auto;
}

.admin-generated-image-meta {
  display: grid;
  grid-template-columns: max-content 1fr;
  gap: var(--space-2) var(--space-4);
  margin-block: var(--space-4);
}

.admin-generated-image-actions {
  display: grid;
  gap: var(--space-3);
  margin-top: var(--space-4);
}
```

- [ ] **Step 7: Run admin tests**

Run: `bin/rails test test/controllers/admin/generated_images_controller_test.rb`

Expected: PASS.

---

## Task 8: Retry behavior and safer second prompt

**Files:**
- Modify: `app/services/generated_images/generator.rb`
- Modify: `app/jobs/generated_images/generate_for_meeting_job.rb`
- Modify: `app/jobs/generated_images/generate_for_topic_job.rb`
- Test: `test/services/generated_images/generator_test.rb`
- Test: job tests from Task 5

- [ ] **Step 1: Add retry test**

Append to `test/services/generated_images/generator_test.rb`:

```ruby
test "second attempt uses safer prompt suffix" do
  meeting = meetings(:one)
  summary = MeetingSummary.create!(meeting: meeting, summary_type: "minutes_recap", content: "", generation_data: { "headline" => "Council approved utility shutoff policy" })
  prior_failure = GeneratedImage.create!(imageable: meeting, status: "failed", purpose: "feature_and_og", retry_count: 1, failure_reason: "blocked")

  ai = Minitest::Mock.new
  ai.expect :build_generated_image_brief, { "civic_issue" => "utility shutoffs", "composition" => "meter and notice", "avoid" => [] }, [ Hash ]
  ai.expect :generate_civic_image, {
    bytes: file_fixture("generated-image-placeholder.jpg").binread,
    revised_prompt: "safe revised prompt",
    model: "gpt-image-2",
    size: "1200x640",
    format: "jpeg"
  } do |prompt:, size:, output_format:|
    prompt.include?("Use a simpler, safer composition") && size == "1200x640" && output_format == "jpeg"
  end

  image = GeneratedImages::Generator.new(meeting, source: summary, ai_service: ai, retrying_after: prior_failure).call

  assert_equal "ready", image.status
  ai.verify
end
```

- [ ] **Step 2: Update generator initializer and prompt**

Change `GeneratedImages::Generator#initialize` signature to:

```ruby
def initialize(imageable, source:, purpose: "feature_and_og", custom_prompt: nil, retrying_after: nil, ai_service: Ai::OpenAiService.new)
  @imageable = imageable
  @source = source
  @purpose = purpose
  @custom_prompt = custom_prompt
  @retrying_after = retrying_after
  @ai_service = ai_service
end
```

At the end of `prompt_from_brief`, before returning the prompt, append this when retrying:

```ruby
if @retrying_after
  prompt = "#{prompt} Use a simpler, safer composition with fewer elements and no ambiguous people, text, or local landmarks."
end
```

Make `prompt_from_brief` assign the heredoc to a local variable named `prompt` and return it after the conditional.

- [ ] **Step 3: Pass prior failure from jobs**

In both generate jobs, before calling `Generator.new`, find retryable prior failure:

```ruby
prior_failure = imageable.generated_images.where(status: "failed").order(created_at: :desc).first
return if prior_failure && !prior_failure.retry_available?
```

For meeting job use `meeting` as `imageable`; for topic job use `topic` as `imageable`.

Then pass:

```ruby
retrying_after: prior_failure&.retry_available? ? prior_failure : nil
```

- [ ] **Step 4: Run retry tests**

Run:

```bash
bin/rails test test/services/generated_images/generator_test.rb test/jobs/generated_images/generate_for_meeting_job_test.rb test/jobs/generated_images/generate_for_topic_job_test.rb
```

Expected: PASS.

---

## Task 9: Final verification and documentation updates

**Files:**
- Modify: `docs/DEVELOPMENT_PLAN.md`
- Modify: `CLAUDE.md`
- Verify all changed tests and style

- [ ] **Step 1: Update DEVELOPMENT_PLAN**

Add a short subsection under the public website or summary architecture sections:

```markdown
### Generated Civic Images

High-priority homepage topics and substantive meetings may have AI-generated illustrative images. Images are illustrative only: they do not replace official documents, citations, minutes, packets, or transcripts. Topic images are generated only for the actual homepage top-six pool and are reused for topic social previews. Meeting images are generated only when structured summary or agenda content contains enough substantive material; they appear as meeting feature images and social previews.

Generated images store provenance, including source summary/briefing, prompt, visual brief, model, status, and failure reason. Failed generation retries once with a safer prompt, then falls back to text-only cards or the default static OG image. Admins can regenerate, provide a custom prompt, upload a replacement, or disable an image.
```

- [ ] **Step 2: Update CLAUDE.md**

Add a compact note near the AI pipeline/services section:

```markdown
### Generated Civic Images

Generated civic images are represented by `GeneratedImage`, a polymorphic ActiveStorage-backed model for `Meeting` and `Topic`. Generation is handled by `GeneratedImages::*` services/jobs and all OpenAI calls go through `Ai::OpenAiService`. Images are illustrative editorial art, not evidence. Topic generation is limited to the actual homepage top-six pool; meeting generation requires substantive summary/agenda content. Admin repair controls support regenerate, custom prompt, upload replacement, and disable.
```

- [ ] **Step 3: Run targeted tests**

Run:

```bash
bin/rails test test/models/generated_image_test.rb \
  test/services/generated_images/content_fingerprint_test.rb \
  test/services/generated_images/homepage_topic_selector_test.rb \
  test/services/generated_images/meeting_eligibility_test.rb \
  test/services/generated_images/generator_test.rb \
  test/jobs/generated_images/generate_for_meeting_job_test.rb \
  test/jobs/generated_images/generate_for_topic_job_test.rb \
  test/jobs/generated_images/refresh_homepage_topics_job_test.rb \
  test/controllers/home_controller_test.rb \
  test/controllers/meetings_controller_test.rb \
  test/controllers/topics_controller_test.rb \
  test/controllers/admin/generated_images_controller_test.rb \
  test/services/ai/open_ai_service_test.rb
```

Expected: PASS.

- [ ] **Step 4: Run lint**

Run: `bin/rubocop`

Expected: PASS.

- [ ] **Step 5: Run full test suite if time allows**

Run: `bin/rails test`

Expected: PASS.

- [ ] **Step 6: Inspect git diff**

Run:

```bash
git status --short
git diff --stat
```

Expected: only generated image implementation files, docs, and intended test fixture are changed. Existing unrelated untracked files should remain unstaged.

---

## Self-Review

- Spec coverage: covered topic/meeting surfaces, automatic generation, admin overrides, provenance, retry once, fallbacks, cost controls, reference-image limitation, rendering, and verification.
- Placeholder scan: no open placeholder sections are intentionally left for implementers; each task names exact files and commands.
- Type consistency: all new classes live under `GeneratedImages::*`; `GeneratedImage` uses `imageable`, `source_summary`, and `source_briefing` consistently.
- Risk note: admin ownership uses the existing `User` model because admin authentication is based on `Current.user` and `User#admin?`.
