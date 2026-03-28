# Prompt Management & Job Re-Run Console — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move all 14 AI prompts from hardcoded heredocs into a database-backed admin UI with version history, and add an admin console for targeted job re-runs.

**Architecture:** Two new models (`PromptTemplate`, `PromptVersion`) store prompt text with automatic versioning. `OpenAiService` loads prompts from DB and interpolates `{{placeholders}}` at call time. Two new admin pages: a prompt editor with diff/restore, and a job re-run console with target selection. Both use the Silo theme.

**Tech Stack:** Rails 8.1, PostgreSQL, Turbo Frames, Stimulus, `diffy` gem for diffs, Silo theme CSS.

**Design spec:** `docs/plans/2026-03-28-prompt-management-design.md`

---

## File Map

### New Files

| File | Responsibility |
|------|---------------|
| `db/migrate/TIMESTAMP_create_prompt_templates.rb` | Migration for `prompt_templates` and `prompt_versions` tables |
| `app/models/prompt_template.rb` | PromptTemplate model with interpolation and versioning |
| `app/models/prompt_version.rb` | PromptVersion model (snapshot on save) |
| `db/seeds/prompt_templates.rb` | Seeds 14 prompts from current heredocs |
| `app/controllers/admin/prompt_templates_controller.rb` | Admin CRUD (index, edit, update, diff) |
| `app/controllers/admin/job_runs_controller.rb` | Job re-run console (index, create, count) |
| `app/views/admin/prompt_templates/index.html.erb` | Prompt list page |
| `app/views/admin/prompt_templates/edit.html.erb` | Prompt editor with version history |
| `app/views/admin/prompt_templates/_version_diff.html.erb` | Turbo Frame partial for inline diff |
| `app/views/admin/job_runs/index.html.erb` | Job re-run console page |
| `app/javascript/controllers/job_run_controller.js` | Stimulus controller for dynamic target selection |
| `app/javascript/controllers/prompt_editor_controller.js` | Stimulus controller for tab switching and restore |
| `test/models/prompt_template_test.rb` | Model tests |
| `test/models/prompt_version_test.rb` | Model tests |
| `test/controllers/admin/prompt_templates_controller_test.rb` | Controller tests |
| `test/controllers/admin/job_runs_controller_test.rb` | Controller tests |

### Modified Files

| File | Change |
|------|--------|
| `Gemfile` | Add `diffy` gem |
| `db/seeds.rb` | Load `db/seeds/prompt_templates.rb` |
| `config/routes.rb` | Add `prompt_templates` and `job_runs` routes |
| `app/views/layouts/admin.html.erb` | Add "Prompts" and "Job Runs" nav links |
| `app/services/ai/open_ai_service.rb` | Load prompts from DB instead of heredocs |
| `app/assets/stylesheets/application.css` | Add prompt editor and diff CSS classes |

---

## Task 1: Add `diffy` Gem

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Add diffy to Gemfile**

Add after the `redcarpet` line (~line 78):

```ruby
gem "diffy", "~> 3.4"
```

- [ ] **Step 2: Install**

Run: `bundle install`
Expected: `diffy` appears in `Gemfile.lock`

- [ ] **Step 3: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "deps: add diffy gem for prompt version diffs"
```

---

## Task 2: Create Migration

**Files:**
- Create: `db/migrate/TIMESTAMP_create_prompt_templates.rb`

- [ ] **Step 1: Generate migration**

Run: `bin/rails generate migration CreatePromptTemplates`

- [ ] **Step 2: Write migration**

Replace the generated file content with:

```ruby
class CreatePromptTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :prompt_templates do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.text :system_role
      t.text :instructions, null: false
      t.string :model_tier, null: false, default: "default"
      t.jsonb :placeholders, null: false, default: []
      t.timestamps
    end

    add_index :prompt_templates, :key, unique: true

    create_table :prompt_versions do |t|
      t.references :prompt_template, null: false, foreign_key: true
      t.text :system_role
      t.text :instructions, null: false
      t.string :model_tier, null: false
      t.string :editor_note
      t.datetime :created_at, null: false
    end

    add_index :prompt_versions, [:prompt_template_id, :created_at]
  end
