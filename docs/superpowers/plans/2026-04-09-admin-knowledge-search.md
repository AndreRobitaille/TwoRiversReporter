# Admin Knowledge Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an admin-only RAG search page at `/admin/search` that queries the knowledge base via vector similarity, searches meeting documents via full-text search, and optionally synthesizes AI answers with traceable citations.

**Architecture:** Single controller (`Admin::SearchesController`) with one `index` action. KB results via `RetrievalService`, document results via `MeetingDocument.search` scope, AI synthesis via new `OpenAiService#answer_question` method using gpt-5.2. Also upgrades `LIGHTWEIGHT_MODEL` to `gpt-5.4-mini` and adds `meeting_id` FK to `KnowledgeSource`.

**Tech Stack:** Rails 8.1, PostgreSQL full-text search, pgvector embeddings, OpenAI gpt-5.2

**Spec:** `docs/superpowers/specs/2026-04-09-admin-knowledge-search-design.md`

---

### Task 1: Upgrade LIGHTWEIGHT_MODEL to gpt-5.4-mini

**Files:**
- Modify: `app/services/ai/open_ai_service.rb:6`
- Modify: `test/test_helper.rb:22` (bump guard count)

- [ ] **Step 1: Update the constant**

In `app/services/ai/open_ai_service.rb`, change line 6:

```ruby
# Old:
LIGHTWEIGHT_MODEL = ENV.fetch("OPENAI_LIGHTWEIGHT_MODEL", "gpt-5-mini")

# New:
LIGHTWEIGHT_MODEL = ENV.fetch("OPENAI_LIGHTWEIGHT_MODEL", "gpt-5.4-mini")
```

- [ ] **Step 2: Run existing tests to verify nothing breaks**

