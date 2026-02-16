# Topic-First Migration Plan (Working Notes)

## Purpose
This plan captures the migration path from meeting-first architecture to a Topic-first system as required by `docs/DEVELOPMENT_PLAN.md` and `docs/topics/TOPIC_GOVERNANCE.md`.

This is a living note for future actions, not an implementation log.

## Constraints (Non-Negotiable)
- Topics are the organizing structure; meetings/documents are inputs.
- Topic Governance is binding for extraction, summarization, and presentation.
- Human-in-the-loop required for topic confirmation, merging, and deletion.
- AI output must separate factual record, institutional framing, and civic sentiment.

## Current Gaps (High Level)
- Topic lifecycle status is not modeled (active/dormant/resolved/recurring).
- Topic review state is not separated from lifecycle status.
- AI topic creation is auto-approved and public by default.
- Summaries are meeting-centric and not Topic-aware.
- Retrieval is meeting-centric and not Topic-aware.
- UI/navigation is meeting-first.

## Proposed Schema Changes (Draft)
### Topics
- Add lifecycle status: `lifecycle_status` (active/dormant/resolved/recurring).
- Add review status: `review_status` (proposed/approved/blocked).
- Add `canonical_name` and `slug` (leave `name` as legacy alias if needed).
- Add `first_seen_at` (derive from earliest agenda association).

### Topic continuity and evidence
- Add `topic_appearances` (or similar) to track agenda item linkage and continuity signals:
  - `topic_id`, `meeting_id`, `agenda_item_id`, `appeared_at`, `body_name`, `evidence_type`, `source_ref`.
- Add `topic_status_events` to log lifecycle transitions with evidence.

### Notes
- Keep existing `agenda_item_topics` as the join table; backfill into `topic_appearances`.
- Preserve existing topic IDs to avoid URL churn.

## Migration Phases
### Phase 1: Schema + Backfill Plan (Completed)
1) [x] Define lifecycle and review status enums.
2) [x] Add columns and tables above (no data removal).
3) [x] Backfill:
   - `first_seen_at` from earliest agenda item.
   - `last_seen_at` from latest agenda item.
   - `lifecycle_status` from recurrence and resolution signals.
4) [x] Add idempotent backfill job with logging.

### Phase 2: Topic Proposal Pipeline
1) [x] AI extraction creates proposals only (review_status = proposed).
2) [x] Admin queue for review/merge/approve/block.
3) [x] Blocklist and alias resolution run before proposal creation.

### Phase 3: Continuity Signals
1) [x] Derive lifecycle status from agenda anchors and resolution evidence.
2) [x] Track deferral/disappearance without implying intent.
3) [x] Log lifecycle transitions in `topic_status_events`.

### Phase 4: Summarization + Retrieval
1) [x] Topic-aware summaries with fact/framing/sentiment separation.
2) [x] Citations required for factual claims.
3) [x] Retrieval uses topic history and caps context size.

### Phase 5: UI + Navigation
1) [x] Topics index grouped by lifecycle status.
2) [x] Topics index: "Recently Updated" row (cross-status recency).
3) [x] Topics index: highlight newly active/resurfaced topics (structural signal badges).
4) Topics index: filters (status, body, timeframe).
5) Topics index: pagination + activity window rules.
6) Topic navigation: standardize click-through behavior.
7) Topic pages: empty/error/low-signal states (QA checklist).
8) Add semantic color tokens for light/dark modes.
9) Apply theme color tokens to Topics + Home.
10) Topic lifecycle status chips.
11) Topic page: add identity accents to top cards.
12) Theme QA: verify tokenized light/dark modes.
13) Home page reoriented to Topic-first modules.

## Backfill Strategy (Draft)
- Run a backfill job that:
  - Rebuilds topic appearances from agenda item associations.
  - Computes first/last seen and lifecycle status.
  - Flags ambiguous cases for admin review (no auto-resolution).
- All backfills must be idempotent and log their changes.

## Risks
- Topic lifecycle inference could misclassify resolution without strong evidence.
- Topic creation auto-approval must be removed carefully to avoid regressions.
- UI changes may disrupt existing navigation expectations; add clear guidance.

## Related GitHub Issues
- #38 Topic review queue + admin triage for AI proposals
- #39 Topic detail page: continuity timeline with motions/votes
- #47 Topic schema redesign + migration/backfill
- #48 Topic continuity pipeline: lifecycle derivation + deferral/disappearance
- #49 Topic-aware summarization (governance-compliant)
- #50 Topic-aware retrieval context + caps

## Explicit Issue Order (Recommended)
1) [x] #47 Topic schema redesign + migration/backfill
2) [x] #38 Topic review queue + admin triage for AI proposals
3) [x] #48 Topic continuity pipeline: lifecycle derivation + deferral/disappearance
4) [x] #49 Topic-aware summarization (governance-compliant)
5) [x] #50 Topic-aware retrieval context + caps
6) [x] #39 Topic detail page: continuity timeline with motions/votes
7) UI reorientation and polish: #30–36, #33–34, #41–43 (include "Recently Updated" row for Topics index)
   - [x] #29 Topics index: lifecycle grouping + recently updated row
   - [x] #32 Topics list: highlight newly active/resurfaced topics