end
```

- [ ] **Step 3: Run migration**

Run: `bin/rails db:migrate`
Expected: Tables created, `schema.rb` updated

- [ ] **Step 4: Commit**

```bash
git add db/migrate/*_create_prompt_templates.rb db/schema.rb
git commit -m "db: create prompt_templates and prompt_versions tables"
```

---

## Task 3: PromptVersion Model

**Files:**
- Create: `app/models/prompt_version.rb`
- Create: `test/models/prompt_version_test.rb`

- [ ] **Step 1: Write the test**

```ruby
# test/models/prompt_version_test.rb
require "test_helper"

class PromptVersionTest < ActiveSupport::TestCase
  setup do
    @template = PromptTemplate.create!(
      key: "test_prompt",
      name: "Test Prompt",
      instructions: "Do the thing with {{input}}",
      model_tier: "default"
    )
  end

  test "belongs to prompt_template" do
    version = PromptVersion.create!(
      prompt_template: @template,
      instructions: "Do the thing with {{input}}",
      model_tier: "default",
      editor_note: "Initial"
    )
    assert_equal @template, version.prompt_template
  end

  test "requires instructions" do
    version = PromptVersion.new(prompt_template: @template, model_tier: "default")
    assert_not version.valid?
    assert_includes version.errors[:instructions], "can't be blank"
  end

  test "requires model_tier" do
    version = PromptVersion.new(prompt_template: @template, instructions: "test")
    assert_not version.valid?
    assert_includes version.errors[:model_tier], "can't be blank"
  end

  test "orders by created_at desc" do
    v1 = PromptVersion.create!(prompt_template: @template, instructions: "v1", model_tier: "default", created_at: 2.days.ago)
    v2 = PromptVersion.create!(prompt_template: @template, instructions: "v2", model_tier: "default", created_at: 1.day.ago)

    assert_equal [v2, v1], @template.versions.recent.to_a
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/prompt_version_test.rb`
Expected: NameError — `PromptVersion` not defined

- [ ] **Step 3: Write PromptVersion model**

```ruby
# app/models/prompt_version.rb
class PromptVersion < ApplicationRecord
  belongs_to :prompt_template

  validates :instructions, presence: true
  validates :model_tier, presence: true

  scope :recent, -> { order(created_at: :desc) }
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/models/prompt_version_test.rb`
Expected: 4 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/models/prompt_version.rb test/models/prompt_version_test.rb
git commit -m "feat: add PromptVersion model"
```

---

## Task 4: PromptTemplate Model

**Files:**
- Create: `app/models/prompt_template.rb`
- Create: `test/models/prompt_template_test.rb`

- [ ] **Step 1: Write the test**

```ruby
# test/models/prompt_template_test.rb
require "test_helper"

class PromptTemplateTest < ActiveSupport::TestCase
  test "requires key, name, and instructions" do
    template = PromptTemplate.new
    assert_not template.valid?
    assert_includes template.errors[:key], "can't be blank"
    assert_includes template.errors[:name], "can't be blank"
    assert_includes template.errors[:instructions], "can't be blank"
  end

  test "key must be unique" do
    PromptTemplate.create!(key: "unique_key", name: "Test", instructions: "Do it")
    duplicate = PromptTemplate.new(key: "unique_key", name: "Other", instructions: "Do other")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:key], "has already been taken"
  end

  test "model_tier defaults to default" do
    template = PromptTemplate.create!(key: "tier_test", name: "Test", instructions: "Do it")
    assert_equal "default", template.model_tier
  end

  test "interpolate replaces placeholders" do
    template = PromptTemplate.new(instructions: "Analyze {{items}} using {{context}}")
    result = template.interpolate(items: "agenda item 1", context: "committee info")
    assert_equal "Analyze agenda item 1 using committee info", result
  end

  test "interpolate raises KeyError for missing required placeholder" do
    template = PromptTemplate.new(instructions: "Analyze {{items}} using {{context}}")
    assert_raises(KeyError) do
      template.interpolate(items: "agenda item 1")
    end
  end

  test "interpolate leaves unmatched placeholders when allow_missing is true" do
    template = PromptTemplate.new(instructions: "Analyze {{items}} using {{context}}")
    result = template.interpolate({ items: "agenda item 1" }, allow_missing: true)
    assert_equal "Analyze agenda item 1 using {{context}}", result
  end

  test "interpolate_system_role replaces placeholders in system_role" do
    template = PromptTemplate.new(system_role: "You are a {{role}} analyst")
    result = template.interpolate_system_role(role: "civic")
    assert_equal "You are a civic analyst", result
  end

  test "creates version on save" do
    template = PromptTemplate.create!(key: "version_test", name: "Test", instructions: "v1", model_tier: "default")
    assert_equal 1, template.versions.count

    version = template.versions.first
    assert_equal "v1", version.instructions
    assert_equal "default", version.model_tier
  end

  test "creates version with editor_note on update" do
    template = PromptTemplate.create!(key: "update_test", name: "Test", instructions: "v1")

    template.update!(instructions: "v2", editor_note: "Changed wording")
    assert_equal 2, template.versions.count

    latest = template.versions.recent.first
    assert_equal "v2", latest.instructions
    assert_equal "Changed wording", latest.editor_note
  end

  test "does not create version if text unchanged" do
    template = PromptTemplate.create!(key: "nochange_test", name: "Test", instructions: "same")
    template.update!(name: "Updated Name")
    assert_equal 1, template.versions.count
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/prompt_template_test.rb`
Expected: NameError — `PromptTemplate` not defined

- [ ] **Step 3: Write PromptTemplate model**

```ruby
# app/models/prompt_template.rb
class PromptTemplate < ApplicationRecord
  has_many :versions, class_name: "PromptVersion", dependent: :destroy

  validates :key, presence: true, uniqueness: true
  validates :name, presence: true
  validates :instructions, presence: true
  validates :model_tier, inclusion: { in: %w[default lightweight] }

  # Virtual attribute for passing editor_note through to version creation
  attr_accessor :editor_note

  after_save :create_version_if_changed

  def interpolate(context = {}, allow_missing: false)
    replace_placeholders(instructions, context, allow_missing: allow_missing)
  end

  def interpolate_system_role(context = {}, allow_missing: false)
    replace_placeholders(system_role || "", context, allow_missing: allow_missing)
  end

  private

  def replace_placeholders(text, context, allow_missing: false)
    text.gsub(/\{\{(\w+)\}\}/) do
      key = $1.to_sym
      if context.key?(key)
        context[key].to_s
      elsif allow_missing
        "{{#{$1}}}"
      else
        raise KeyError, "Missing placeholder: {{#{$1}}}"
      end
    end
  end

  def create_version_if_changed
    return unless saved_change_to_instructions? || saved_change_to_system_role? || saved_change_to_model_tier?

    versions.create!(
      system_role: system_role,
      instructions: instructions,
      model_tier: model_tier,
      editor_note: editor_note
    )

    self.editor_note = nil
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/models/prompt_template_test.rb`
Expected: 10 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/models/prompt_template.rb test/models/prompt_template_test.rb
git commit -m "feat: add PromptTemplate model with interpolation and auto-versioning"
```

---

## Task 5: Seed Prompt Templates

**Files:**
- Create: `db/seeds/prompt_templates.rb`
- Modify: `db/seeds.rb`

- [ ] **Step 1: Write the seed file**

```ruby
# db/seeds/prompt_templates.rb
#
# Seeds the 14 AI prompt templates with metadata.
# Actual prompt text must be populated via the admin UI at /admin/prompt_templates
# by copying from the heredocs in app/services/ai/open_ai_service.rb.
# Idempotent — skips existing keys.

PROMPT_TEMPLATES_DATA = [
  {
    key: "extract_votes",
    name: "Vote Extraction",
    description: "Extracts motions and vote records from meeting minutes",
    model_tier: "default",
    placeholders: [
      { "name" => "text", "description" => "Meeting minutes text (truncated to 50k chars)" }
    ]
  },
  {
    key: "extract_committee_members",
    name: "Committee Member Extraction",
    description: "Extracts roll call and attendance from meeting minutes",
    model_tier: "lightweight",
    placeholders: [
      { "name" => "text", "description" => "Meeting minutes text (truncated to 50k chars)" }
    ]
  },
  {
    key: "extract_topics",
    name: "Topic Extraction",
    description: "Classifies agenda items into civic topics",
    model_tier: "default",
    placeholders: [
      { "name" => "existing_topics", "description" => "All approved topic names" },
      { "name" => "community_context", "description" => "Knowledge base context" },
      { "name" => "meeting_documents_context", "description" => "Extracted text from meeting documents" },
      { "name" => "items_text", "description" => "Formatted agenda items to classify" }
    ]
  },
  {
    key: "refine_catchall_topic",
    name: "Catchall Topic Refinement",
    description: "Refines broad ordinance topics into specific civic concerns",
    model_tier: "default",
    placeholders: [
      { "name" => "item_title", "description" => "Agenda item title" },
      { "name" => "item_summary", "description" => "Agenda item summary" },
      { "name" => "catchall_topic", "description" => "The broad topic being refined" },
      { "name" => "document_text", "description" => "Related document text (6k truncated)" },
      { "name" => "existing_topics", "description" => "All approved topic names" }
    ]
  },
  {
    key: "re_extract_item_topics",
    name: "Topic Re-extraction",
    description: "Re-extracts topics when splitting a broad topic",
    model_tier: "default",
    placeholders: [
      { "name" => "item_title", "description" => "Agenda item title" },
      { "name" => "item_summary", "description" => "Agenda item summary" },
      { "name" => "document_text", "description" => "Related document text (6k truncated)" },
      { "name" => "broad_topic_name", "description" => "The broad topic being split" },
      { "name" => "existing_topics", "description" => "All approved topic names" }
    ]
  },
  {
    key: "triage_topics",
    name: "Topic Triage",
    description: "AI-assisted approval, blocking, and merging of proposed topics",
    model_tier: "default",
    placeholders: [
      { "name" => "context_json", "description" => "JSON with topic data, similarities, and community context" }
    ]
  },
  {
    key: "analyze_topic_summary",
    name: "Topic Summary Analysis",
    description: "Structured analysis of a topic's activity in a single meeting",
    model_tier: "default",
    placeholders: [
      { "name" => "committee_context", "description" => "Active committees and descriptions" },
      { "name" => "context_json", "description" => "Topic context JSON with meeting data" }
    ]
  },
  {
    key: "render_topic_summary",
    name: "Topic Summary Rendering",
    description: "Renders structured topic analysis into editorial prose",
    model_tier: "default",
    placeholders: [
      { "name" => "plan_json", "description" => "Structured analysis JSON from pass 1" }
    ]
  },
  {
    key: "analyze_topic_briefing",
    name: "Topic Briefing Analysis",
    description: "Rolling briefing — structured analysis across all meetings for a topic",
    model_tier: "default",
    placeholders: [
      { "name" => "committee_context", "description" => "Active committees and descriptions" },
      { "name" => "context", "description" => "Topic briefing context with all meeting data" }
    ]
  },
  {
    key: "render_topic_briefing",
    name: "Topic Briefing Rendering",
    description: "Renders briefing analysis into editorial content",
    model_tier: "default",
    placeholders: [
      { "name" => "analysis_json", "description" => "Structured briefing analysis JSON from pass 1" }
    ]
  },
  {
    key: "generate_briefing_interim",
    name: "Interim Briefing",
    description: "Quick headline generation for newly approved topics",
    model_tier: "lightweight",
    placeholders: [
      { "name" => "topic_name", "description" => "Name of the topic" },
      { "name" => "current_headline", "description" => "Current headline if any" },
      { "name" => "meeting_body", "description" => "Committee/body name" },
      { "name" => "meeting_date", "description" => "Meeting date" },
      { "name" => "agenda_items", "description" => "Related agenda items" }
    ]
  },
  {
    key: "generate_topic_description_detailed",
    name: "Topic Description (Detailed)",
    description: "Generates scope descriptions for topics with 3+ agenda items",
    model_tier: "lightweight",
    placeholders: [
      { "name" => "topic_name", "description" => "Name of the topic" },
      { "name" => "activity_text", "description" => "Formatted agenda item activity" },
      { "name" => "headlines_text", "description" => "Recent headlines if any" }
    ]
  },
  {
    key: "generate_topic_description_broad",
    name: "Topic Description (Broad)",
    description: "Generates scope descriptions for topics with fewer than 3 agenda items",
    model_tier: "lightweight",
    placeholders: [
      { "name" => "topic_name", "description" => "Name of the topic" },
      { "name" => "activity_text", "description" => "Formatted agenda item activity (may be empty)" },
      { "name" => "headlines_text", "description" => "Recent headlines if any" }
    ]
  },
  {
    key: "analyze_meeting_content",
    name: "Meeting Content Analysis",
    description: "Single-pass structured analysis of full meeting content",
    model_tier: "default",
    placeholders: [
      { "name" => "kb_context", "description" => "Knowledge base context chunks" },
      { "name" => "committee_context", "description" => "Active committees and descriptions" },
      { "name" => "type", "description" => "Document type: packet or minutes" },
      { "name" => "doc_text", "description" => "Meeting document text (truncated to 50k)" }
    ]
  },
  {
    key: "render_meeting_summary",
    name: "Meeting Summary Rendering",
    description: "Renders meeting analysis into editorial prose (legacy)",
    model_tier: "default",
    placeholders: [
      { "name" => "plan_json", "description" => "Structured analysis JSON from pass 1" },
      { "name" => "doc_text", "description" => "Original document text for reference" }
    ]
  }
].freeze

puts "Seeding prompt templates..."

PROMPT_TEMPLATES_DATA.each do |data|
  placeholders = data.delete(:placeholders)
  existing = PromptTemplate.find_by(key: data[:key])

  if existing
    puts "  PromptTemplate '#{data[:key]}' already exists, skipping."
    next
  end

  template = PromptTemplate.create!(
    **data,
    placeholders: placeholders,
    system_role: "TODO: Copy from OpenAiService heredoc via admin UI at /admin/prompt_templates",
    instructions: "TODO: Copy from OpenAiService heredoc via admin UI at /admin/prompt_templates"
  )
  puts "  Created PromptTemplate '#{data[:key]}' (ID: #{template.id})"
end

puts "Done. #{PromptTemplate.count} prompt templates in database."
puts "Next: visit /admin/prompt_templates to populate each prompt with text from OpenAiService."
```

- [ ] **Step 2: Load seed file from db/seeds.rb**

Add to `db/seeds.rb` after the existing lines:

```ruby
load Rails.root.join("db/seeds/prompt_templates.rb")
```

- [ ] **Step 3: Run the seed**

Run: `bin/rails db:seed`
Expected: 15 "Created PromptTemplate" lines (14 original + 1 split for topic description)

- [ ] **Step 4: Verify in console**

Run: `bin/rails runner "puts PromptTemplate.count"`
Expected: `15`

- [ ] **Step 5: Commit**

```bash
git add db/seeds/prompt_templates.rb db/seeds.rb
git commit -m "feat: seed 15 prompt template metadata rows"
```

---

## Task 6: Validation Rake Task

**Files:**
- Create: `lib/tasks/prompt_templates.rake`

- [ ] **Step 1: Write the rake task**

```ruby
# lib/tasks/prompt_templates.rake
namespace :prompt_templates do
  desc "Check that all required prompt templates exist and have real content"
  task validate: :environment do
    expected_keys = %w[
      extract_votes extract_committee_members extract_topics
      refine_catchall_topic re_extract_item_topics triage_topics
      analyze_topic_summary render_topic_summary
      analyze_topic_briefing render_topic_briefing
      generate_briefing_interim generate_topic_description_detailed
      generate_topic_description_broad
      analyze_meeting_content render_meeting_summary
    ]

    missing = []
    placeholder = []

    expected_keys.each do |key|
      template = PromptTemplate.find_by(key: key)
      if template.nil?
        missing << key
      elsif template.instructions.include?("TODO")
        placeholder << key
      end
    end

    if missing.any?
      puts "MISSING templates (run db:seed): #{missing.join(', ')}"
    end

    if placeholder.any?
      puts "PLACEHOLDER text (populate via admin UI): #{placeholder.join(', ')}"
    end

    if missing.empty? && placeholder.empty?
      puts "All #{expected_keys.size} prompt templates present with real content."
    end
  end
end
```

- [ ] **Step 2: Test the rake task**

Run: `bin/rails prompt_templates:validate`
Expected: Lists 15 templates as having placeholder text

- [ ] **Step 3: Commit**

```bash
git add lib/tasks/prompt_templates.rake
git commit -m "feat: add prompt_templates:validate rake task"
```

---

## Task 7: Admin Routes and Navigation

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/views/layouts/admin.html.erb`

- [ ] **Step 1: Add routes**

In `config/routes.rb`, inside the admin route area (after the `members` resource block), add:

```ruby
resources :prompt_templates, controller: "admin/prompt_templates", as: :admin_prompt_templates, only: [:index, :edit, :update] do
  member do
    get :diff
  end
end

resources :job_runs, controller: "admin/job_runs", as: :admin_job_runs, only: [:index, :create] do
  collection do
    get :count
  end
end
```

- [ ] **Step 2: Add nav links**

In `app/views/layouts/admin.html.erb`, find the `<nav>` section with the site navigation links. Add two links after "Knowledge Sources" and before "Jobs":

```erb
<%= link_to "Prompts", admin_prompt_templates_path, class: "site-nav-link #{'active' if controller_name == 'prompt_templates'}" %>
<%= link_to "Job Runs", admin_job_runs_path, class: "site-nav-link #{'active' if controller_name == 'job_runs'}" %>
```

Match the exact class and `active` pattern used by the existing nav links in the layout.

- [ ] **Step 3: Verify routes**

Run: `bin/rails routes | grep prompt_template`
Expected: Shows index, edit, update, and diff routes

Run: `bin/rails routes | grep job_run`
Expected: Shows index, create, and count routes

- [ ] **Step 4: Commit**

```bash
git add config/routes.rb app/views/layouts/admin.html.erb
git commit -m "feat: add admin routes and nav for prompts and job runs"
```

---

## Task 8: Prompt Templates Controller

**Files:**
- Create: `app/controllers/admin/prompt_templates_controller.rb`
- Create: `test/controllers/admin/prompt_templates_controller_test.rb`

- [ ] **Step 1: Write controller test**

```ruby
# test/controllers/admin/prompt_templates_controller_test.rb
require "test_helper"

class Admin::PromptTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(
      email_address: "prompt-admin@example.com",
      password: "password123456",
      admin: true,
      totp_enabled: true
    )
    @admin.ensure_totp_secret!

    post session_url, params: {
      email_address: @admin.email_address,
      password: "password123456"
    }
    post mfa_session_url, params: {
      code: ROTP::TOTP.new(@admin.totp_secret).now
    }

    @template = PromptTemplate.create!(
      key: "test_prompt",
      name: "Test Prompt",
      description: "A test prompt",
      system_role: "You are a test assistant",
      instructions: "Do {{thing}} with {{stuff}}",
      model_tier: "default",
      placeholders: [
        { "name" => "thing", "description" => "The thing" },
        { "name" => "stuff", "description" => "The stuff" }
      ]
    )
  end

  test "index shows all prompts" do
    get admin_prompt_templates_url
    assert_response :success
    assert_select "td", text: /Test Prompt/
  end

  test "edit shows prompt form" do
    get edit_admin_prompt_template_url(@template)
    assert_response :success
    assert_select "textarea", minimum: 2
  end

  test "update saves changes and creates version" do
    assert_difference "@template.versions.count", 1 do
      patch admin_prompt_template_url(@template), params: {
        prompt_template: {
          instructions: "Updated instructions for {{thing}}",
          editor_note: "Changed wording"
        }
      }
    end
    assert_redirected_to edit_admin_prompt_template_url(@template)
    @template.reload
    assert_equal "Updated instructions for {{thing}}", @template.instructions
  end

  test "update with no text change does not create version" do
    assert_no_difference "@template.versions.count" do
      patch admin_prompt_template_url(@template), params: {
        prompt_template: {
          name: "Renamed Prompt"
        }
      }
    end
  end

  test "diff returns version comparison" do
    @template.update!(instructions: "v2 instructions", editor_note: "v2")
    version = @template.versions.recent.last

    get diff_admin_prompt_template_url(@template, version_id: version.id)
    assert_response :success
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/admin/prompt_templates_controller_test.rb`
Expected: Routing error — controller doesn't exist

- [ ] **Step 3: Write controller**

```ruby
# app/controllers/admin/prompt_templates_controller.rb
class Admin::PromptTemplatesController < Admin::BaseController
  before_action :set_template, only: [:edit, :update, :diff]

  def index
    @templates = PromptTemplate.order(:name)
  end

  def edit
    @versions = @template.versions.recent.limit(20)
  end

  def update
    @template.editor_note = params[:prompt_template][:editor_note]

    if @template.update(template_params)
      redirect_to edit_admin_prompt_template_path(@template), notice: "Prompt updated."
    else
      @versions = @template.versions.recent.limit(20)
      render :edit, status: :unprocessable_entity
    end
  end

  def diff
    version = @template.versions.find(params[:version_id])
    current_text = @template.instructions || ""
    version_text = version.instructions || ""

    @diff = Diffy::Diff.new(version_text, current_text, context: 3)
    @version = version

    render partial: "version_diff", locals: { diff: @diff, version: version }
  end

  private

  def set_template
    @template = PromptTemplate.find(params[:id])
  end

  def template_params
    params.require(:prompt_template).permit(:system_role, :instructions, :model_tier)
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/controllers/admin/prompt_templates_controller_test.rb`
Expected: 5 tests, 0 failures (some may fail pending views — that's OK, views come in Task 10)

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/prompt_templates_controller.rb test/controllers/admin/prompt_templates_controller_test.rb
git commit -m "feat: add admin prompt templates controller with CRUD and diff"
```

---

## Task 9: Prompt Editor CSS

**Files:**
- Modify: `app/assets/stylesheets/application.css`

- [ ] **Step 1: Add prompt editor styles**

Add to the end of `application.css` (before any closing comments):

```css
/* === Prompt Editor === */

