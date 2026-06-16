# Committee-Scoped Topic Extraction and Surgical Reanalysis Design

## Problem

The topic extraction pipeline linked the Room Tax Commission agenda item `BUDGET REVIEW` from meeting `216` to the broad `city budget` topic (`189`). That revived the citywide budget briefing and made it appear important even though the agenda item likely refers to the commission's own room-tax/tourism budget.

The core defect is scope confusion: generic agenda terms such as `budget`, `policy`, `update`, or `review` are being interpreted as citywide concerns without enough regard for the meeting body discussing them.

## Goals

1. Make topic extraction and related AI analysis account for the committee/body context before reusing broad citywide topics.
2. Surgically reanalyze meeting `216` and all downstream topic summaries/headlines/briefings for topics linked before or after reanalysis.
3. Verify whether the prompt/context fix and reanalysis remove topic `189` from the homepage. Only add a homepage guardrail if verification proves it is still necessary.

## Non-goals

- Do not broadly scan or repair unrelated historical meetings in this pass.
- Do not change homepage ranking unless the post-reanalysis verification still fails.
- Do not suppress legitimate citywide budget activity when a meeting/document clearly concerns the General Fund, tax levy, citywide budget, or City Council budget adoption.

## Design

### 1. Committee-scoped extraction context

`ExtractTopicsJob` will pass explicit meeting context into `Ai::OpenAiService#extract_topics`, including:

- `body_name`
- meeting date
- a short instruction that agenda terms must be interpreted within the body's jurisdiction unless documents clearly broaden the scope

The `extract_topics` prompt template will add a binding scope rule:

- First determine what the meeting body normally governs.
- Treat generic items like `budget review`, `policy update`, `director update`, `treasurer report`, and `program update` as body-scoped by default.
- Reuse a broad citywide topic only when the item or attached documents explicitly mention citywide concepts such as General Fund, tax levy, all fund budgets, citywide services, City Council adoption, city budget, or a citywide budget amendment.
- For Room Tax Commission, `budget review` should normally mean room-tax/tourism budget, not the overall city budget.
- If scope is ambiguous and the item is generic, prefer a narrower/body-scoped topic or mark it not topic-worthy rather than linking to a broad canonical topic.

### 2. Tests

Add regression coverage around the extraction prompt/context path:

- Verify the extraction prompt receives the meeting body context.
- Verify the prompt includes the body-scoped interpretation rule.
- Add a Room Tax Commission `BUDGET REVIEW` scenario showing it should not be treated as the canonical `city budget` topic unless citywide budget evidence is present.

### 3. Surgical reanalysis workflow for meeting 216

After #1 is implemented and tested, run a surgical repair for meeting `216`:

1. Capture current topic links for all substantive agenda items in meeting `216`.
2. Clear existing topic links for those agenda items.
3. Rerun topic extraction for meeting `216`.
4. Capture new topic links.
5. Compute the affected topic set as `before_topic_ids ∪ after_topic_ids`.
6. Rerun per-meeting topic summaries for affected topics that still have meeting `216` links.
7. Remove stale meeting `216` summaries for topics no longer linked to meeting `216`.
8. Rerun topic headline/briefing generation for every affected topic so homepage/topic pages reflect the corrected links.
9. Recompute continuity for affected topics if links changed, so `last_activity_at` and lifecycle status reflect the corrected appearances.

The workflow should report before/after links so the repair is auditable.

### 4. Homepage verification gate

After #1 and #2:

- Run the homepage selector and `HomeController` topic queries.
- Confirm topic `189` is not selected for top stories or wire cards/rows.

Only if topic `189` still appears after corrected extraction and downstream reanalysis should we implement a homepage guardrail. Any guardrail must be narrowly targeted at stale or body-scoped false recency, not a broad suppression of budget topics.

## Verification

- Run targeted tests for topic extraction and any changed jobs/services.
- Run the surgical reanalysis against meeting `216`.
- Inspect before/after topic links for meeting `216`.
- Verify topic `189` is not linked to agenda item `3029` unless the new extraction finds explicit citywide budget evidence.
- Verify topic `189` is absent from homepage selection after reanalysis.
