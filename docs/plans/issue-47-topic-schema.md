# Issue 47 Plan: Topic schema redesign + migration/backfill

Goal: introduce topic lifecycle + review separation, continuity evidence, and backfill strategy while preserving existing topic IDs and URLs.

References:
- docs/DEVELOPMENT_PLAN.md
- docs/topic-first-migration-plan.md
- docs/topics/TOPIC_GOVERNANCE.md

## Current State (from schema)
- topics: name, description, status (proposed/approved/blocked), importance, last_activity_at, last_seen_at, pinned
- agenda_item_topics: join between agenda_items and topics
- topic_aliases and topic_blocklists exist

## Proposed Schema Changes (draft)
Note: any data model changes must be confirmed before implementation.

### Topics table
- Add `canonical_name` (string, required, normalized, unique)
- Add `slug` (string, required, unique)
- Add `review_status` (string enum: proposed/approved/blocked)
- Add `lifecycle_status` (string enum: active/dormant/resolved/recurring)
- Add `first_seen_at` (datetime)
- Keep existing `name` as legacy display/alias input (retain for compatibility)
- Keep `last_seen_at` and `last_activity_at` (recompute via backfill)

### New table: topic_appearances
Tracks evidence for continuity and agenda linkage.
- topic_id (FK)
- meeting_id (FK)
- agenda_item_id (FK, nullable)
- appeared_at (datetime)
- body_name (string)
- evidence_type (string enum: agenda_item/meeting_minutes/document_citation)
- source_ref (jsonb for page numbers, document IDs, etc.)

Indexes:
- topic_id + appeared_at
- meeting_id
- agenda_item_id

### New table: topic_status_events
Tracks lifecycle status transitions and evidence.
- topic_id (FK)
- lifecycle_status (string)
- occurred_at (datetime)
- evidence_type (string)
- source_ref (jsonb)
- notes (text, optional)

Indexes:
- topic_id + occurred_at

## Migration & Backfill Strategy
All backfills must be idempotent and log their work.

1) Migration 1: add new columns to topics (nullable, no defaults yet).
2) Migration 2: create topic_appearances + topic_status_events tables with indexes/constraints.
3) Migration 3: data migration or job to populate:
   - canonical_name from normalized current name
   - slug from canonical_name (parameterized)
   - review_status mapped from existing status
   - first_seen_at/last_seen_at via agenda_item_topics + agenda_items + meetings
   - topic_appearances rebuilt from agenda_item_topics

Backfill job (recommended): Topics::BackfillContinuityJob
- Deletes and rebuilds topic_appearances for idempotency
- Computes first_seen_at/last_seen_at based on appeared_at
- Sets lifecycle_status to active by default when evidence exists, dormant when none
- Writes logs with counts, topic IDs, and any missing meeting links
- Does not infer resolved/recurring yet (reserved for issue #48)

## Model Updates (planned)
- Topic validations for canonical_name, slug, review_status, lifecycle_status
- Keep normalization logic but target canonical_name instead of name
- Introduce scopes for review_status and lifecycle_status
- Maintain existing Topic API for status until the app is updated (transition period)

## Risks / Mitigations
- Renaming `status` to `review_status` affects existing code paths.
  - Mitigation: add review_status alongside status first; migrate usage in a follow-up change.
- Slug uniqueness conflicts if multiple topics normalize to same canonical_name.
  - Mitigation: detect collisions and suffix slugs in backfill; log collisions for admin review.
- Missing or inconsistent agenda_item/meeting links.
  - Mitigation: skip and log anomalies; avoid raising.

## Acceptance Criteria
- Schema supports lifecycle_status, review_status, canonical_name, slug, first_seen_at.
- topic_appearances and topic_status_events tables exist with indexes and FKs.
- Backfill job is idempotent, logs progress, and populates continuity fields without inference.
- No change to public-facing behavior yet (UI changes follow in later issues).

## Open Decisions (confirm before implementation)
1) Rename `topics.status` to `review_status` now, or introduce review_status and deprecate status later.
2) Should `name` remain a user-facing display field or be replaced by canonical_name?
3) Slug collision handling strategy: suffix with short hash vs. incrementing integer.