.form-textarea--code {
  font-family: var(--font-data);
  font-size: var(--text-sm);
  line-height: 1.6;
  letter-spacing: 0;
  text-transform: none;
  background: #f8fafa;
  resize: vertical;
  tab-size: 2;
}

.placeholder-ref {
  margin-top: var(--space-2);
}

.placeholder-toggle {
  font-family: var(--font-data);
  font-size: var(--text-xs);
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--color-text-muted);
  background: none;
  border: none;
  cursor: pointer;
  padding: var(--space-1) 0;
  display: flex;
  align-items: center;
  gap: var(--space-2);
}

.placeholder-toggle:hover {
  color: var(--color-text-secondary);
}

.placeholder-toggle svg {
  width: 12px;
  height: 12px;
  transition: transform var(--transition-fast);
}

.placeholder-toggle[aria-expanded="true"] svg {
  transform: rotate(90deg);
}

.placeholder-list {
  display: none;
  margin-top: var(--space-2);
  padding: var(--space-3) var(--space-4);
  background: var(--color-surface-raised, #e4eaea);
  border-radius: var(--radius-sm);
}

.placeholder-list.visible {
  display: block;
}

.placeholder-item {
  font-family: var(--font-data);
  font-size: var(--text-xs);
  color: var(--color-text-secondary);
  padding: var(--space-1) 0;
  display: flex;
  gap: var(--space-3);
  letter-spacing: 0;
  text-transform: none;
}

.placeholder-item code {
  color: var(--color-primary, #004a59);
  font-weight: 500;
  white-space: nowrap;
}

/* === Diff View === */

.diff-container {
  padding: var(--space-4);
  background: #f8fafa;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  font-family: var(--font-data);
  font-size: var(--text-xs);
  line-height: 1.8;
  letter-spacing: 0;
  text-transform: none;
  overflow-x: auto;
}

.diff-line {
  padding: 1px var(--space-2);
  white-space: pre-wrap;
}

.diff-add {
  background: var(--color-success-light, #dcecea);
  color: var(--color-success, #2a7a4a);
}

.diff-remove {
  background: var(--color-danger-light, #fce8e8);
  color: var(--color-danger, #9e2a2a);
  text-decoration: line-through;
  opacity: 0.8;
}

.diff-context {
  color: var(--color-text-muted);
}

.diff-header {
  color: var(--color-text-secondary);
  font-weight: 500;
  margin-bottom: var(--space-2);
}

/* === Tab Bar === */

.tab-bar {
  display: flex;
  gap: 0;
  border-bottom: 1px solid var(--color-border);
  margin-bottom: var(--space-6);
}

.tab-bar .tab {
  font-family: var(--font-body);
  font-weight: 500;
  font-size: var(--text-sm);
  color: var(--color-text-secondary);
  padding: var(--space-3) var(--space-4);
  border: none;
  background: none;
  cursor: pointer;
  border-bottom: 2px solid transparent;
  margin-bottom: -1px;
  transition: color var(--transition-fast), border-color var(--transition-fast);
}

.tab-bar .tab:hover {
  color: var(--color-text);
}

.tab-bar .tab.active {
  color: var(--color-primary, #004a59);
  border-bottom-color: var(--color-primary, #004a59);
}

/* === Job Run Console === */

.job-type-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
  gap: var(--space-4);
}

.job-type-card {
  padding: var(--space-4);
  border: 2px solid var(--color-border);
  border-radius: var(--radius-lg);
  cursor: pointer;
  transition: border-color var(--transition-fast), background var(--transition-fast);
}

.job-type-card:hover {
  border-color: var(--color-primary, #004a59);
  background: var(--color-primary-light, #e0f0f4);
}

.job-type-card.selected {
  border-color: var(--color-primary, #004a59);
  background: var(--color-primary-light, #e0f0f4);
}

.job-type-card-name {
  font-family: var(--font-body);
  font-weight: 600;
  font-size: var(--text-sm);
  color: var(--color-text);
  margin-bottom: var(--space-1);
}

.job-type-card-desc {
  font-size: var(--text-xs);
  color: var(--color-text-secondary);
}

.job-category-label {
  font-family: var(--font-data);
  font-size: var(--text-xs);
  font-weight: 500;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--color-text-muted);
  margin-bottom: var(--space-3);
  margin-top: var(--space-6);
}

.job-category-label:first-child {
  margin-top: 0;
}

.target-preview {
  font-family: var(--font-data);
  font-size: var(--text-sm);
  color: var(--color-text-secondary);
  padding: var(--space-3) var(--space-4);
  background: var(--color-surface-raised, #e4eaea);
  border-radius: var(--radius-md);
  margin-top: var(--space-3);
}
```

- [ ] **Step 2: Commit**

```bash
git add app/assets/stylesheets/application.css
git commit -m "feat: add CSS for prompt editor, diff view, tabs, and job run console"
```

---

## Task 10: Prompt Editor Views

**Files:**
- Create: `app/views/admin/prompt_templates/index.html.erb`
- Create: `app/views/admin/prompt_templates/edit.html.erb`
- Create: `app/views/admin/prompt_templates/_version_diff.html.erb`

- [ ] **Step 1: Write the index view**

```erb
<%# app/views/admin/prompt_templates/index.html.erb %>

<div class="page-header">
  <div class="section-header">
    <svg class="atom-marker" viewBox="0 0 100 100" width="20" height="20">
      <ellipse cx="50" cy="50" rx="38" ry="12" transform="rotate(-30, 50, 50)" fill="none" stroke="currentColor" stroke-width="1.5" opacity="0.4"/>
      <ellipse cx="50" cy="50" rx="38" ry="12" transform="rotate(30, 50, 50)" fill="none" stroke="currentColor" stroke-width="1.5" opacity="0.4"/>
      <ellipse cx="50" cy="50" rx="38" ry="12" transform="rotate(90, 50, 50)" fill="none" stroke="currentColor" stroke-width="1.5" opacity="0.4"/>
      <circle cx="50" cy="50" r="5" fill="currentColor"/>
    </svg>
    <span class="section-header-label">Prompt Templates</span>
    <div class="section-header-line"></div>
  </div>
  <p class="page-subtitle">Edit the AI prompts that drive topic extraction, summarization, and analysis.</p>
</div>

<div class="table-wrapper">
  <table>
    <thead>
      <tr>
        <th>Prompt</th>
        <th>Model</th>
        <th>Last Edited</th>
        <th></th>
      </tr>
    </thead>
    <tbody>
      <% @templates.each do |template| %>
        <tr>
          <td>
            <%= link_to template.name, edit_admin_prompt_template_path(template), class: "table-name" %>
            <% if template.description.present? %>
              <div class="table-desc"><%= template.description %></div>
            <% end %>
          </td>
          <td>
            <span class="chip <%= template.model_tier == 'lightweight' ? 'chip--amber' : 'chip--teal' %>">
              <%= template.model_tier.capitalize %>
            </span>
          </td>
          <td>
            <span class="timestamp"><%= time_ago_in_words(template.updated_at) %> ago</span>
          </td>
          <td>
            <%= link_to "Edit", edit_admin_prompt_template_path(template), class: "btn btn--ghost btn--sm" %>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
</div>
```

- [ ] **Step 2: Write the edit view**

```erb
<%# app/views/admin/prompt_templates/edit.html.erb %>

<div class="breadcrumb">
  <%= link_to "Prompt Templates", admin_prompt_templates_path %> &rsaquo;
  <span><%= @template.name %></span>
</div>

<div class="page-header">
  <div class="page-header-row">
    <div>
      <h1 class="page-title" style="margin-bottom: var(--space-2);"><%= @template.name %></h1>
      <p class="page-subtitle"><%= @template.description %></p>
    </div>
  </div>
</div>

<div class="tab-bar" data-controller="prompt-editor">
  <button class="tab active" data-action="click->prompt-editor#showTab" data-prompt-editor-tab-param="editor">Editor</button>
  <button class="tab" data-action="click->prompt-editor#showTab" data-prompt-editor-tab-param="history">Version History</button>
</div>

<div id="tab-editor" data-prompt-editor-target="panel" data-tab="editor">
  <div class="card">
    <div class="card-body">
      <%= form_with model: [:admin, @template], method: :patch, local: true do |form| %>
        <% if @template.errors.any? %>
          <div class="flash flash--danger mb-4">
            <%= @template.errors.full_messages.to_sentence %>
          </div>
        <% end %>

        <div class="form-group">
          <div class="flex items-center gap-4">
            <%= form.label :model_tier, "Model Tier", class: "form-label", style: "margin-bottom: 0;" %>
            <%= form.select :model_tier, [["Default (GPT-5.2)", "default"], ["Lightweight (GPT-5-mini)", "lightweight"]], {}, class: "form-select", style: "width: auto;" %>
          </div>
        </div>

        <div class="form-group">
          <%= form.label :system_role, "System Role", class: "form-label" %>
          <%= form.text_area :system_role, class: "form-textarea form-textarea--code", rows: 5 %>
          <% if @template.placeholders.present? %>
            <div class="placeholder-ref">
              <button type="button" class="placeholder-toggle" data-action="click->prompt-editor#togglePlaceholders" aria-expanded="false">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="12" height="12"><path d="M9 18l6-6-6-6"/></svg>
                Available placeholders
              </button>
              <div class="placeholder-list">
                <% @template.placeholders.each do |p| %>
                  <div class="placeholder-item">
                    <code>{{<%= p["name"] %>}}</code>
                    <%= p["description"] %>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>

        <div class="form-group">
          <%= form.label :instructions, "Instructions", class: "form-label" %>
          <%= form.text_area :instructions, class: "form-textarea form-textarea--code", rows: 25 %>
          <% if @template.placeholders.present? %>
            <div class="placeholder-ref">
              <button type="button" class="placeholder-toggle" data-action="click->prompt-editor#togglePlaceholders" aria-expanded="false">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="12" height="12"><path d="M9 18l6-6-6-6"/></svg>
                Available placeholders
              </button>
              <div class="placeholder-list">
                <% @template.placeholders.each do |p| %>
                  <div class="placeholder-item">
                    <code>{{<%= p["name"] %>}}</code>
                    <%= p["description"] %>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>

        <div class="form-group" style="margin-bottom: 0;">
          <label class="form-label">
            Edit note <span style="font-weight: 400; color: var(--color-text-muted);">(optional)</span>
          </label>
          <input type="text" name="prompt_template[editor_note]" class="form-input" placeholder="What did you change?" style="max-width: 500px;">
        </div>

        <div class="flex gap-2 items-center mt-6" style="padding-top: var(--space-4); border-top: 1px solid var(--color-border);">
          <%= form.submit "Save Changes", class: "btn btn--primary" %>
          <%= link_to "Cancel", admin_prompt_templates_path, class: "btn btn--ghost" %>
        </div>
      <% end %>
    </div>
  </div>
</div>

<div id="tab-history" data-prompt-editor-target="panel" data-tab="history" class="hidden">
  <div class="table-wrapper">
    <table>
      <thead>
        <tr>
          <th>Version</th>
          <th>Date</th>
          <th>Note</th>
          <th class="text-right">Actions</th>
        </tr>
      </thead>
      <tbody>
        <% @versions.each_with_index do |version, index| %>
          <tr>
            <td>
              <% if index == 0 %>
                <span class="badge badge--primary">Current</span>
              <% else %>
                <span class="timestamp">v<%= @versions.size - index %></span>
              <% end %>
            </td>
            <td><span class="timestamp"><%= version.created_at.strftime("%b %d, %Y · %l:%M %p") %></span></td>
            <td>
              <% if version.editor_note.present? %>
                <span><%= version.editor_note %></span>
              <% else %>
                <span style="color: var(--color-text-muted); font-style: italic;">No note</span>
              <% end %>
            </td>
            <td class="text-right">
              <% unless index == 0 %>
                <button class="btn btn--ghost btn--sm"
                        data-action="click->prompt-editor#loadDiff"
                        data-prompt-editor-url-param="<%= diff_admin_prompt_template_path(@template, version_id: version.id) %>"
                        data-prompt-editor-version-param="<%= version.id %>">
                  Diff
                </button>
                <button class="btn btn--ghost btn--sm"
                        data-action="click->prompt-editor#restore"
                        data-prompt-editor-system-role-param="<%= version.system_role %>"
                        data-prompt-editor-instructions-param="<%= version.instructions %>"
                        data-prompt-editor-model-tier-param="<%= version.model_tier %>">
                  Restore
                </button>
              <% end %>
            </td>
          </tr>
          <tr class="hidden" id="diff-row-<%= version.id %>">
            <td colspan="4" style="padding: 0;">
              <div id="diff-content-<%= version.id %>"></div>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>
</div>
```

- [ ] **Step 3: Write the diff partial**

```erb
<%# app/views/admin/prompt_templates/_version_diff.html.erb %>

<div class="diff-container">
  <div class="diff-header">Instructions — comparing to current</div>
  <% diff.each_chunk do |chunk| %>
    <% chunk.each_line do |line| %>
      <% css_class = case line[0]
        when '+' then 'diff-add'
        when '-' then 'diff-remove'
        else 'diff-context'
      end %>
      <div class="diff-line <%= css_class %>"><%= line.chomp %></div>
    <% end %>
  <% end %>
</div>
```

- [ ] **Step 4: Run controller tests**

Run: `bin/rails test test/controllers/admin/prompt_templates_controller_test.rb`
Expected: 5 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/views/admin/prompt_templates/
git commit -m "feat: add prompt editor views with index, edit, and diff"
```

---

## Task 11: Prompt Editor Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/prompt_editor_controller.js`

- [ ] **Step 1: Write the Stimulus controller**

```javascript
// app/javascript/controllers/prompt_editor_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel"]

  showTab(event) {
    const tabName = event.params.tab
    this.panelTargets.forEach(panel => {
      panel.classList.toggle("hidden", panel.dataset.tab !== tabName)
    })

    // Update tab button active states
    this.element.querySelectorAll(".tab").forEach(tab => {
      tab.classList.toggle("active", tab.dataset.promptEditorTabParam === tabName)
    })
  }

  togglePlaceholders(event) {
    const button = event.currentTarget
    const list = button.nextElementSibling
    const expanded = button.getAttribute("aria-expanded") === "true"

    button.setAttribute("aria-expanded", !expanded)
    list.classList.toggle("visible")
  }

  async loadDiff(event) {
    const url = event.params.url
    const versionId = event.params.version
    const diffRow = document.getElementById(`diff-row-${versionId}`)
    const diffContent = document.getElementById(`diff-content-${versionId}`)

    if (diffRow.classList.contains("hidden")) {
      const response = await fetch(url, {
        headers: { "Accept": "text/html" }
      })
      const html = await response.text()
      // Use Turbo morphing or safe DOM insertion
      const template = document.createElement("template")
      template.innerHTML = html
      diffContent.replaceChildren(template.content)
      diffRow.classList.remove("hidden")
    } else {
      diffRow.classList.add("hidden")
    }
  }

  restore(event) {
    const systemRole = event.params.systemRole
    const instructions = event.params.instructions
    const modelTier = event.params.modelTier

    const systemRoleField = document.querySelector("textarea[name='prompt_template[system_role]']")
    const instructionsField = document.querySelector("textarea[name='prompt_template[instructions]']")
    const modelTierField = document.querySelector("select[name='prompt_template[model_tier]']")

    if (systemRoleField) systemRoleField.value = systemRole || ""
    if (instructionsField) instructionsField.value = instructions || ""
    if (modelTierField) modelTierField.value = modelTier || "default"

    // Switch to editor tab
    this.showTab({ params: { tab: "editor" } })

    // Scroll to top of form
    if (systemRoleField) systemRoleField.scrollIntoView({ behavior: "smooth", block: "start" })
  }
}
```

- [ ] **Step 2: Verify auto-registration**

Check that the Stimulus controller is auto-discovered. The app uses importmap with `eagerLoadControllersFrom` in `app/javascript/controllers/index.js`, so placing the file at `app/javascript/controllers/prompt_editor_controller.js` should auto-register it as `prompt-editor`.

Run: `grep "eagerLoadControllersFrom" app/javascript/controllers/index.js`
Expected: Confirms auto-loading is in place.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/prompt_editor_controller.js
git commit -m "feat: add Stimulus controller for prompt editor tabs, diffs, and restore"
```

---

## Task 12: Job Runs Controller

**Files:**
- Create: `app/controllers/admin/job_runs_controller.rb`
- Create: `test/controllers/admin/job_runs_controller_test.rb`

- [ ] **Step 1: Write controller test**

```ruby
# test/controllers/admin/job_runs_controller_test.rb
require "test_helper"

class Admin::JobRunsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(
      email_address: "jobrun-admin@example.com",
      password: "password123456",
      admin: true,
      totp_enabled: true
    )
    @admin.ensure_totp_secret!

    post session_url, params: {
      email_address: @admin.email_address,
      password: "password123456"
    }
    post mfa_session_url, params: {
      code: ROTP::TOTP.new(@admin.totp_secret).now
    }

    @meeting = Meeting.create!(
      title: "Test Meeting",
      date: Date.new(2026, 3, 1),
      body_name: "City Council",
      source_url: "https://example.com/meeting"
    )
  end

  test "index shows job run console" do
    get admin_job_runs_url
    assert_response :success
    assert_select ".job-type-grid"
  end

  test "create enqueues meeting-scoped jobs" do
    assert_enqueued_with(job: ExtractTopicsJob, args: [@meeting.id]) do
      post admin_job_runs_url, params: {
        job_type: "extract_topics",
        date_from: "2026-03-01",
        date_to: "2026-03-31"
      }
    end
    assert_redirected_to admin_job_runs_url
    assert_match(/enqueued/i, flash[:notice])
  end

  test "create enqueues scraper job" do
    assert_enqueued_with(job: Scrapers::DiscoverMeetingsJob) do
      post admin_job_runs_url, params: {
        job_type: "discover_meetings"
      }
    end
    assert_redirected_to admin_job_runs_url
  end

  test "count returns target count for meeting-scoped jobs" do
    get count_admin_job_runs_url, params: {
      job_type: "extract_topics",
      date_from: "2026-03-01",
      date_to: "2026-03-31"
    }, as: :json
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 1, json["count"]
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/admin/job_runs_controller_test.rb`
Expected: Routing error or controller not found

- [ ] **Step 3: Write controller**

```ruby
# app/controllers/admin/job_runs_controller.rb
class Admin::JobRunsController < Admin::BaseController
  JOB_TYPES = {
    # Meeting-scoped
    "extract_topics" => { job: ExtractTopicsJob, scope: :meeting, name: "Extract Topics" },
    "extract_votes" => { job: ExtractVotesJob, scope: :meeting, name: "Extract Votes" },
    "extract_committee_members" => { job: ExtractCommitteeMembersJob, scope: :meeting, name: "Extract Committee Members" },
    "summarize_meeting" => { job: SummarizeMeetingJob, scope: :meeting, name: "Summarize Meeting" },
    # Topic-scoped
    "generate_topic_briefing" => { job: Topics::GenerateTopicBriefingJob, scope: :topic, name: "Topic Briefing" },
    "generate_description" => { job: Topics::GenerateDescriptionJob, scope: :topic, name: "Topic Description" },
    # No-target
    "auto_triage" => { job: Topics::AutoTriageJob, scope: :none, name: "Topic Triage" },
    "discover_meetings" => { job: Scrapers::DiscoverMeetingsJob, scope: :none, name: "Scrape City Website" }
  }.freeze

  def index
    @job_types = JOB_TYPES
    @committees = Committee.active.order(:name)
  end

  def create
    job_type = params[:job_type]
    config = JOB_TYPES[job_type]

    unless config
      redirect_to admin_job_runs_path, alert: "Unknown job type."
      return
    end

    targets = resolve_targets(config, params)
    enqueue_jobs(config, targets)

    count_text = targets ? "#{targets.size} #{config[:name]}" : "1 #{config[:name]}"
    redirect_to admin_job_runs_path, notice: "Enqueued #{count_text} job(s)."
  end

  def count
    config = JOB_TYPES[params[:job_type]]
    return render json: { count: 0 } unless config

    targets = resolve_targets(config, params)
    render json: { count: targets&.size || 1 }
  end

  private

  def resolve_targets(config, params)
    case config[:scope]
    when :meeting
      scope = Meeting.all
      scope = scope.where(date: params[:date_from]..params[:date_to]) if params[:date_from].present? && params[:date_to].present?
      scope = scope.where(committee_id: params[:committee_id]) if params[:committee_id].present?
      scope.to_a
    when :topic
      if params[:topic_ids].present?
        Topic.where(id: params[:topic_ids]).to_a
      else
        Topic.approved.to_a
      end
    when :none
      nil
    end
  end

  def enqueue_jobs(config, targets)
    case config[:scope]
    when :meeting
      targets.each { |meeting| config[:job].perform_later(meeting.id) }
    when :topic
      if config[:job] == Topics::GenerateTopicBriefingJob
        targets.each do |topic|
          latest_meeting_id = topic.meetings.order(date: :desc).pick(:id)
          config[:job].perform_later(topic_id: topic.id, meeting_id: latest_meeting_id) if latest_meeting_id
        end
      else
        targets.each { |topic| config[:job].perform_later(topic.id) }
      end
    when :none
      config[:job].perform_later
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/controllers/admin/job_runs_controller_test.rb`
Expected: 4 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/job_runs_controller.rb test/controllers/admin/job_runs_controller_test.rb
git commit -m "feat: add job runs controller with target resolution and enqueuing"
```

---

## Task 13: Job Run Console View

**Files:**
- Create: `app/views/admin/job_runs/index.html.erb`

- [ ] **Step 1: Write the index view**

```erb
<%# app/views/admin/job_runs/index.html.erb %>

<div class="page-header">
  <div class="section-header">
    <svg class="atom-marker" viewBox="0 0 100 100" width="20" height="20">
      <ellipse cx="50" cy="50" rx="38" ry="12" transform="rotate(-30, 50, 50)" fill="none" stroke="currentColor" stroke-width="1.5" opacity="0.4"/>
      <ellipse cx="50" cy="50" rx="38" ry="12" transform="rotate(30, 50, 50)" fill="none" stroke="currentColor" stroke-width="1.5" opacity="0.4"/>
      <ellipse cx="50" cy="50" rx="38" ry="12" transform="rotate(90, 50, 50)" fill="none" stroke="currentColor" stroke-width="1.5" opacity="0.4"/>
      <circle cx="50" cy="50" r="5" fill="currentColor"/>
    </svg>
    <span class="section-header-label">Job Re-Run Console</span>
    <div class="section-header-line"></div>
  </div>
  <p class="page-subtitle">Select a job type and targets, then enqueue.</p>
</div>

<%= form_with url: admin_job_runs_path, method: :post, local: true, data: { controller: "job-run" } do |form| %>
  <div class="card mb-6">
    <div class="card-body">
      <h2 class="card-title mb-4">1. Select Job Type</h2>

      <div class="job-category-label">Extraction</div>
      <div class="job-type-grid mb-4">
        <label class="job-type-card" data-action="click->job-run#selectType" data-job-run-scope-param="meeting">
          <input type="radio" name="job_type" value="extract_topics" class="hidden" data-job-run-target="typeRadio">
          <div class="job-type-card-name">Extract Topics</div>
          <div class="job-type-card-desc">Classify agenda items into civic topics</div>
        </label>
        <label class="job-type-card" data-action="click->job-run#selectType" data-job-run-scope-param="meeting">
          <input type="radio" name="job_type" value="extract_votes" class="hidden" data-job-run-target="typeRadio">
          <div class="job-type-card-name">Extract Votes</div>
          <div class="job-type-card-desc">Extract motions and vote records from minutes</div>
        </label>
        <label class="job-type-card" data-action="click->job-run#selectType" data-job-run-scope-param="meeting">
          <input type="radio" name="job_type" value="extract_committee_members" class="hidden" data-job-run-target="typeRadio">
          <div class="job-type-card-name">Extract Members</div>
          <div class="job-type-card-desc">Extract roll call and attendance from minutes</div>
        </label>
      </div>

      <div class="job-category-label">Summarization</div>
      <div class="job-type-grid mb-4">
        <label class="job-type-card" data-action="click->job-run#selectType" data-job-run-scope-param="meeting">
          <input type="radio" name="job_type" value="summarize_meeting" class="hidden" data-job-run-target="typeRadio">
          <div class="job-type-card-name">Summarize Meeting</div>
          <div class="job-type-card-desc">Generate structured meeting summary</div>
        </label>
        <label class="job-type-card" data-action="click->job-run#selectType" data-job-run-scope-param="topic">
          <input type="radio" name="job_type" value="generate_topic_briefing" class="hidden" data-job-run-target="typeRadio">
          <div class="job-type-card-name">Topic Briefing</div>
          <div class="job-type-card-desc">Generate rolling topic briefing</div>
        </label>
        <label class="job-type-card" data-action="click->job-run#selectType" data-job-run-scope-param="topic">
          <input type="radio" name="job_type" value="generate_description" class="hidden" data-job-run-target="typeRadio">
          <div class="job-type-card-name">Topic Description</div>
          <div class="job-type-card-desc">Generate short scope descriptions</div>
        </label>
      </div>

      <div class="job-category-label">Other</div>
      <div class="job-type-grid">
        <label class="job-type-card" data-action="click->job-run#selectType" data-job-run-scope-param="none">
          <input type="radio" name="job_type" value="auto_triage" class="hidden" data-job-run-target="typeRadio">
          <div class="job-type-card-name">Topic Triage</div>
          <div class="job-type-card-desc">Run auto-approval on proposed topics</div>
        </label>
        <label class="job-type-card" data-action="click->job-run#selectType" data-job-run-scope-param="none">
          <input type="radio" name="job_type" value="discover_meetings" class="hidden" data-job-run-target="typeRadio">
          <div class="job-type-card-name">Scrape City Website</div>
          <div class="job-type-card-desc">Check for new meetings and documents</div>
        </label>
      </div>
    </div>
  </div>

  <div class="card mb-6 hidden" data-job-run-target="meetingTargets">
    <div class="card-body">
      <h2 class="card-title mb-4">2. Select Meetings</h2>
      <div class="flex gap-4 flex-wrap">
        <div class="form-group grow">
          <label class="form-label">From</label>
          <input type="date" name="date_from" class="form-input" data-job-run-target="dateFrom" data-action="change->job-run#updateCount">
        </div>
        <div class="form-group grow">
          <label class="form-label">To</label>
          <input type="date" name="date_to" class="form-input" data-job-run-target="dateTo" data-action="change->job-run#updateCount">
        </div>
        <div class="form-group grow">
          <label class="form-label">Committee (optional)</label>
          <select name="committee_id" class="form-select" data-job-run-target="committeeFilter" data-action="change->job-run#updateCount">
            <option value="">All committees</option>
            <% @committees.each do |committee| %>
              <option value="<%= committee.id %>"><%= committee.name %></option>
            <% end %>
          </select>
        </div>
      </div>
      <div class="target-preview" data-job-run-target="countPreview">
        Select a date range to see matching meetings.
      </div>
    </div>
  </div>

  <div class="card mb-6 hidden" data-job-run-target="topicTargets">
    <div class="card-body">
      <h2 class="card-title mb-4">2. Select Topics</h2>
      <div class="form-group">
        <label class="flex items-center gap-2" style="cursor: pointer;">
          <input type="checkbox" name="all_topics" value="1" data-action="change->job-run#toggleAllTopics" data-job-run-target="allTopics">
          <span>All approved topics (<%= Topic.approved.count %>)</span>
        </label>
      </div>
      <div class="form-group" data-job-run-target="topicSelect">
        <label class="form-label">Or select specific topics:</label>
        <select name="topic_ids[]" multiple class="form-select" size="8">
          <% Topic.approved.order(:name).each do |topic| %>
            <option value="<%= topic.id %>"><%= topic.name %></option>
          <% end %>
        </select>
        <p class="form-hint">Hold Ctrl/Cmd to select multiple topics.</p>
      </div>
    </div>
  </div>

  <div class="card">
    <div class="card-body">
      <button type="submit" class="btn btn--primary">
        Enqueue Jobs
      </button>
    </div>
  </div>
<% end %>
```

- [ ] **Step 2: Run controller tests to verify views render**

Run: `bin/rails test test/controllers/admin/job_runs_controller_test.rb`
Expected: All pass

- [ ] **Step 3: Commit**

```bash
git add app/views/admin/job_runs/
git commit -m "feat: add job re-run console view with target selection"
```

---

## Task 14: Job Run Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/job_run_controller.js`

- [ ] **Step 1: Write the Stimulus controller**

```javascript
// app/javascript/controllers/job_run_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "typeRadio", "meetingTargets", "topicTargets",
    "dateFrom", "dateTo", "committeeFilter",
    "countPreview", "allTopics", "topicSelect"
  ]

  selectType(event) {
    const scope = event.params.scope
    const card = event.currentTarget

    // Update visual selection
    this.element.querySelectorAll(".job-type-card").forEach(c => c.classList.remove("selected"))
    card.classList.add("selected")

    // Check the radio
    const radio = card.querySelector("input[type=radio]")
    if (radio) radio.checked = true

    // Show/hide target sections
    this.meetingTargetsTarget.classList.toggle("hidden", scope !== "meeting")
    this.topicTargetsTarget.classList.toggle("hidden", scope !== "topic")
  }

  async updateCount() {
    const jobType = this.element.querySelector("input[name='job_type']:checked")?.value
    const dateFrom = this.dateFromTarget.value
    const dateTo = this.dateToTarget.value

    if (!jobType || !dateFrom || !dateTo) {
      this.countPreviewTarget.textContent = "Select a date range to see matching meetings."
      return
    }

    const params = new URLSearchParams({
      job_type: jobType,
      date_from: dateFrom,
      date_to: dateTo
    })

    const committeeId = this.committeeFilterTarget.value
    if (committeeId) params.append("committee_id", committeeId)

    try {
      const response = await fetch(`/admin/job_runs/count?${params}`, {
        headers: { "Accept": "application/json" }
      })
      const data = await response.json()
      this.countPreviewTarget.textContent = `${data.count} meeting(s) in range.`
    } catch {
      this.countPreviewTarget.textContent = "Unable to fetch count."
    }
  }

  toggleAllTopics() {
    const checked = this.allTopicsTarget.checked
    this.topicSelectTarget.classList.toggle("hidden", checked)
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/javascript/controllers/job_run_controller.js
git commit -m "feat: add Stimulus controller for job run console interaction"
```

---

## Task 15: Wire OpenAiService to PromptTemplate

**Files:**
- Modify: `app/services/ai/open_ai_service.rb`
- Create: `test/services/ai/open_ai_service_prompt_template_test.rb`

- [ ] **Step 1: Write integration test**

```ruby
# test/services/ai/open_ai_service_prompt_template_test.rb
require "test_helper"

class Ai::OpenAiServicePromptTemplateTest < ActiveSupport::TestCase
  test "PromptTemplate.interpolate replaces all placeholders" do
    template = PromptTemplate.new(
      instructions: "Extract votes from:\n{{text}}\nReturn json."
    )
    result = template.interpolate(text: "The motion passed 5-2.")
    assert_equal "Extract votes from:\nThe motion passed 5-2.\nReturn json.", result
  end

  test "PromptTemplate.interpolate_system_role works for system messages" do
    template = PromptTemplate.new(
      system_role: "You are a {{role}} for {{city}}."
    )
    result = template.interpolate_system_role(role: "civic journalist", city: "Two Rivers, WI")
    assert_equal "You are a civic journalist for Two Rivers, WI.", result
  end

  test "load_template returns nil for missing key" do
    service = Ai::OpenAiService.new
    template = PromptTemplate.find_by(key: "nonexistent_key")
    assert_nil template
  end
end
```

- [ ] **Step 2: Run test**

Run: `bin/rails test test/services/ai/open_ai_service_prompt_template_test.rb`
Expected: 3 tests pass

- [ ] **Step 3: Add `load_template` helper to OpenAiService**

In `app/services/ai/open_ai_service.rb`, add this method in the private section (after `prepare_committee_context`, before `gemini_api_key`):

```ruby
def load_template(key)
  template = PromptTemplate.find_by(key: key)
  return nil if template.nil? || template.instructions.include?("TODO")
  template
rescue => e
  Rails.logger.warn("Failed to load prompt template '#{key}': #{e.message}")
  nil
end
```

- [ ] **Step 4: Convert `extract_votes` method as the first example**

In the `extract_votes` method (~lines 36-81), wrap the existing logic with a template check. The pattern is:

```ruby
def extract_votes(text)
  template = load_template("extract_votes")

  if template
    system_role = template.system_role
    prompt = template.interpolate(text: text.truncate(50000))
    model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL
  else
    # === ORIGINAL HEREDOC (unchanged) ===
    system_role = nil
    prompt = <<~PROMPT
      # ... existing heredoc text stays exactly as-is ...
    PROMPT
    model = DEFAULT_MODEL
  end

  response = @client.chat(
    parameters: {
      model: model,
      messages: [
        (system_role.present? ? { role: "system", content: system_role } : nil),
        { role: "user", content: prompt }
      ].compact,
      response_format: { type: "json_object" },
      temperature: 0.1
    }
  )

  JSON.parse(response.dig("choices", 0, "message", "content"))
end
```

The key change: the existing `@client.chat(...)` call at the bottom of the method now uses the template-loaded values when available, or the original heredoc as fallback.

- [ ] **Step 5: Apply the same pattern to all remaining 14 methods**

Each method follows the same conversion pattern:
1. Add `template = load_template("key")` at the top
2. Wrap the heredoc in an `if template ... else ... end`
3. In the `if` branch, use `template.interpolate(...)` and `template.interpolate_system_role(...)`
4. In the `else` branch, keep the original heredoc exactly as-is
5. The `@client.chat(...)` call at the bottom uses the loaded values

Key per-method notes:

**`extract_committee_members`** — No temperature param. Don't add one in the template path.

**`extract_topics`** — Has 4 placeholders: `items_text`, `community_context`, `existing_topics` (format as newline-separated list), `meeting_documents_context`.

**`refine_catchall_topic` / `re_extract_item_topics`** — Take keyword args. Map each to a placeholder.

**`triage_topics`** — May use Gemini model. Template path should still respect `use_gemini?` check.

**`analyze_topic_summary` / `analyze_topic_briefing` / `analyze_meeting_content`** — Have separate `system_role` heredocs. Use `template.interpolate_system_role(committee_context: prepare_committee_context)`.

**`render_topic_summary` / `render_topic_briefing`** — Have separate system_role strings. Map to template `system_role` field.

**`generate_briefing_interim`** — Uses LIGHTWEIGHT_MODEL, no temperature.

**`generate_topic_description`** — Has conditional branch. Use two template keys:
```ruby
key = agenda_items.size >= 3 ? "generate_topic_description_detailed" : "generate_topic_description_broad"
template = load_template(key)
```

**`render_meeting_summary`** — Legacy method. Convert normally.

- [ ] **Step 6: Run full test suite**

Run: `bin/rails test`
Expected: All tests pass. The fallback heredocs ensure nothing breaks.

- [ ] **Step 7: Commit**

```bash
git add app/services/ai/open_ai_service.rb test/services/ai/open_ai_service_prompt_template_test.rb
git commit -m "feat: wire OpenAiService to load prompts from PromptTemplate with fallback"
```

---

## Task 16: Populate Prompts via Admin UI

This is a manual step — copy each heredoc from `open_ai_service.rb` into the admin UI.

- [ ] **Step 1: Start the dev server**

Run: `bin/dev`

- [ ] **Step 2: Populate each prompt**

Visit `/admin/prompt_templates`. For each of the 15 prompts:

1. Click "Edit"
2. Open `app/services/ai/open_ai_service.rb` in your editor
3. Find the corresponding method
4. Copy the system_role text (if any) into the "System Role" field
5. Copy the instructions heredoc into the "Instructions" field
6. Replace Ruby interpolations (like `#{text.truncate(50000)}`) with `{{text}}`
7. Replace `#{prepare_committee_context}` with `{{committee_context}}`
8. Replace `#{existing_topics_list}` with `{{existing_topics}}`
9. Set the model tier dropdown to match the original method
10. Add edit note: "Populated from OpenAiService heredoc"
11. Save

- [ ] **Step 3: Validate all prompts populated**

Run: `bin/rails prompt_templates:validate`
Expected: "All 15 prompt templates present with real content."

- [ ] **Step 4: Run full test suite**

Run: `bin/rails test`
Expected: All tests pass

---

## Task 17: Update Documentation

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add to Commands table**

```markdown
| Validate prompt templates | `bin/rails prompt_templates:validate` |
```

- [ ] **Step 2: Add to Core Domain Models**

After the `TopicBriefing` entry:

```markdown
- **`PromptTemplate`** — Stores AI prompt text (system_role + instructions) with `{{placeholder}}` interpolation. 15 fixed templates (seeded), editable via admin UI. Auto-versions on save via `PromptVersion`.
```

- [ ] **Step 3: Update Key Services**

In the `Ai::OpenAiService` entry, append:

```markdown
Prompts loaded from `PromptTemplate` (database) with fallback to hardcoded heredocs.
```

- [ ] **Step 4: Update Routes**

In the Admin routes line:

```markdown
Admin: ... `/admin/prompt_templates` (edit AI prompts), `/admin/job_runs` (re-run pipeline jobs with targeting)
```

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add prompt management and job re-run console to CLAUDE.md"
```

---

## Task 18: Lint and Final Verification

- [ ] **Step 1: Run RuboCop**

Run: `bin/rubocop`
Fix any style violations in new files.

- [ ] **Step 2: Run Brakeman**

Run: `bin/brakeman --no-pager`
Expected: No new security warnings. Admin controllers inherit `require_admin` and `require_admin_mfa`.

- [ ] **Step 3: Run full CI**

Run: `bin/ci`
Expected: All checks pass.

- [ ] **Step 4: Run full test suite**

Run: `bin/rails test`
Expected: All tests pass.

- [ ] **Step 5: Commit any lint fixes**

```bash
git add -A
git commit -m "fix: lint and style fixes for prompt management feature"
```
