# Prompt Editor Test Run Feature

**Date:** 2026-03-29
**Status:** Design

## Problem

The admin prompt template editor lets you edit system role and instructions, but there's no way to see what a prompt actually produces against real data. An admin editing a prompt must save it, wait for the next pipeline run, then check the output — a slow, blind feedback loop.

## Solution

Add a test run flow to the prompt editor that:

1. Shows recent real inputs and outputs for each prompt template (from past pipeline runs)
2. Lets the admin edit the prompt, then re-run it against a displayed example to preview the output
3. Shows old output vs. new output side-by-side so the admin can judge whether the change is an improvement

## Data Model

### New model: `PromptRun`

Captures the fully interpolated prompt and raw response each time `OpenAiService` makes an API call.

```
prompt_runs
  id              bigint PK
  prompt_template_key  string    (indexed, matches PromptTemplate.key)
  model_name      string        (e.g. "gpt-5.2", "gpt-5-mini")
  messages        jsonb         (the full messages array sent to the API: [{role:, content:}])
  response_body   text          (raw response content string from the API)
  response_format string        (nullable — "json_object" or nil for text)
  temperature     float         (nullable — the temperature used, nil if not set)
  duration_ms     integer       (nullable — wall-clock time of the API call)
  source_type     string        (nullable — polymorphic: "Meeting", "Topic", etc.)
  source_id       bigint        (nullable — polymorphic: the record that triggered this call)
  created_at      datetime
```

**Associations:**
- `belongs_to :source, polymorphic: true, optional: true` — links to the Meeting, Topic, etc. that triggered the job. Used for display context (e.g., "City Council — Jan 14, 2026").
- No `belongs_to :prompt_template` FK — uses `prompt_template_key` string so the log survives even if templates are restructured. Indexed for fast lookup.

**Retention:** After creating a new `PromptRun`, prune old runs for the same `prompt_template_key` keeping only the most recent 10. Simple `after_create` callback with `DELETE` query.

**Indexes:**
- `prompt_template_key` (for lookups on edit page)
- `[prompt_template_key, created_at]` (for ordering + pruning)
- `[source_type, source_id]` (for polymorphic lookups)

### Recording runs in `OpenAiService`

Add a private method `record_prompt_run` that captures the call data. Each public method in `OpenAiService` calls it after a successful API response. The method accepts:

```ruby
def record_prompt_run(template_key:, messages:, response_content:, model:, response_format: nil, temperature: nil, duration_ms: nil, source: nil)
  PromptRun.create!(
    prompt_template_key: template_key,
    model_name: model,
    messages: messages,
    response_body: response_content,
    response_format: response_format,
    temperature: temperature,
    duration_ms: duration_ms,
    source: source
  )
end
```

**Source record passing:** Jobs that call `OpenAiService` methods need to pass the source record so we can display context. This requires adding an optional `source:` keyword to the public methods in `OpenAiService` (e.g., `extract_votes(text, source: nil)`). Jobs pass the relevant record:

- `SummarizeMeetingJob` → `source: meeting`
- `ExtractTopicsJob` → `source: meeting`
- `ExtractVotesJob` → `source: meeting`
- `ExtractCommitteeMembersJob` → `source: meeting`
- `GenerateTopicBriefingJob` → `source: topic`
- `Topics::GenerateDescriptionJob` → `source: topic`
- `Topics::AutoTriageJob` → `source: nil` (batch operation, no single source)

Jobs that don't pass `source:` simply get `nil` — the run is still recorded and usable, just without a display label.

**Duration tracking:** Wrap the `@client.chat` call with timing:

```ruby
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
response = @client.chat(...)
duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
```

## Edit Page Changes

### New tab: "Examples"

Add a third tab to the edit page alongside "Editor" and "Version History":

**Editor** | **Examples** | Version History

The Examples tab shows the most recent `PromptRun` records for this template (up to 5, ordered by most recent). Each example is a collapsible card showing:

- **Header row:** Source label (e.g., "City Council — Jan 14, 2026" or "Alcohol Licensing" for topics), timestamp, model name, duration
- **Collapsed by default.** Clicking expands to show:
  - **Input section:** The `messages` array, rendered as labeled blocks (System Role, User Prompt). Monospace, scrollable, max-height constrained.
  - **Output section:** The `response_body`, rendered as formatted JSON (if `response_format` was `json_object`) or plain text. Also monospace, scrollable.
- **"Test with this example" button** on each card — starts the test run flow (see below)

### Test run flow

When the admin clicks "Test with this example" on a specific `PromptRun` card:

1. The system grabs the current (possibly edited, unsaved) system role and instructions from the editor form
2. It **re-interpolates** the original prompt using the edited template. This requires reconstructing the original placeholder values from the stored `messages`. Since we store the fully interpolated prompt (not the raw placeholders), re-interpolation is not possible from stored data alone.

**Practical approach:** Instead of re-interpolating, we do a simpler thing — the test run replays the stored `messages` array but with the system role message replaced by the edited one. For the user message (instructions), we need the original placeholder values.

**Revised approach — store placeholder context too:**

Add a `placeholder_values` jsonb column to `prompt_runs`:

```
placeholder_values  jsonb  (nullable — the hash of {placeholder_name: value} passed to interpolate)
```

This lets us re-interpolate with the edited template:

