# Plan: Topic Triage Tool (temporary auto-apply cleanup)

## Goal
Provide a backend tool that uses a reasoning LLM to recommend topic merges, approvals, and procedural blocks, with an explicit `apply` switch for temporary auto-application. Default mode is review-only.

## References
- `docs/topics/TOPIC_GOVERNANCE.md`
- `docs/DEVELOPMENT_PLAN.md`
- `app/jobs/extract_topics_job.rb`
- `app/services/ai/open_ai_service.rb`
- `app/models/topic.rb`

## Problem Summary
Topic extraction currently produces procedural noise (Roberts Rules/admin items) and overly granular topical categories (e.g., beer, wine, bars) that should roll up to a resident-facing canonical topic like “Alcohol licensing.”

## Constraints
- Human-in-the-loop remains the default; auto-apply is an explicit, temporary opt-in.
- Avoid auto-approval/merges when evidence is ambiguous or conflicting.
- Respect governance separation of factual record vs framing vs sentiment.

## Proposed Tool Interface
- Runner entrypoint: `Topics::TriageTool.call(apply: false, dry_run: true, min_confidence: 0.85)`
- CLI usage (examples):
  - Review-only: `bin/rails runner "Topics::TriageTool.call"`
  - Auto-apply: `bin/rails runner "Topics::TriageTool.call(apply: true, dry_run: false, min_confidence: 0.9)"`

## Data Inputs
- Candidate topics (status != blocked), including:
  - name, canonical_name, lifecycle_status, last_activity_at, agenda item titles/summaries
- Similarity candidates via `Topic.similar_to` and shared agenda item overlap
- Procedural signal keywords (Roberts Rules, roll call, adjournment, etc.)

## LLM Output (JSON)
```
{
  "merge_map": [
    { "canonical": "Alcohol licensing", "aliases": ["Beer", "Wine", "Bars"], "confidence": 0.92, "rationale": "..." }
  ],
  "approvals": [
    { "topic": "Alcohol licensing", "approve": true, "confidence": 0.9, "rationale": "..." }
  ],
  "blocks": [
    { "topic": "Robert's Rules", "block": true, "confidence": 0.96, "rationale": "Procedural only" }
  ]
}
```

## Apply Rules (auto-apply)
- Merge only when:
  - Confidence >= `min_confidence`
  - Strong similarity + shared evidence (agenda overlap)
  - No lifecycle status conflicts across bodies
- Approve only when:
  - Non-procedural
  - Confidence >= `min_confidence`
  - Clear resident-facing scope
- Block only when:
  - Procedural/administrative signals are explicit
- Always log decisions via review events/audit trail

## Persistence & Audit
- Store triage runs in a `topic_review_events` entry (or add a dedicated `topic_triage_events` table if needed).
- Record before/after for merges, approvals, and blocks.

## Implementation Steps
1) Add `Topics::TriageTool` service with candidate generation and rules.
2) Add LLM prompt in `Ai::OpenAiService` (JSON mode, reasoning model).
3) Add `--apply` behavior with guardrails + audit logging.
4) Add dry-run reporting (summary printed to console).
5) Add tests for merge and block rules (no LLM calls; stub JSON).

## Open Questions
- Should auto-apply set `status=approved` or only merge/block? (Recommendation: allow approvals when confidence is high and non-procedural.)
