# Auto-Generated Topic Descriptions

## Problem

331 of 332 topics have empty descriptions. The topic card partial already renders descriptions when present (truncated to 80 chars), but without them the topics index page shows only names and metadata — insufficient context for residents.

## Design Decisions

- **Static explainer, not dynamic headline.** Descriptions explain what a topic covers ("Requests for property setback and fence variances"). Headlines in TopicSummary handle "what happened recently."
- **Activity-informed but scope-level.** Descriptions reflect the breadth of a topic's activity without anchoring to any single event, address, or applicant. A topic like "development" should describe the range of what it covers, not the latest project.
- **Tiered generation.** Topics with 3+ agenda items get activity-informed descriptions. Fewer than 3 get broader civic-concept descriptions.
- **80-character target.** Matches the existing `truncate(..., length: 80)` in `_topic_card.html.erb`.
- **Lightweight model.** Uses `gpt-4.1-mini` (or equivalent) — no reasoning model needed for one-sentence generation.
- **Fixed refresh schedule.** Regenerate every 90 days via a weekly sweep job. No scope-change detection heuristics.
- **Admin override respected.** Manually-edited descriptions are never overwritten.

## Data Model

One new column on `topics`:

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

Uses a lightweight model constant (e.g., `LIGHTWEIGHT_MODEL = "gpt-4.1-mini"`).

### 2. `Topics::GenerateDescriptionJob`

- Takes `topic_id`
- Loads topic + agenda items (titles, summaries) + any TopicSummary headlines
- Calls `OpenAiService#generate_topic_description`
- Writes `description` and `description_generated_at`
- Guard: skips if `description_generated_at` is present and within refresh threshold (prevents duplicate work)
- Idempotent, safe to re-run

### 3. Integration: `TriageTool.apply_approvals`

After approving a topic, enqueue `Topics::GenerateDescriptionJob.perform_later(topic.id)`.

### 4. Integration: Admin form

When an admin manually edits the description field, nil out `description_generated_at` so the refresh job leaves it alone.

### 5. `Topics::RefreshDescriptionsJob`

- Runs weekly (Solid Queue recurring schedule)
- Finds approved topics where `description_generated_at < 90.days.ago`
- Enqueues `GenerateDescriptionJob` for each
- Thin scheduler — no AI calls itself

### 6. Backfill

Rake task or one-liner:
```ruby
Topic.where(status: "approved").where(description: [nil, ""]).find_each do |t|
  Topics::GenerateDescriptionJob.perform_later(t.id)
end
```

## Not Included (YAGNI)

- No admin UI button for triggering regeneration (clear description + wait for refresh)
- No per-topic refresh interval
- No description change history
- No view changes (card partial already renders descriptions)