```ruby
# In the test run controller action:
original_run = PromptRun.find(params[:prompt_run_id])
edited_system_role = params[:system_role]
edited_instructions = params[:instructions]

# Build a temporary template with edited text
temp_template = @template.dup
temp_template.system_role = edited_system_role
temp_template.instructions = edited_instructions

# Re-interpolate with original values
new_system_role = temp_template.interpolate_system_role(**original_run.placeholder_values.symbolize_keys)
new_user_prompt = temp_template.interpolate(**original_run.placeholder_values.symbolize_keys)
```

Then call the API with the re-interpolated messages and return the result.

**Recording placeholder values in `OpenAiService`:** Each method already passes named arguments to `interpolate()`. We capture those same arguments:

```ruby
placeholders = { text: text.truncate(50_000) }
prompt = template.interpolate(**placeholders)
# ... later ...
record_prompt_run(..., placeholder_values: placeholders)
```

### Test run controller action

New member route on `prompt_templates`:

```ruby
member do
  get :diff
  post :test_run
end
```

The `test_run` action:

1. Finds the `PromptRun` record
2. Takes edited `system_role` and `instructions` from params
3. Re-interpolates using stored `placeholder_values`
4. Calls the OpenAI API with the re-interpolated messages (same model, response_format, temperature as original)
5. Returns a Turbo Stream or JSON response with the new output

**Response:** Returns a partial that renders a side-by-side comparison:
- Left: "Original Output" — the `response_body` from the stored `PromptRun`
- Right: "Test Output" — the new response from the API call

The test run result is **not persisted** — it's ephemeral, rendered in the response only.

### Stimulus controller changes

Extend `prompt_editor_controller.js`:

- `testRun(event)` — triggered by "Test with this example" button:
  1. Grabs current form values for `system_role` and `instructions`
  2. Shows a spinner on the button ("Running...")
  3. POSTs to `test_run` with: `prompt_run_id`, `system_role`, `instructions`
  4. On response, inserts the comparison partial into the card (below input/output)
  5. Scrolls to the comparison view

### UI layout for comparison

The comparison view (inserted after test run completes) uses a simple stacked layout:

```
┌─────────────────────────────────────────┐
│  Original Output          Test Output   │
│ ┌─────────────────┐ ┌─────────────────┐ │
│ │                 │ │                 │ │
│ │  (stored        │ │  (new API       │ │
│ │   response)     │ │   response)     │ │
│ │                 │ │                 │ │
│ └─────────────────┘ └─────────────────┘ │
└─────────────────────────────────────────┘
```

Both panels are scrollable, monospace, with JSON pretty-printed when applicable. Side-by-side on desktop, stacked on mobile.

## Example diversity

When displaying examples on the edit page, prefer diversity over pure recency. For meeting-related templates (`analyze_meeting_content`, `extract_topics`, `extract_votes`, `extract_committee_members`), the edit page query should try to show examples from different committees:

```ruby
# Prefer diverse sources: group by source, take most recent from each, fill remaining slots with recency
runs = PromptRun.where(prompt_template_key: template.key)
                .order(created_at: :desc)
                .limit(10)

# In Ruby: group by source, take 1 per source, then fill to 5
grouped = runs.group_by { |r| [r.source_type, r.source_id] }
diverse = grouped.values.map(&:first).sort_by(&:created_at).reverse.first(5)
```

This ensures the admin sees e.g. a City Council run and a Plan Commission run, not just the 5 most recent (which might all be from the same meeting batch).

## Files to create/modify

### New files
- `db/migrate/TIMESTAMP_create_prompt_runs.rb` — migration
- `app/models/prompt_run.rb` — model with retention pruning
- `app/views/admin/prompt_templates/_examples_tab.html.erb` — examples tab partial
- `app/views/admin/prompt_templates/_prompt_run_card.html.erb` — individual run card
- `app/views/admin/prompt_templates/_test_comparison.html.erb` — side-by-side comparison partial

### Modified files
- `app/services/ai/open_ai_service.rb` — add `record_prompt_run`, add `source:` param, capture placeholders + timing
- `app/controllers/admin/prompt_templates_controller.rb` — add `test_run` action, update `edit` to load examples
- `app/views/admin/prompt_templates/edit.html.erb` — add Examples tab
- `app/javascript/controllers/prompt_editor_controller.js` — add `testRun` action
- `config/routes.rb` — add `test_run` member route
- Jobs that call OpenAiService — add `source:` parameter passthrough (6-7 jobs)

## Edge cases

- **Template with no runs yet:** Examples tab shows empty state: "No examples yet. This prompt will capture examples the next time it runs in the pipeline."
- **Placeholder values contain large text:** The `placeholder_values` jsonb could be large (meeting documents are 50K+). This is acceptable — these records are pruned to 10 per template (max ~150 rows total across all 15 templates), and PostgreSQL jsonb handles large values fine.
- **Test run fails (API error):** Show the error message in the test output panel instead of a result. No special handling needed.
- **Admin edits template and test runs, then navigates away without saving:** No prompt change is persisted. The test run is ephemeral. This is intentional.
- **`triage_topics` has a Gemini branch:** Only record runs for the OpenAI path. The Gemini path doesn't use `PromptTemplate` so there's nothing to test against.
- **`generate_topic_description` uses two templates conditionally:** Each path records against its own template key (`generate_topic_description_detailed` or `generate_topic_description_broad`). Both show up on their respective edit pages.
