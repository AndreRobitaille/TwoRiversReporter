# Broad Topic Prevention + Cleanup

## Date: 2026-02-28

## Problem

The extraction pipeline creates overly-broad "process category" topics
like "zoning" that aggregate unrelated civic concerns. The "zoning" topic
currently has 26 agenda items spanning conditional use permits, rezoning
requests, fence setback ordinances, land sales, BID boundaries, and
development planning. When the briefing pipeline tries to summarize all
26 as one narrative, it produces vague, unhelpful output like "Zoning
keeps bouncing between boards. Lots of talk, few clear finishes."

### Root Causes

1. **The extraction prompt lists `Zoning` as a category**, and the AI
   often reuses category names as topic tags. Once "zoning" exists in
   the `existing_topics` list, the prompt's "prefer existing topics"
   instruction funnels every zoning-adjacent item into it.

2. **The briefing pipeline can't handle broad topics.** It assembles
   context from only 3 recent meetings + compressed prior analyses.
   For a topic spanning 26 items across 5 governing bodies, the AI
   can't identify coherent patterns and falls back on vague
   characterizations.

3. **Cross-body movement gets mischaracterized.** Normal
   committee→council flow (Plan Commission reviews, then Council
   approves) looks like "bouncing between boards" when aggregated
   across unrelated items. The prompt already instructs against this,
   but the data noise overwhelms the instruction.

## Design

### Principle

From TOPIC_GOVERNANCE.md: "Topics are long-lived civic concerns that may
span multiple meetings, multiple bodies, and extended periods of time."

A topic must be specific enough to tell a coherent story. Process
domains (Zoning, Infrastructure, Finance) are not topics — they contain
dozens of unrelated concerns. But not every item within a process domain
deserves its own topic either. Many are routine one-off actions that
aren't topic-worthy at all.

**Granularity target:** "neighborhood conversation" level. Good:
"conditional use permits", "fence setback rules", "downtown
redevelopment". Bad: "zoning" (too broad), "123 Main St survey map"
(too narrow). Not topic-worthy: one-off procedural actions with no
recurring significance.

### Part 1: Extraction Prompt Refinement

Add a `<topic_granularity>` section to the `extract_topics` prompt in
`Ai::OpenAiService`:

- Explicitly state that **category names are not valid topic names**.
  The category field already captures the domain — the topic tag must
  name the specific civic concern.
- Give concrete examples of good granularity vs. too-broad vs.
  too-narrow.
- Reinforce that `topic_worthy: false` is the correct classification
  for routine one-off items (a single plat review, a standard survey
  map approval).

The existing category enum in the extraction spec stays as-is — it's
useful for classification. The change is preventing the AI from copying
category names into the `tags` array.

### Part 2: TopicBlocklist Additions

Add the extraction category names to the existing `TopicBlocklist`
table so `FindOrCreateService` rejects them even if the AI slips:

- zoning
- infrastructure
- public safety
- finance
- governance
- personnel
- parks & rec (and variants)
- licensing

These are already admin-managed via the existing blocklist UI, so
admins can adjust without code changes. The rake task (Part 3) will
add them programmatically as a one-time seed.

### Part 3: Selective Re-Extraction of "Zoning" Items

A rake task (`topics:split_broad_topic`) that:

1. Takes a topic name (e.g., "zoning") as an argument
2. Finds all `AgendaItemTopic` links for that topic
3. For each linked agenda item, sends it through the **updated**
   extraction prompt with full document context
4. The AI returns either:
   - A specific topic name → created as `proposed`, normal triage
   - `topic_worthy: false` → the "zoning" link is removed, no new
     topic created
5. After processing, the old broad topic has 0 remaining links
6. Admin reviews new proposed topics via existing triage queue
7. Admin can then block/delete the emptied "zoning" topic

**Expected outcome for current "zoning" (26 items):** ~8-10 get
specific topics (conditional use permits, fence setback rules, downtown
redevelopment, etc.), ~16 are marked not topic-worthy. Fewer, better
topics — not more noise.

### Part 4: Briefing Regeneration

After re-extraction and triage, queue `GenerateTopicBriefingJob` for
newly-created topics. The briefing pipeline works well for focused
topics — the problem was never the prompts, it was the input data.

Cross-body characterization ("bouncing between boards") will be
revisited after seeing results. Hypothesis: with focused topics, normal
committee→council flow won't look like "bouncing" because there are
only 2-3 appearances, not 26.

## What This Does NOT Change

- Briefing pipeline (prompts, context assembly, two-pass architecture)
- Topic schema (no new columns or tables)
- `CATCHALL_TOPIC_NAMES` mechanism (stays for post-hoc ordinance
  section refinement — a different pattern)
- Triage pipeline (AutoTriageJob handles new proposed topics normally)

## Files to Modify

| File | Change |
|------|--------|
| `app/services/ai/open_ai_service.rb` | Add `<topic_granularity>` section to `extract_topics` prompt |
| `lib/tasks/topics.rake` | Add `topics:split_broad_topic` rake task |
| `lib/tasks/topics.rake` | Add `topics:seed_category_blocklist` rake task |
| `app/services/ai/open_ai_service.rb` | Add `re_extract_single_item` method (or reuse `extract_topics` for single items) |

## Risks

- **AI still creates broad names**: Mitigated by `TopicBlocklist` guard
  in `FindOrCreateService`. Even if the prompt fails, the blocked name
  won't be created.
- **Re-extraction creates noise**: Mitigated by allowing `topic_worthy:
  false` — items can be explicitly marked as not topic-worthy instead
  of forced into new topics. Also mitigated by normal triage pipeline.
- **Losing valid "zoning" associations**: The re-extraction preserves
  all original agenda item links. Items that get new specific topics
  keep their meeting/document associations. Items marked not
  topic-worthy were noise anyway.

## Open Questions

- Should we proactively scan for other broad topics beyond "zoning"?
  (Could check topics with high appearance counts + low content
  coherence.) Defer to after initial results.
- Should the extraction prompt also block "zoning" variants (e.g.,
  "zoning changes", "zoning issues")? The blocklist handles exact
  matches; the prompt should handle semantic variants.

## Migration Plan Item #7 Disposition

The original migration plan item "Topic pages: empty/error/low-signal
states (QA checklist)" was about handling topic pages that have
incomplete data (no briefing, no appearances, failed AI generation).
This work partially addresses the "low-signal" case — broad topics
that produce vague summaries. The empty/error states remain as a
separate concern for future QA work, but are lower priority since
they're edge cases rather than systematic quality problems.
