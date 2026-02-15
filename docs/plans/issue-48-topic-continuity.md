# Issue 48 Plan: Topic continuity pipeline (lifecycle + deferral/disappearance)

Goal: derive Topic lifecycle status from observable evidence, log status transitions, and surface deferral/disappearance signals without implying intent.

References:
- docs/DEVELOPMENT_PLAN.md
- docs/topic-first-migration-plan.md
- docs/topics/TOPIC_GOVERNANCE.md

## Current State (code + schema)
- Continuity evidence table exists: topic_appearances (agenda_item evidence only so far).
- TopicStatusEvent table exists but no pipeline writes events.
- Topics::BackfillContinuityJob builds topic_appearances and sets lifecycle_status via a 6-month heuristic.
- Motions + votes are extracted from minutes (ExtractVotesJob) and linked to agenda items where possible.

## Objectives (from Issue 48)
- Detect recurrence, deferrals, and disappearance without resolution.
- Track cross-body progression (committee -> council).
- Update lifecycle status based on agenda anchors and resolution signals.
- Log status transitions with timestamps; keep behavior explainable and reproducible.

## Constraints (Topic Governance)
- Prefer agenda anchors and document evidence. No resolution inference without artifacts.
- Disappearance is a signal, not a conclusion. Avoid implying intent or motive.
- Separate factual record from interpretation; log evidence with source_ref.

## Data Inputs (available now)
- topic_appearances: agenda item evidence with meeting + body_name + appeared_at.
- agenda_items: title, recommended_action, summary.
- motions: description + outcome (from minutes extraction).
- meeting_documents: minutes_pdf presence implies motions/outcomes are available for that meeting.

## Proposed Continuity Rules (deterministic)

### 1) Recurrence / Activity
- Use ordered topic_appearances by appeared_at as the primary signal.
- Active if last appearance is within ACTIVITY_WINDOW (initially 6 months, keep as constant).
- Dormant if no appearances within ACTIVITY_WINDOW and no resolution signal.

### 2) Resolution signals (strict evidence only)
- Resolution indicates a formal decision event occurred (recorded action), not that the topic is permanently closed.
- Resolve only when there is explicit evidence in minutes-based motion outcomes tied to agenda items for the topic.
- Maintain a small, explicit outcome mapping (e.g., passed/adopted/approved/accepted/enacted).
- When outcome is ambiguous or absent, do not resolve; keep status based on appearance recency.
- Record TopicStatusEvent with evidence_type "motion_outcome" and source_ref containing motion_id, meeting_id, agenda_item_id, outcome, and minutes document id if available.

### 3) Recurring status
- If a topic previously had a resolved event and appears again after a RESOLUTION_COOLDOWN window, mark as recurring.
- Recurring is expected for long-lived issues; it is not a regression of resolution, but a new phase with new evidence.
- Log a TopicStatusEvent with evidence_type "agenda_recurrence" and source_ref pointing to the new appearance.
- If no prior resolved event exists, do not mark recurring.

### 4) Deferral signals
- Detect deferral language in agenda item title/recommended_action/summary and/or minutes outcomes.
- Use a keyword list ("defer", "continue", "tabled", "postpone", "carry over") applied to agenda item fields and motion outcome/description.
- When matched, create a TopicStatusEvent with lifecycle_status unchanged, evidence_type "deferral_signal", and source_ref pointing to the agenda item and meeting.
- Do not change lifecycle_status to resolved/dormant solely due to deferral signals.

### 5) Disappearance signals (non-conclusive)
- If a topic has no appearances for DISAPPEARANCE_WINDOW but has no resolution evidence, log a TopicStatusEvent with evidence_type "disappearance_signal".
- This should not automatically mark resolved; it can set status to dormant if outside ACTIVITY_WINDOW.
- Provide source_ref with last known appearance and computed gap duration for explainability.

### 6) Cross-body progression
- Track body_name sequence from topic_appearances.
- When a new body_name appears (e.g., committee -> council), log a TopicStatusEvent evidence_type "cross_body_progression" with source_ref containing prior and current bodies + appearance ids.
- Do not change lifecycle_status solely based on body progression.

## Pipeline Design

### Core service
Introduce Topics::ContinuityService (or similar) that:
1) Loads appearances + motions for the topic (or for a meeting, then scoped to impacted topics).
2) Derives lifecycle_status deterministically using the rules above.
3) Emits TopicStatusEvent records for transitions and signals (deferral/disappearance/cross-body).
4) Updates topic.lifecycle_status, first_seen_at/last_seen_at/last_activity_at when needed.

### Job orchestration
- Create Topics::UpdateContinuityJob that:
  - Accepts topic_id (single) or meeting_id (batch for recently updated meeting).
  - Is idempotent by:
    - recomputing lifecycle status from current evidence;
    - de-duplicating status events via (topic_id, occurred_at, evidence_type, source_ref fingerprint).
- Call sites:
  - After agenda item topic association creation.
  - After ExtractVotesJob completes for a meeting (minutes evidence).
  - For backfill, run in batch after Topics::BackfillContinuityJob completes.

### Event logging rules
- Only write a new TopicStatusEvent when:
  - lifecycle_status changes, or
  - a signal event occurs (deferral/disappearance/cross-body).
- Keep event timestamps deterministic (use appearance date or meeting date).
- Include notes for ambiguity ("deferral keyword matched in agenda_item.recommended_action").

## Tests (Minitest)
- Service tests covering:
  - Active vs dormant thresholds based on appearance recency.
  - Resolved when motion outcome matches explicit allowlist.
  - Recurring when resolved topics reappear after cooldown.
  - Deferral signal creation without status change.
  - Disappearance signal logged without implying resolution.
  - Cross-body progression signal when body_name changes.
- Event de-duplication test for idempotent job reruns.

## Rollout Notes
- Start with conservative outcome mapping; expand only with documented evidence.
- Keep thresholds as constants in service for easy tuning.
- Log warnings when evidence is missing or ambiguous; never raise unhandled exceptions in jobs.

## UI/UX Guidance (for resident/admin clarity)
- Label resolved status as "Formal action recorded" (or similar) with a short tooltip: "A decision was recorded at this time; topics can return later."
- When a topic becomes recurring, surface both the prior resolution event and the new appearance date to reinforce continuity.
- In admin views, show the evidence_type + source_ref snippet for status changes to keep them auditable.

## Open Decisions (confirm before implementation)
1) Define explicit motion outcome mapping list for "resolved" (current ExtractVotesJob outputs are free-text).
2) Thresholds: ACTIVITY_WINDOW, DISAPPEARANCE_WINDOW, RESOLUTION_COOLDOWN.
3) Event de-duplication strategy (unique constraint vs. application-level fingerprinting).
