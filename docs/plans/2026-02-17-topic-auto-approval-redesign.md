# Topic Auto-Approval Redesign

## Problem

The topic creation/approval system requires too much manual admin intervention. The auto-triage confidence threshold (0.9) is too conservative — the AI makes good decisions but reports low confidence, so <20% of topics are auto-handled. The review queue fills with three categories of noise:

1. Procedural items the Administrative filter missed
2. Near-duplicate topics the similarity matching didn't catch
3. One-off agenda items that aren't persistent civic concerns

Additionally, the AI lacks community context. It uses institutional signals (committee activity, agenda recurrence) as proxies for importance, when what matters to Two Rivers residents is fundamentally different from what the city bureaucracy spends time on.

## Design Principles

- **Shift from pre-approval gatekeeping to post-approval auditing** — the admin reviews what the AI did, not what it wants to do
- **Community-aware AI at every stage** — the AI must understand Two Rivers residents' values and concerns to make good topic decisions
- **Tiered risk tolerance** — different actions have different blast radii; blocking procedural junk is low-risk, approving a novel topic is high-risk
- **Governance-compliant** — human review remains available; novel, ambiguous, or politically sensitive topics still flag for human review per TOPIC_GOVERNANCE.md Section 9

## Changes

### 1. Community-Aware Extraction

**Files:** `app/services/ai/open_ai_service.rb` (extract_topics method), `app/jobs/extract_topics_job.rb`

The extraction prompt currently uses a generic civic classifier with no community context. Change to:

**a) Inject community context via KnowledgeSource RAG.** Before calling `extract_topics`, retrieve relevant KnowledgeSource chunks tagged for extraction use. Include them as a preamble so the AI understands what kinds of issues matter to Two Rivers residents.

**b) Add `topic_worthy` boolean to the AI response schema.** The AI must explicitly decide whether each tag warrants topic creation. Items marked `topic_worthy: false` still get categorized but don't create Topic records. This forces the AI to distinguish persistent civic concerns from single-meeting routine business.

```json
{
  "items": [
    {
      "id": 123,
      "category": "Licensing",
      "tags": ["Downtown Liquor License Policy"],
      "topic_worthy": true,
      "confidence": 0.85
    },
    {
      "id": 124,
      "category": "Licensing",
      "tags": ["Individual License Renewal"],
      "topic_worthy": false,
      "confidence": 0.9
    }
  ]
}
```

**c) Add a `Routine` skip category** alongside `Administrative`. Routine items (individual license renewals, single-person appointments, standard approvals) get categorized but don't produce topics.

**d) Feed existing approved topic names into the extraction prompt.** The AI should know what topics already exist so it can tag items to existing topics rather than inventing new granular names. This directly reduces near-duplicates.

### 2. Community-Aware Triage

**Files:** `app/services/topics/triage_tool.rb`, `app/services/ai/open_ai_service.rb` (triage_topics method), `app/jobs/topics/auto_triage_job.rb`

**a) Inject the same community context** into the triage prompt via KnowledgeSource RAG. The AI's approval/block/merge decisions should be informed by resident salience, not just institutional signals.

**b) Tiered confidence thresholds** instead of a flat 0.9:

| Action | Threshold | Rationale |
|--------|-----------|-----------|
| Block procedural/routine | 0.7 | Low risk — worst case, admin unblocks |
| Merge into existing approved topic | 0.75 | Medium-low — target already approved, just routing a duplicate |
| Approve community-salient topic | 0.8 | Medium — AI has community context to judge salience |
| Approve novel/ambiguous topic | 0.9 | High — governance requires human review for novelty/sensitivity |

Implement by passing separate thresholds to `TriageTool` and applying per-action instead of a single `@min_confidence`.

**c) Fix the audit trail gap.** `record_review_event` currently short-circuits when `user` is nil (line 247-250 of triage_tool.rb). Change to record events with an `automated: true` flag or a sentinel system user, so all auto-triage decisions are visible in the audit log.

### 3. Blocklist Learning

**Files:** `app/controllers/admin/topics_controller.rb` (block action), `app/models/topic_blocklist.rb`

When an admin manually blocks a topic, auto-generate blocklist entries for similar name variants using pg_trgm similarity (threshold 0.8). This prevents the "public comment" vs "public comments" gap where the blocklist catches one form but not another.

### 4. Admin Experience: Audit View

**Files:** `app/controllers/admin/topics_controller.rb`, `app/views/admin/topics/index.html.erb`

**a) Add "Recent AI Decisions" tab** to the admin topics index. Shows topics that were auto-approved, auto-blocked, or auto-merged in the last 7 days, with:
- The action taken
- AI confidence score
- AI rationale
- One-click undo (approve ↔ block, unmerge)

**b) The existing review queue remains** for genuinely novel/ambiguous topics that the AI couldn't confidently handle. With the upstream and triage improvements, this queue should be much smaller.

### 5. Seed Community Context KnowledgeSource

**Files:** Database seed or admin action

Create KnowledgeSource entries capturing Two Rivers community context for extraction and triage use:

- **Community identity:** Post-industrial city with strong generational attachment. Residents have deep nostalgia for the manufacturing era and are skeptical of economic transition narratives.
- **High-salience concerns:** Property taxes and assessments; development/zoning changes that alter community character; tourism-vs-manufacturing economic tension; school and infrastructure decisions; downtown identity and Main Street/Washington Street changes; anything generating significant public comment.
- **Resident disposition:** Skepticism toward city leadership (elected and appointed); feeling that decisions are made without genuine input; attention to who benefits from decisions; value placed on stability over growth.
- **Low-salience / routine items:** Standard license renewals for existing businesses; routine budget approvals without tax impact; individual personnel actions; procedural committee business; proclamations and ceremonial items.
- **What engagement looks like:** Volume and intensity of public comment is the strongest signal of resident concern. Divided or contentious votes signal community misalignment. Items that change the physical or economic character of neighborhoods matter more than institutional process items.

Tag these KnowledgeSource entries so the extraction and triage retrieval can find them.

### 6. ExtractTopicsJob Flow Change

**Files:** `app/jobs/extract_topics_job.rb`

Update the job to:
1. Retrieve community context chunks before calling AI
2. Pass existing approved topic names as context
3. Respect the `topic_worthy` field — skip `FindOrCreateService` for items marked `false`
4. Skip items categorized as `Routine` (in addition to existing `Administrative` skip)

## What Doesn't Change

- `FindOrCreateService` deduplication chain (blocklist → exact → alias → similarity → create) — still works as-is
- Topic lifecycle/continuity derivation via `ContinuityService` — purely rules-based, unaffected
- Summarization pipeline — still only runs for approved topics, still validates citations
- Resident impact score system — separate from this work
- TOPIC_GOVERNANCE.md compliance — all changes respect the governance constraints

## Risk Assessment

- **Occasional bad auto-approval:** A non-topic or low-quality topic briefly appears on the public site. Mitigated by the audit view — admin catches and corrects in periodic review. Accepted risk per user preference.
- **Missing a genuinely new topic:** Possible if the extraction prompt becomes too aggressive about filtering. Mitigated by keeping the `topic_worthy` decision explicit (AI must justify) and keeping the novel-topic threshold at 0.9 (flags for human review).
- **Community context drift:** The KnowledgeSource entries may need updating as Two Rivers changes. Mitigated by admin editability — same as existing knowledge sources.
