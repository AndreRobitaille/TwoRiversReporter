# Prompt Management & Job Re-Run Console

**Date:** 2026-03-28
**Status:** Design approved
**Scope:** Admin UI for editing AI prompts and re-running pipeline jobs with targeting

## Problem

All 14 AI prompts are hardcoded as heredocs in `Ai::OpenAiService`. Iterating on prompt quality requires a developer (or AI coding agent) to edit Ruby source, which is expensive and slow. There is also no way to re-run specific pipeline jobs against a targeted set of meetings or topics without Rails console access.

## Solution

1. **`PromptTemplate` model** — stores each prompt in the database, editable via admin UI
2. **`PromptVersion` model** — automatic version snapshots on every save, with diff and restore
3. **Admin Prompt Editor** — Silo-themed pages for browsing and editing prompts
4. **Admin Job Re-Run Console** — pick a job type, select targets, enqueue

---

## Data Model

### PromptTemplate

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint | PK |
| `key` | string | Unique, indexed. e.g. `extract_topics` |
| `name` | string | Human label. e.g. "Topic Extraction" |
| `description` | text | What this prompt does (shown in UI) |
| `system_role` | text | System message |
| `instructions` | text | Main prompt body with `{{placeholder}}` markers |
| `model_tier` | string | `default` or `lightweight` |
| `placeholders` | jsonb | Array of placeholder definitions: `[{"name": "existing_topics", "description": "All approved topic names"}]` |
| `created_at` | datetime | |
| `updated_at` | datetime | |

No `destroy` or `create` in admin — the 14 prompts are seeded and fixed.

### PromptVersion

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint | PK |
| `prompt_template_id` | bigint | FK to PromptTemplate |
| `system_role` | text | Snapshot |
| `instructions` | text | Snapshot |
| `model_tier` | string | Snapshot |
| `editor_note` | string | Nullable. What changed. |
| `created_at` | datetime | |

Created automatically on every PromptTemplate save. `belongs_to :prompt_template`. Ordered by `created_at DESC`.

### Seeding

A seed file (`db/seeds/prompt_templates.rb`) extracts the 14 current heredocs from `OpenAiService` into `PromptTemplate` rows. Each seed creates one `PromptVersion` with note "Initial seed from code". Seed is idempotent — skips existing keys by checking `find_or_create_by(key:)`.

The 14 prompt keys:

| Key | Name | Model Tier |
|-----|------|------------|
| `extract_topics` | Topic Extraction | default |
| `refine_catchall_topic` | Catchall Topic Refinement | default |
| `re_extract_item_topics` | Topic Re-extraction | default |
| `triage_topics` | Topic Triage | default |
| `analyze_topic_summary` | Topic Summary Analysis | default |
| `render_topic_summary` | Topic Summary Rendering | default |
| `analyze_topic_briefing` | Topic Briefing Analysis | default |
| `render_topic_briefing` | Topic Briefing Rendering | default |
| `generate_briefing_interim` | Interim Briefing | lightweight |
| `generate_topic_description_detailed` | Topic Description (Detailed) | lightweight |
| `generate_topic_description_broad` | Topic Description (Broad) | lightweight |
| `analyze_meeting_content` | Meeting Content Analysis | default |
| `render_meeting_summary` | Meeting Summary Rendering | default |
| `extract_votes` | Vote Extraction | default |
| `extract_committee_members` | Committee Member Extraction | lightweight |

---

## OpenAiService Integration

Each method that currently builds a prompt inline loads it from the database instead:

```ruby
def extract_topics(agenda_items:, meeting:)
  template = PromptTemplate.find_by!(key: "extract_topics")
  system_role = template.system_role
  instructions = template.interpolate(
    governance_constraints: governance_text,
    existing_topics: existing_topics_text,
    committee_context: prepare_committee_context,
    agenda_items: format_agenda_items(agenda_items),
    meeting_document_context: build_meeting_document_context(meeting)
  )
  # ... call OpenAI as before
end
```

### Interpolation

`PromptTemplate#interpolate(context_hash)` replaces `{{placeholder_name}}` with the provided values. Simple string substitution — no ERB, no logic. Raises `KeyError` if a required placeholder is missing from the hash.

### Fallback

During development/migration, if no DB row exists for a key, `OpenAiService` falls back to the hardcoded heredoc with a `Rails.logger.warn`. Once seeds are run, this fallback is never hit. The hardcoded heredocs remain in the codebase as documentation but are not the runtime source.

### Model Selection

`model_tier` determines which model constant is used. `OpenAiService` maps:
- `"default"` → `DEFAULT_MODEL` (gpt-5.2)
- `"lightweight"` → `LIGHTWEIGHT_MODEL` (gpt-5-mini)

Changing `model_tier` on a prompt template changes which model runs it on the next invocation. The dropdown in the edit UI shows both options.

---

## Admin Prompt Editor

### Routes

```ruby
namespace :admin do
  resources :prompt_templates, only: [:index, :edit, :update]
end
```

No `new`, `create`, `show`, or `destroy`.

### Index Page (`/admin/prompt_templates`)

- Section header: atom marker + "PROMPT TEMPLATES" + trailing gradient line
- Subtitle: "Edit the AI prompts that drive topic extraction, summarization, and analysis."
- Table with columns: Prompt (name + description), Model (status chip), Last Edited (DM Mono timestamp), Edit link
- Sorted alphabetically by name
- No search/filter needed for 14 items

