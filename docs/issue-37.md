# Issue 37 Review: Topic Quality Pipeline

## Summary
Issue 37 requests a canonical Topic model with lifecycle states so AI can propose topics without immediately exposing low-quality or duplicate topics publicly. The goal is to reduce topic noise, enable aliasing of near-duplicates, and allow light human steering (approve/block/pin) while keeping extraction mostly AI-driven.

## Product intent (from issue + user context)
- Topics currently render at `/topics`, but the concept is intended to drive other site features such as "what to watch."
- Curated or pinned topics should elevate upcoming meetings that discuss or vote on those topics.
- AI should continue proposing topics, but only approved (or pinned) topics appear publicly.

## Required data model
- `Topic`
  - `name` (string, canonical)
  - `status` (enum: proposed | approved | blocked)
  - `pinned` (boolean)
  - `importance` (small integer, optional)
  - `summary` (text, optional)
  - `last_seen_at` (datetime)
  - `last_activity_at` (datetime)

- `TopicAlias`
  - `topic_id` (FK -> Topic)
  - `name` (string)

- `AgendaItemTopic` (join table)
  - `agenda_item_id` (FK -> AgendaItem)
  - `topic_id` (FK -> Topic)

## Pipeline behavior
- AI extraction creates topics in `proposed` state only.
- Before creating a new topic:
  - Normalize name (case, punctuation, whitespace).
  - Check blocklist (admin-managed in DB).
  - Run similarity check (pg_trgm or equivalent) against existing Topics.
  - If similarity over threshold, create/attach `TopicAlias` instead of new Topic.
- Blocked topics are treated as false positives:
  - AI skips attaching/creating topics that match a blocked topic or blocklist entry.
  - Admin can unblock previously blocked topics.
- Update `last_seen_at` and `last_activity_at` when attached to new agenda items or activity.

## Visibility rules
- Public topics list only includes:
  - `status = approved` OR
  - `pinned = true`
- Proposed + blocked topics remain internal only.

## Human steering
- Admin actions (via `/admin`):
  - Approve a proposed topic.
  - Block/unblock a topic.
  - Pin/unpin a topic to elevate public visibility.
  - Optionally set importance and/or summary.
  - Manage blocklist entries.

## Quality controls
- Maintain a blocklist of common boilerplate topics in the database (admin-managed).
- Keep similarity threshold explicit/configurable (initial default TBD by us).
- Alias handling should avoid creating duplicates while preserving traceability.

## Implications for "what to watch"
- Use `pinned` and/or `importance` to identify critical topics.
- Surface upcoming meetings that have agenda items linked to those topics.

## Open questions
1. Similarity threshold for pg_trgm: start at 0.7 and tune with real data.
2. `TopicAlias` is unique per normalized name (no duplicates across topics).
3. Guard `last_activity_at` via AI extraction rules:
   - Detect embedded prior-meeting minutes within consent agenda packets.
   - Ignore those prior-meeting minutes for activity in the current meeting.
   - Use meeting date context in prompts to avoid false positives.

## Implementation Status (Completed)
- [x] **Data Models**: Created `Topic`, `TopicAlias`, `TopicBlocklist` with appropriate indices and `pg_trgm` integration.
- [x] **Service Logic**: Implemented `Topics::FindOrCreateService` to handle normalization, blocklisting, and similarity matching (aliasing > 0.7).
- [x] **AI Integration**: Updated `ExtractTopicsJob` and OpenAI prompts to filter administrative noise and prior meeting minutes.
- [x] **Admin UI**: Built `/admin/topics` for managing topics (Approve/Block/Pin/Merge/Alias) and Blocklist.
- [x] **Public UI**: Updated `/topics` to only show Approved or Pinned topics.
- [x] **Default Behavior**: New topics are now created as **Approved** by default (per user request).
- [x] **Backfill**: Migrated existing topics to Approved state and backfilled `last_seen_at` timestamps.

## Todos
- [x] Add `Topic`, `TopicAlias`, `AgendaItemTopic`, and `TopicBlocklist` models + migrations.
- [x] Add indices/constraints for uniqueness and performance (normalized name + trigram).
- [x] Implement normalization + blocklist filter in topic creation flow.
- [x] Implement similarity/alias logic with pg_trgm threshold.
- [x] Update AI extraction job to create `proposed` topics only. (CHANGED: Defaults to `approved`).
- [x] Update public `/topics` queries to filter by approved/pinned.
- [x] Extend `/admin` topics management for approve/block/pin/unblock and blocklist edits.
- [x] Track `last_seen_at` and `last_activity_at` updates.
- [x] Add a guard for `last_activity_at` to avoid prior-meeting minutes embedded in packets.
- [x] Add tests for blocklist, similarity, aliasing, and visibility rules.