Run: `bin/rails test test/services/ai/`
Expected: All tests pass (they stub the client, so the model name doesn't affect test behavior).

- [ ] **Step 3: Commit**

```bash
git add app/services/ai/open_ai_service.rb
git commit -m "chore: upgrade LIGHTWEIGHT_MODEL from gpt-5-mini to gpt-5.4-mini"
```

---

### Task 2: Add meeting_id FK to KnowledgeSource

**Files:**
- Create: `db/migrate/TIMESTAMP_add_meeting_id_to_knowledge_sources.rb`
- Modify: `app/models/knowledge_source.rb`
- Modify: `app/models/meeting.rb`
- Modify: `app/jobs/extract_knowledge_job.rb:81`

- [ ] **Step 1: Generate the migration**

Run: `bin/rails generate migration AddMeetingIdToKnowledgeSources meeting:references`

- [ ] **Step 2: Edit the migration to make it optional (nullable)**

The generated migration will have `null: false` by default. Edit it to:

```ruby
class AddMeetingIdToKnowledgeSources < ActiveRecord::Migration[8.1]
  def change
    add_reference :knowledge_sources, :meeting, null: true, foreign_key: true
  end
end
```

- [ ] **Step 3: Run the migration**

Run: `bin/rails db:migrate`
Expected: Migration succeeds, `schema.rb` updated.

- [ ] **Step 4: Add the association to KnowledgeSource model**

In `app/models/knowledge_source.rb`, add after the existing associations (after line 7):

```ruby
belongs_to :meeting, optional: true
```

- [ ] **Step 5: Add the reverse association to Meeting model**

In `app/models/meeting.rb`, add after the existing `has_many` lines (after line 8):

```ruby
has_many :knowledge_sources, dependent: :nullify
```

- [ ] **Step 6: Update ExtractKnowledgeJob to populate meeting_id**

In `app/jobs/extract_knowledge_job.rb`, in the `create_knowledge_source` method (line 80), add `meeting_id:` to the create call:

```ruby
def create_knowledge_source(entry, meeting)
  KnowledgeSource.create!(
    title: entry["title"].to_s.truncate(255),
    body: entry["body"].to_s,
    source_type: "note",
    origin: "extracted",
    status: "proposed",
    active: true,
    reasoning: entry["reasoning"].to_s,
    confidence: entry["confidence"].to_f,
    stated_at: meeting.starts_at&.to_date,
    meeting: meeting
  )
end
```

- [ ] **Step 7: Run tests**

Run: `bin/rails test test/jobs/extract_knowledge_job_test.rb test/models/knowledge_source_test.rb`
Expected: All pass.

- [ ] **Step 8: Commit**

```bash
git add db/migrate/*_add_meeting_id_to_knowledge_sources.rb db/schema.rb app/models/knowledge_source.rb app/models/meeting.rb app/jobs/extract_knowledge_job.rb
git commit -m "feat: add meeting_id FK to knowledge_sources for source traceability"
```

---

### Task 3: Add knowledge_search_answer PromptTemplate

**Files:**
- Modify: `lib/prompt_template_data.rb` (add METADATA entry + PROMPTS entry)
- Modify: `db/seeds/prompt_templates.rb` (add seed data entry)
- Modify: `test/test_helper.rb:22` (bump guard count from 15 to 16)

- [ ] **Step 1: Add metadata entry to lib/prompt_template_data.rb**

In `lib/prompt_template_data.rb`, add this entry at the end of the `METADATA` array (before the `].freeze` on line 174):

```ruby
    {
      key: "knowledge_search_answer",
      name: "Knowledge Search Answer",
      description: "Synthesizes an answer to admin questions using knowledge base context",
      model_tier: "default",
      placeholders: [
        { "name" => "context", "description" => "Numbered knowledge base chunks with origin labels" },
        { "name" => "question", "description" => "The admin's search query" }
      ]
    }
```

- [ ] **Step 2: Add prompt text to PROMPTS hash**

In `lib/prompt_template_data.rb`, add this entry at the end of the `PROMPTS` hash (before the `}.freeze` on the last line):

```ruby
    "knowledge_search_answer" => {
      system_role: "You are a research assistant for a civic transparency project in Two Rivers, WI. Answer questions using only the provided knowledge base context. Cite sources by number in brackets (e.g. [1], [2]). If the context doesn't contain enough information to answer confidently, say so clearly. Be direct and specific.",
      instructions: <<~PROMPT.strip
        The following numbered entries come from the city knowledge base. Each entry has an origin label indicating its trust level:
        - [ADMIN NOTE]: Authoritative background context from site administrators.
        - [DOCUMENT-DERIVED]: Background context extracted from meeting documents.
        - [PATTERN-DERIVED]: System-identified pattern across meetings. Treat with appropriate skepticism.

        Dates in parentheses indicate when the fact was stated. Older facts may be outdated.

        {{context}}

        ---

        Question: {{question}}

        Answer the question based only on the context above. Cite each factual claim with the source number in [brackets]. If multiple sources support a claim, cite all of them. If the context doesn't contain enough information, say "I don't have enough information in the knowledge base to answer this confidently" and explain what's missing.
      PROMPT
    }
```

- [ ] **Step 3: Add seed data entry to db/seeds/prompt_templates.rb**

In `db/seeds/prompt_templates.rb`, add this entry at the end of the `PROMPT_TEMPLATES_DATA` array (before `].freeze`):

```ruby
  {
    key: "knowledge_search_answer",
    name: "Knowledge Search Answer",
    description: "Synthesizes an answer to admin questions using knowledge base context",
    usage_context: "Admin tool: on-demand Q&A over the knowledge base. Admin types a question, top-10 KB chunks are retrieved by vector similarity, and this prompt synthesizes a prose answer with numbered citations. Not part of the automated pipeline — triggered only by manual admin search",
    model_tier: "default",
    placeholders: [
      { "name" => "context", "description" => "Numbered knowledge base chunks with origin labels" },
      { "name" => "question", "description" => "The admin's search query" }
    ]
  }
```

- [ ] **Step 4: Bump the guard count in test_helper.rb**

In `test/test_helper.rb`, line 22, change:

```ruby
# Old:
return if PromptTemplate.count >= 15

# New:
return if PromptTemplate.count >= 16
```

- [ ] **Step 5: Run the populate task to verify the template loads**

Run: `bin/rails prompt_templates:validate`
Expected: No errors. The new template key should be recognized.

- [ ] **Step 6: Commit**

```bash
git add lib/prompt_template_data.rb db/seeds/prompt_templates.rb test/test_helper.rb
git commit -m "feat: add knowledge_search_answer prompt template"
```

---

### Task 4: Add OpenAiService#answer_question method

**Files:**
- Modify: `app/services/ai/open_ai_service.rb` (add method)
- Create: `test/services/ai/open_ai_service_answer_question_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/services/ai/open_ai_service_answer_question_test.rb`:

```ruby
require "test_helper"

class Ai::OpenAiServiceAnswerQuestionTest < ActiveSupport::TestCase
  setup do
    seed_prompt_templates
    @service = Ai::OpenAiService.new
  end

  test "answer_question returns answer text and uses DEFAULT_MODEL" do
    captured_params = nil
    mock_response = {
      "choices" => [ { "message" => { "content" => "Kay Koch served on Plan Commission for 38 years [1]." } } ]
    }

    client = @service.instance_variable_get(:@client)
    client.stub :chat, ->(parameters:) {
      captured_params = parameters
      mock_response
    } do
      answer = @service.answer_question(
        "Who served longest on Plan Commission?",
        [ "[1] [DOCUMENT-DERIVED: Plan Commission History (2025-11-15)]\nKay Koch served for 38 years." ],
        source: "admin_search"
      )

      assert_equal "Kay Koch served on Plan Commission for 38 years [1].", answer
      assert_equal Ai::OpenAiService::DEFAULT_MODEL, captured_params[:model]
      # Should NOT have temperature (reasoning model)
      assert_nil captured_params[:temperature]
    end
  end

  test "answer_question includes context and question in prompt" do
    captured_messages = nil
    mock_response = {
      "choices" => [ { "message" => { "content" => "Test answer." } } ]
    }

    client = @service.instance_variable_get(:@client)
    client.stub :chat, ->(parameters:) {
      captured_messages = parameters[:messages]
      mock_response
    } do
      @service.answer_question(
        "What about parks?",
        [ "[1] [ADMIN NOTE: Parks info]\nThe city has 12 parks." ],
        source: "admin_search"
      )

      user_message = captured_messages.find { |m| m[:role] == "user" }
      assert_includes user_message[:content], "What about parks?"
      assert_includes user_message[:content], "The city has 12 parks."
    end
  end

  test "answer_question records prompt run" do
    mock_response = {
      "choices" => [ { "message" => { "content" => "Answer." } } ]
    }

    client = @service.instance_variable_get(:@client)
    client.stub :chat, ->(**_) { mock_response } do
      assert_difference "PromptRun.count", 1 do
        @service.answer_question("Test?", [ "[1] Context." ], source: "admin_search")
      end
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/services/ai/open_ai_service_answer_question_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'answer_question'`

- [ ] **Step 3: Implement answer_question**

In `app/services/ai/open_ai_service.rb`, add this method after the `triage_knowledge` method (around line 740):

```ruby
    def answer_question(query, numbered_context, source: nil)
      template = PromptTemplate.find_by!(key: "knowledge_search_answer")
      system_role = template.system_role
      context_text = numbered_context.join("\n\n")
      placeholders = { context: context_text, question: query }
      prompt = template.interpolate(**placeholders)

      messages = [
        (system_role.present? ? { role: "system", content: system_role } : nil),
        { role: "user", content: prompt }
      ].compact

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = @client.chat(
        parameters: {
          model: DEFAULT_MODEL,
          messages: messages
        }
      )
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

      content = response.dig("choices", 0, "message", "content")

      record_prompt_run(
        template_key: "knowledge_search_answer",
        messages: messages,
        response_content: content,
        model: DEFAULT_MODEL,
        duration_ms: duration_ms,
        source: source,
        placeholder_values: placeholders.transform_keys(&:to_s)
      )

      content
    end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/services/ai/open_ai_service_answer_question_test.rb`
Expected: All 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/services/ai/open_ai_service.rb test/services/ai/open_ai_service_answer_question_test.rb
git commit -m "feat: add OpenAiService#answer_question for admin knowledge search"
```

---

### Task 5: Add route and controller

**Files:**
- Create: `app/controllers/admin/searches_controller.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Add the route**

In `config/routes.rb`, inside the `scope :admin` block, add after the `resources :job_runs` block (before the closing `end` of the scope):

```ruby
    resource :search, only: [ :index ], controller: "admin/searches", as: :admin_search
```

Note: `resource` (singular) gives `GET /admin/search` → `searches#index` without requiring an ID.

- [ ] **Step 2: Verify the route exists**

Run: `bin/rails routes | grep search`
Expected: Shows `admin_search GET /admin/search(.:format) admin/searches#index`

- [ ] **Step 3: Create the controller**

Create `app/controllers/admin/searches_controller.rb`:

```ruby
module Admin
  class SearchesController < BaseController
    def index
      @query = params[:q].to_s.strip
      return if @query.blank?

      @kb_results = retrieve_kb_results
      @document_results = retrieve_document_results

      if params[:ask_ai].present? && @kb_results.any?
        @numbered_context = build_numbered_context(@kb_results)
        @ai_answer = Ai::OpenAiService.new.answer_question(@query, @numbered_context, source: "admin_search")
      end
    end

    private

    def retrieve_kb_results
      RetrievalService.new.retrieve_context(@query, limit: 10)
    end

    def retrieve_document_results
      MeetingDocument.search(@query)
                     .includes(:meeting)
                     .select(
                       "meeting_documents.*",
                       "ts_headline('english', meeting_documents.extracted_text, websearch_to_tsquery('english', #{MeetingDocument.connection.quote(@query)}), 'MaxWords=35, MinWords=15, StartSel=<mark>, StopSel=</mark>') AS headline_excerpt"
                     )
                     .limit(10)
    end

    def build_numbered_context(results)
      results.each_with_index.map do |result, i|
        chunk = result[:chunk]
        source = chunk.knowledge_source
        label = source_label(source)
        "[#{i + 1}] #{label}\n#{chunk.content}"
      end
    end

    def source_label(source)
      date_suffix = source.stated_at ? " (#{source.stated_at})" : ""
      case source.origin
      when "manual"
        "[ADMIN NOTE: #{source.title}#{date_suffix}]"
      when "extracted"
        "[DOCUMENT-DERIVED: #{source.title}#{date_suffix}]"
      when "pattern"
        "[PATTERN-DERIVED: #{source.title}#{date_suffix}]"
      else
        "[#{source.title}#{date_suffix}]"
      end
    end
  end
end
```

- [ ] **Step 4: Run a quick smoke test**

Run: `bin/rails routes | grep search`
Expected: Route exists and maps correctly.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/admin/searches_controller.rb config/routes.rb
git commit -m "feat: add admin search controller and route"
```

---

### Task 6: Create the search view

**Files:**
- Create: `app/views/admin/searches/index.html.erb`
- Modify: `app/assets/stylesheets/application.css` (add `.card--ai-answer`)

- [ ] **Step 1: Add the CSS class**

In `app/assets/stylesheets/application.css`, add after the existing `.card` rules (around line 420, after the card block):

```css
.card--ai-answer {
  border-left: 3px solid var(--color-teal);
}
```

- [ ] **Step 2: Create the view**

Create `app/views/admin/searches/index.html.erb`:

```erb
<div class="page-header">
  <h1 class="page-title">Knowledge Search</h1>
  <p class="page-subtitle">Ask questions about your civic data</p>
</div>

<div class="card mb-6">
  <%= form_with url: admin_search_path, method: :get, local: true, class: "search-form" do |f| %>
    <input type="text" name="q" value="<%= @query %>" placeholder="Search knowledge base and meeting documents..." class="form-input" style="flex: 1; max-width: none;" autofocus>
    <button type="submit" class="btn btn--secondary">Search</button>
    <button type="submit" name="ask_ai" value="1" class="btn btn--primary">Ask AI</button>
  <% end %>
</div>

<% if @query.blank? %>
  <div class="card">
    <p class="section-empty">Enter a search to query the knowledge base and meeting documents.</p>
  </div>
<% else %>

  <%# AI Answer (conditional) %>
  <% if @ai_answer.present? %>
    <div class="card card--ai-answer mb-6">
      <div class="card-header">
        <span class="badge badge--info">AI Answer</span>
      </div>
      <div class="prose">
        <%= simple_format @ai_answer %>
      </div>
      <% if @kb_results.present? %>
        <div class="mt-4" style="border-top: 1px solid var(--color-border); padding-top: var(--space-4);">
          <div class="text-sm font-medium text-secondary mb-2">Sources</div>
          <ol class="text-sm" style="padding-left: var(--space-4); margin: 0;">
            <% @kb_results.each_with_index do |result, i| %>
              <% source = result[:chunk].knowledge_source %>
              <li style="margin-bottom: var(--space-1);">
                <%= link_to source.title, admin_knowledge_source_path(source) %>
                <span class="badge badge--<%= source.origin == 'manual' ? 'default' : (source.origin == 'extracted' ? 'info' : 'warning') %>" style="font-size: 0.65rem;"><%= source.origin %></span>
                <% if source.stated_at %>
                  <span class="text-muted" style="font-family: var(--font-data); font-size: 0.7rem;"><%= source.stated_at %></span>
                <% end %>
                <% if source.meeting %>
                  &middot; from <%= link_to source.meeting.body_name, meeting_path(source.meeting) %>
                <% end %>
              </li>
            <% end %>
          </ol>
        </div>
      <% end %>
      <div class="mt-4 text-sm text-muted">
        Based on <%= @kb_results.size %> knowledge sources &middot; gpt-5.2
      </div>
    </div>
  <% end %>

  <%# Knowledge Base Results %>
  <div class="card mb-6">
    <div class="card-header">
      <h2 class="card-title">Knowledge Base Results (<%= @kb_results&.size || 0 %>)</h2>
    </div>
    <% if @kb_results.blank? %>
      <p class="section-empty">No matching knowledge base entries found.</p>
    <% else %>
      <% @kb_results.each do |result| %>
        <% chunk = result[:chunk] %>
        <% source = chunk.knowledge_source %>
        <% score_pct = (result[:score] * 100).round %>
        <div style="padding: var(--space-3) 0; border-bottom: 1px solid var(--color-border);">
          <div class="flex items-center gap-2 mb-1">
            <span style="font-family: var(--font-data); font-size: 0.75rem; color: var(--color-text-muted); letter-spacing: 0.05em; min-width: 3em;"><%= score_pct %>%</span>
            <strong><%= link_to source.title, admin_knowledge_source_path(source) %></strong>
            <span class="badge badge--<%= source.origin == 'manual' ? 'default' : (source.origin == 'extracted' ? 'info' : 'warning') %>"><%= source.origin.humanize %></span>
            <% if source.stated_at %>
              <span style="font-family: var(--font-data); font-size: 0.7rem; color: var(--color-text-muted); text-transform: uppercase; letter-spacing: 0.05em;"><%= source.stated_at %></span>
            <% end %>
          </div>
          <p class="text-sm text-secondary" style="margin: 0;"><%= chunk.content.truncate(200) %></p>
        </div>
      <% end %>
    <% end %>
  </div>

  <%# Meeting Document Results %>
  <div class="card">
    <div class="card-header">
      <h2 class="card-title">Meeting Documents (<%= @document_results&.size || 0 %>)</h2>
    </div>
    <% if @document_results.blank? %>
      <p class="section-empty">No matching meeting documents found.</p>
    <% else %>
      <% @document_results.each do |doc| %>
        <div style="padding: var(--space-3) 0; border-bottom: 1px solid var(--color-border);">
          <div class="flex items-center gap-2 mb-1">
            <span class="badge badge--default"><%= doc.document_type.humanize.upcase %></span>
            <% if doc.meeting %>
              <strong><%= link_to doc.meeting.body_name, meeting_path(doc.meeting) %></strong>
              <span class="text-muted"><%= doc.meeting.starts_at&.strftime("%b %d, %Y") %></span>
            <% end %>
          </div>
          <% if doc.respond_to?(:headline_excerpt) && doc.headline_excerpt.present? %>
            <p class="text-sm text-secondary" style="margin: 0;"><%= raw doc.headline_excerpt %></p>
          <% else %>
            <p class="text-sm text-secondary" style="margin: 0;"><%= doc.extracted_text.to_s.truncate(200) %></p>
          <% end %>
        </div>
      <% end %>
    <% end %>
  </div>

<% end %>
```

- [ ] **Step 3: Verify the page renders**

Start the dev server (`bin/dev`) and visit `http://localhost:3000/admin/search` (after logging in).
Expected: The search form renders without errors.

- [ ] **Step 4: Commit**

```bash
git add app/views/admin/searches/index.html.erb app/assets/stylesheets/application.css
git commit -m "feat: add admin knowledge search view"
```

---

### Task 7: Add dashboard link

**Files:**
- Modify: `app/views/admin/dashboard/show.html.erb`

- [ ] **Step 1: Add the search link to the Content section**

In `app/views/admin/dashboard/show.html.erb`, in the Content `<ul>` (after line 12, after the "Knowledgebase Sources" link), add:

```erb
    <li><%= link_to "Knowledge Search", admin_search_path %></li>
```

- [ ] **Step 2: Verify the link appears**

Visit `http://localhost:3000/admin` and confirm "Knowledge Search" appears in the Content section.

- [ ] **Step 3: Commit**

```bash
git add app/views/admin/dashboard/show.html.erb
git commit -m "feat: add knowledge search link to admin dashboard"
```

---

### Task 8: Controller tests

**Files:**
- Create: `test/controllers/admin/searches_controller_test.rb`

- [ ] **Step 1: Write the controller tests**

Create `test/controllers/admin/searches_controller_test.rb`:

```ruby
require "test_helper"

module Admin
  class SearchesControllerTest < ActionDispatch::IntegrationTest
    setup do
      @admin = User.create!(email_address: "admin@example.com", password: "password", admin: true, totp_enabled: true)
      @admin.ensure_totp_secret!

      post session_url, params: { email_address: "admin@example.com", password: "password" }
      follow_redirect!

      totp = ROTP::TOTP.new(@admin.totp_secret, issuer: "TwoRiversMatters")
      post mfa_session_url, params: { code: totp.now }
      follow_redirect!

      seed_prompt_templates
    end

    test "renders search form on empty query" do
      get admin_search_url
      assert_response :success
      assert_select "input[name=q]"
    end

    test "returns results for a query" do
      # Create a searchable knowledge source
      source = KnowledgeSource.create!(
        title: "Test Source", body: "Plan Commission history",
        source_type: "note", origin: "manual", status: "approved", active: true
      )
      IngestKnowledgeSourceJob.perform_now(source.id)

      get admin_search_url, params: { q: "Plan Commission" }
      assert_response :success
    end

    test "unauthenticated users are redirected" do
      delete session_url
      get admin_search_url
      assert_response :redirect
    end
  end
end
```

- [ ] **Step 2: Run the tests**

Run: `bin/rails test test/controllers/admin/searches_controller_test.rb`
Expected: All 3 tests pass.

- [ ] **Step 3: Commit**

```bash
git add test/controllers/admin/searches_controller_test.rb
git commit -m "test: add admin search controller tests"
```

---

### Task 9: Run full test suite and lint

**Files:** None (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `bin/rails test`
Expected: All tests pass.

- [ ] **Step 2: Run linter**

Run: `bin/rubocop`
Expected: No new offenses.

- [ ] **Step 3: Run CI**

Run: `bin/ci`
Expected: All checks pass (rubocop, bundler-audit, importmap audit, brakeman).

- [ ] **Step 4: Fix any issues found, then commit fixes**

If any tests or lint issues are found, fix them and commit:

```bash
git commit -m "fix: address lint/test issues from knowledge search feature"
```

---

### Task 10: Update documentation

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md**

In `CLAUDE.md`, add to the Routes section (under the Admin routes description):

After the existing admin routes line mentioning `/admin/job_runs`, add:

```
`/admin/search` (knowledge search with RAG-powered Q&A)
```

In the Commands table, add:

```
| Seed prompt templates | `bin/rails db:seed` |
```

In the Key Services section, update the `RetrievalService` entry to mention admin search:

```
- **`RetrievalService`** — RAG implementation using pgvector. Retrieves context chunks for AI prompts and admin knowledge search.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with knowledge search feature"
```