### Edit Page (`/admin/prompt_templates/:id/edit`)

- Breadcrumb: Prompt Templates > [Name]
- Page title: prompt name + model tier dropdown (editable)
- Subtitle: prompt description
- Tabbed interface: **Editor** | **Version History**

**Editor tab:**
- System Role textarea — monospace (DM Mono), ~5 rows
- Instructions textarea — monospace, ~25 rows, resizable
- Below each textarea: collapsible "Available placeholders" reference showing `{{name}}` and description for each placeholder defined in the `placeholders` jsonb
- Edit note — single-line text input, optional
- Save button (creates PromptVersion, updates PromptTemplate)
- Cancel link back to index

**Version History tab:**
- Table: version number (or "Current"), date (DM Mono), edit note, actions
- Actions: Diff, Restore
- Diff: click to expand inline diff below the row. Green additions, red removals. Monospace. Compares selected version against current.
- Restore: copies that version's system_role, instructions, and model_tier back into the form on the Editor tab (switches to Editor tab). Does not save — user must explicitly save.

### Diff Implementation

Use the `diffy` gem for generating unified diffs in Ruby. Render as HTML with `.diff-add` (green background) and `.diff-remove` (red background, strikethrough) classes. Loaded via Turbo Frame on click — no full page reload.

---

## Admin Job Re-Run Console

### Routes

```ruby
namespace :admin do
  resources :job_runs, only: [:index, :create]
end
```

### Page (`/admin/job_runs`)

Single page with a form. Three sections visible at once:

#### 1. Job Type Selection

Card grid or radio group, organized in four categories:

**Extraction**
- Extract Topics — `ExtractTopicsJob`
- Extract Votes — `ExtractVotesJob`
- Extract Committee Members — `ExtractCommitteeMembersJob`

**Summarization**
- Summarize Meeting — `SummarizeMeetingJob`
- Topic Summary — `GenerateTopicSummaryJob` (runs analyze + render passes)
- Topic Briefing — `GenerateTopicBriefingJob`

**Other**
- Topic Triage — `Topics::AutoTriageJob`
- Topic Descriptions — `Topics::GenerateDescriptionJob`

**Ingestion**
- Scrape City Website — `Scrapers::DiscoverMeetingsJob`
  - Sub-option: Full scrape (all committees) or single committee (dropdown)

#### 2. Target Selection

Adapts based on selected job type:

**Meeting-scoped jobs** (Extract Topics, Extract Votes, Extract Committee Members, Summarize Meeting):
- Date range picker: start date + end date
- Preview: "14 meetings in range" (live count via Turbo Frame)
- Optional committee filter dropdown

**Topic-scoped jobs** (Topic Summary, Topic Briefing, Topic Descriptions, Topic Triage):
- Multi-select with search for specific topics
- "All approved topics" checkbox with count
- For Topic Summary: also needs meeting date range (summary is per-topic-per-meeting)

**Ingestion jobs:**
- Full scrape: no target selection needed
- Single committee: dropdown of active committees

#### 3. Enqueue & Progress

- Button: "Enqueue N jobs" with count based on target selection
- Confirmation: "This will enqueue 14 ExtractTopicsJob runs. Proceed?"
- After enqueue: progress section shows job status updates via Turbo Streams
  - Each job: name, status chip (queued → running → completed/failed), duration
  - Summary: "12/14 completed, 2 failed" with links to failed job details

### Job Enqueuing

The controller iterates over selected targets and enqueues the appropriate job class for each:

```ruby
def create
  targets = resolve_targets(params[:job_type], params[:target_params])
  targets.each do |target|
    job_class.perform_later(target.id)
  end
  # Redirect with flash showing count
end
```

Jobs are enqueued to Solid Queue and processed by the existing worker (`bin/jobs`). No new queue or priority needed.

---

## Silo Theme Styling

Both pages use the Silo theme as defined in `docs/plans/2026-03-28-atomic-design-system-spec.md`:

- Cool concrete backgrounds (`--color-bg: #f2f5f5`)
- Teal chrome for headings, links, primary buttons
- DM Mono for all metadata: timestamps, status chips, version numbers, job counts
- Atom marker section headers with trailing gradient line
- Status chips with 1px border (Silo variant)
- Cards with `--radius-lg`, `--shadow-sm` at rest
- Monospace textareas for prompt editing (DM Mono at readable size, slightly raised background)

### New CSS Classes

- `.form-textarea--code` — monospace textarea with subtle raised background for prompt editing
- `.placeholder-ref` — collapsible placeholder reference below textareas
- `.diff-container`, `.diff-add`, `.diff-remove`, `.diff-context` — inline diff rendering
- `.job-type-grid` — card grid for job type selection
- `.target-preview` — live count display for selected targets

---

## Navigation

Add "Prompts" and "Job Runs" to the admin nav bar. Position after "Knowledge" and before "Jobs":

```
Dashboard | Topics | Committees | Members | Knowledge | Prompts | Job Runs | Jobs
```

---

## Dependencies

- `diffy` gem for diff generation (add to Gemfile)
- No other new dependencies

---

## Out of Scope

- Prompt A/B testing or split runs
- Per-prompt temperature/parameter overrides (use model defaults)
- Scheduled re-runs (use existing cron/Solid Queue scheduling)
- Prompt template creation or deletion via UI (always seeded)
- Full admin UI redesign (these pages are the first Silo-themed admin pages; others convert later)
