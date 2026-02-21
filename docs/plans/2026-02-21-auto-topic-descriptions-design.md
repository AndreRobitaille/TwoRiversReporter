# Auto-Generated Topic Descriptions

## Problem

331 of 332 topics had empty descriptions. The topic card partial renders descriptions when present (truncated to 80 chars), but without them the topics index page showed only names and metadata — insufficient context for residents.

## Design Decisions

- **Static explainer, not dynamic headline.** Descriptions explain what a topic covers ("Requests for property setback and fence variances"). Headlines in TopicSummary handle "what happened recently."
- **Activity-informed but scope-level.** Descriptions reflect the breadth of a topic's activity without anchoring to any single event, address, or applicant. A topic like "development" should describe the range of what it covers, not the latest project.
- **Tiered generation.** Topics with 3+ agenda items get activity-informed descriptions. Fewer than 3 get broader civic-concept descriptions.
- **80-character target.** Matches the existing `truncate(..., length: 80)` in `_topic_card.html.erb`.
- **Lightweight model.** Uses `gpt-5-mini` via `LIGHTWEIGHT_MODEL` constant. Override with `OPENAI_LIGHTWEIGHT_MODEL` env var.
- **Fixed refresh schedule.** Regenerate every 90 days via a weekly sweep job. No scope-change detection heuristics.
- **Admin override respected.** Manually-edited descriptions are never overwritten.

## How It Works

### Automatic Operation

1. **New topics**: When `TriageTool` auto-approves a topic, or an admin approves via the admin UI (single or bulk), `Topics::GenerateDescriptionJob` is enqueued automatically.
2. **Weekly refresh**: `Topics::RefreshDescriptionsJob` runs every Monday at 3am (configured in `config/recurring.yml`). It finds approved topics where:
   - `description_generated_at` is older than 90 days (stale AI descriptions), OR
   - `description` is blank and `description_generated_at` is nil (never generated)
   - It skips admin-edited topics (description present + `description_generated_at` nil)
3. **Admin override**: When an admin manually edits a description in the admin form, `description_generated_at` is set to nil. This tells the refresh job to leave it alone permanently.

### Manual Operation

**Backfill all missing descriptions:**
```bash
bin/rails topics:generate_descriptions
```
Runs synchronously, prints each description as it's generated. Safe to re-run — skips topics that already have descriptions.

**Generate for a single topic:**
```bash
bin/rails runner "Topics::GenerateDescriptionJob.perform_now(TOPIC_ID)"
```

**Force-regenerate a specific topic** (even if it has one):
```bash
bin/rails runner "Topic.find(ID).update!(description_generated_at: 100.days.ago); Topics::GenerateDescriptionJob.perform_now(ID)"
```

## Data Model

One column on `topics`:

```ruby
add_column :topics, :description_generated_at, :datetime
```

- Set when AI generates/regenerates a description.
- Nil means either never auto-generated or manually edited by admin.
- Periodic refresh only targets rows where `description_generated_at < 90.days.ago`.

## Components

### 1. `Ai::OpenAiService#generate_topic_description(topic_context)`

New method. Receives topic name, agenda item titles/summaries, and any existing headlines. Returns a plain string (the description).

Prompt guardrails:
- One sentence, max 80 characters
- Describe the scope of the topic, not a specific event
- No addresses, applicant names, dates, or votes
- Neighborhood-conversation language, not bureaucratic jargon
- Tiered: if 3+ agenda items, "based on the following activity, describe what this topic covers"; if fewer, "write a broad civic-concept description"

Uses `LIGHTWEIGHT_MODEL` constant (`gpt-5-mini`).

### 2. `Topics::GenerateDescriptionJob`

- Takes `topic_id`
- Loads topic + agenda items (titles, summaries) + any TopicSummary headlines
- Calls `OpenAiService#generate_topic_description`
- Writes `description` and `description_generated_at`
- Guard: skips admin-edited descriptions and recently-generated descriptions
- Idempotent, safe to re-run. Rescues errors and logs them.

### 3. `Topics::RefreshDescriptionsJob`

- Runs weekly (Solid Queue recurring schedule, `config/recurring.yml`)
- Finds approved topics with stale or missing descriptions
- Enqueues `GenerateDescriptionJob` for each
- Thin scheduler — no AI calls itself

### 4. Integration Points

- **`TriageTool.apply_approvals`** — enqueues after auto-approval
- **`Admin::TopicsController#approve`** — enqueues after manual approval
- **`Admin::TopicsController#bulk_update`** — enqueues for each bulk-approved topic
- **`Admin::TopicsController#update`** — nils `description_generated_at` when description is manually edited

### 5. Rake Task

`bin/rails topics:generate_descriptions` — backfills all approved topics with missing descriptions, running synchronously with progress output.

## Not Included (YAGNI)

- No admin UI button for triggering regeneration (clear description + wait for refresh, or use rake task)
- No per-topic refresh interval
- No description change history
- No view changes (card partial already renders descriptions)
