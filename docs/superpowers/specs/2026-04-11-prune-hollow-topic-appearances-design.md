# Prune Hollow Topic Appearances

**Date:** 2026-04-11
**Status:** Proposed

## Problem

Topics are being promoted to the homepage based on recurring standing-agenda placeholders that contain no substantive discussion. The motivating case is `/topics/513` ("garbage and recycling service changes"):

- 8 appearances, `resident_impact_score = 4` (eligible for top stories)
- 7 of the 8 map to the same monthly PUC agenda slot: "SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED"
- What the minutes actually say under that slot each month:
  - Jan 2026: a resident reported a garbage-sticker purchasing issue; staff will look into it
  - Feb 2026: leaf collection totals exceeded previous years; no final figures yet
  - Mar 2026: preparation of the WDNR Solid Waste grant report is underway
- No motions, no votes, no decisions, no public input on any of these appearances

The topic name is a lie. Nothing about garbage and recycling service is actually changing. The system counts each "as needed" placeholder as a civic-concern signal, accumulates 8 of them, and pushes the topic onto the front page.

The same failure mode exists in other standing agenda slots that appear in subcommittees month after month: Director Updates, Administrator's Report, Any Other Items, Council Communications, etc.

## Goals

1. Stop counting hollow recurring-placeholder appearances as evidence of civic activity
2. Clean up existing phantom topics (like 513) that were promoted on false signals
3. Preserve the ability for the same agenda slot to surface a real decision when one occurs — never block slots or names outright
4. Prefer signals already computed by the pipeline over new AI calls

## Non-Goals

- Changing how topics are extracted in the first place (pass 1 of `ExtractTopicsJob`)
- Changing topic naming precision
- Regenerating all historical meeting summaries (too expensive, too slow)
- Blocking standing-slot titles or topic names (loses future real decisions)

## Design

### Overview

Two complementary paths:

1. **Going forward** — A new `activity_level` field is added to each `item_details` entry in `MeetingSummary.generation_data`. A new `PruneHollowAppearancesJob` runs at the end of `SummarizeMeetingJob` and detaches hollow `AgendaItemTopic` rows using that field plus existing motion/public-input data. Affected topics are re-scored and re-lifecycled.
2. **One-time backfill** — A rake task applies a conservative rule-based heuristic to existing data (using `item_details` structure, not re-running AI) to clean up historical hollow appearances.

Both paths use the same pruning primitive (`AgendaItemTopic.destroy`) and the same post-prune topic-demotion rules.

### Part 1: Prompt Tweak to `analyze_meeting_content`

Add a new required field to each entry in the `item_details` array:

```json
{
  "agenda_item_title": "...",
  "summary": "...",
  "vote": null,
  "decision": null,
  "public_hearing": null,
  "citations": [...],
  "activity_level": "decision" | "discussion" | "status_update"
}
```

**Classification definitions (to include in the prompt):**

- **`decision`** — A motion, vote, formal action, approval, adoption, or binding commitment occurred, or a public hearing was held on this item.
- **`discussion`** — Substantive conversation, deliberation, or public input occurred, or the item has clear forward-looking implications (a commitment to follow up, a policy question still to resolve, a deadline or dependency that residents would want to track) — even if no formal vote took place. This is the normal category for informal subcommittee work.
- **`status_update`** — Routine informational report only: numbers reported, operations status, "nothing new," or an acknowledgment with no decisions and no forward-looking significance. These are the items a resident could safely skip.

The prompt should emphasize that when in doubt, `discussion` is the safer call — `status_update` is only for items where there is genuinely nothing for a resident to act on, follow, or care about.

**Files changed:**

- `lib/prompt_template_data.rb` — update the seed for `analyze_meeting_content`
- `db/seeds/prompt_templates.rb` — ensure re-seed handles the new field
- Live prompt in `PromptTemplate` (key: `analyze_meeting_content`) — updated via the admin UI or a data migration, since seeds don't overwrite edited prompts

The existing `generation_data` JSON on old `MeetingSummary` records will not have `activity_level`. The pruning job treats missing `activity_level` as "unknown — do not prune" in the going-forward path. The backfill path handles these records separately.

### Part 2: `PruneHollowAppearancesJob` (Going Forward)

A new job enqueued by `SummarizeMeetingJob` after the summary and its `generation_data` are persisted. Takes `meeting_id` as its only argument.

**Job flow:**

1. Load the meeting and its most recent `MeetingSummary`. Return early if no `generation_data` or `item_details` is missing.
2. Detect whether this is a new-format summary: `new_format = item_details.any? { |entry| entry.key?("activity_level") }`. If `new_format` is false, return early — this is an old summary and cleanup is the backfill's responsibility.
3. Build a map from `agenda_item_id` → `item_details` entry, by fuzzy-matching `agenda_item_title` against `AgendaItem.title` for each item on the meeting (normalize both: strip leading numbering like `"10."`, strip trailing `"AS NEEDED"` / `"IF APPLICABLE"`, lowercase, squish). An agenda item with no matching `item_details` entry on a new-format summary is treated as procedural (already filtered by the AI) and is eligible for pruning.
4. For each `AgendaItemTopic` on this meeting's agenda items, evaluate the hollowness rule (below). If hollow, destroy the row.
5. Collect the set of affected `topic_id`s, apply topic-demotion rules (below), and enqueue `GenerateTopicBriefingJob` for each affected topic (it will recompute `resident_impact_score`).

**Hollowness rule (going forward, new-format summaries only) — prune iff ALL are true:**

- No `Motion` row exists with `agenda_item_id = ai.id`
- One of:
  - The agenda item has no matching `item_details` entry (AI filtered it as procedural), OR
  - The matching `item_details` entry has ALL of: `activity_level == "status_update"`, `vote == null`, `decision == null`, `public_hearing == null`

**Why each check:**

- Motion check catches the case where `ExtractVotesJob` linked a formal action the AI summary may have under-emphasized
- `activity_level == "status_update"` is the primary signal
- `vote`/`decision`/`public_hearing` nulls are belt-and-suspenders: if the AI labels something `status_update` while simultaneously recording a vote or a public hearing, trust the structured field over the label

**Why skip old-format summaries entirely:** Without `activity_level`, "missing entry" is ambiguous — it could mean the item was procedurally filtered (prune-eligible) or it could mean the old summary schema didn't emit the entry (unknown — don't prune). Rather than adding heuristics to the going-forward path, old summaries are the backfill rake task's job.

### Part 3: Topic Demotion Rules

After pruning, for each affected topic, apply one rule based on remaining `TopicAppearance` count:

| Remaining appearances | Action |
|---|---|
| `0` | `status = "blocked"`, `lifecycle_status = "dormant"`. Keeps the name in the topic table to prevent re-creation; admin can unblock if desired. |
| `1` | `lifecycle_status = "dormant"`. Stays approved but won't surface on homepage (single isolated appearance is not a recurring concern). |
| `2+` | Leave `status` and `lifecycle_status` alone. Enqueue `GenerateTopicBriefingJob` to let the AI re-rate `resident_impact_score` against the cleaned appearance set. |

**Respect admin overrides:** If `resident_impact_overridden_at` is within the override window (180 days), do not enqueue briefing regeneration — the admin score is protected. Still apply appearance pruning and lifecycle changes.

**Audit trail:** Create a `TopicStatusEvent` row for each demotion describing the pruning source (`"hollow_appearance_prune"` or `"hollow_appearance_backfill"`) with the number of appearances removed.

### Part 4: Backfill Rake Task

A one-time rake task: `bin/rails topics:prune_hollow_appearances` (idempotent — safe to re-run).

**Approach:** Use existing `MeetingSummary.generation_data` structure plus agenda item title patterns. No AI calls. No regeneration.

**For each `AgendaItemTopic` in the database:**

1. Find the meeting's most recent `MeetingSummary`. If none, skip.
2. Look up the matching `item_details` entry by fuzzy-matching `agenda_item_title` against the `AgendaItem.title` (same normalization as the going-forward job).
3. Determine if this appearance is a **standing-slot candidate** — true if ANY of:
   - Normalized `AgendaItem.title` matches a known standing-slot pattern (initial seed list below; expandable)
   - The same normalized title repeats 3 or more times across this topic's appearances (auto-detects standing slots we didn't enumerate)
4. If not a standing-slot candidate, skip (conservative — preserve unusual but potentially real appearances).
5. If it is a candidate, confirm hollowness — prune iff ALL are true:
   - No `Motion` linked to this agenda item
   - Matching `item_details` entry (if present) has `vote == null` AND `decision == null` AND `public_hearing == null`
   - Either no `item_details` entry exists, OR the entry's `summary` text is under 600 characters AND contains none of: `motion`, `seconded`, `carried`, `adopted`, `approved`, `ayes`, `nays`, `public hearing`, `resolution`, `ordinance`

The 600-char threshold and keyword list are the backfill-specific belt-and-suspenders that substitute for the `activity_level` signal we don't have on old data.

**Initial standing-slot pattern list (case-insensitive, normalized):**

```
updates and action
director update
director's report
directors report
administrator's report
administrators report
chief's report
chiefs report
any other items
any other matters
council communications
communications
public comment                 # only when no specific item is named
citizens' comments
open forum
```

(Seed list; can be extended as we find more.)

**Execution:** The rake task groups pruning by topic, then applies the same demotion rules as the going-forward job, then enqueues `GenerateTopicBriefingJob` for each surviving affected topic. Logs a per-topic summary of what was pruned.

**Dry-run mode:** Support `DRY_RUN=1` to print the set of appearances that would be pruned without actually destroying anything. Useful for reviewing the first pass before committing.

### Part 5: Score Recomputation

After pruning, affected topics with `2+` remaining appearances get `GenerateTopicBriefingJob.perform_later`. That job already re-runs `analyze_topic_briefing`, which calls `update_resident_impact_from_ai`. Nothing new needs to be built. Topics with `0` or `1` remaining appearances have their lifecycle changed directly and do NOT get a briefing regeneration (nothing meaningful left to brief about).

## Edge Cases and Decisions

- **The 2025-07-07 City Council appearance on topic 513** is linked to "COUNCIL COMMUNICATIONS" — a different slot at a higher-tier body. It should also be pruned by the same rules; "COUNCIL COMMUNICATIONS" is in the standing-slot pattern list and has no motions or decisions in the minutes for this item.
- **An item with discussion but no decision in an informal subcommittee** — gets labeled `discussion` by the AI, survives pruning, fine.
- **A standing-slot item that one month contains a real vote** — the motion check rescues it. Even if the AI mis-labels the `activity_level`, the linked motion blocks pruning.
- **`ExtractTopicsJob` re-runs when minutes arrive and re-creates a pruned `AgendaItemTopic`** — Possible. Pruning runs after `SummarizeMeetingJob`, which runs after `ExtractTopicsJob`, so a re-prune would catch it on the same pipeline pass. If a future minutes re-run recreates the row, the next `PruneHollowAppearancesJob` will detach it again. Idempotent. The alternative (recording a "pruned" marker to prevent recreation) would require a new table and isn't worth it for idempotency we already get.
- **Topics with all appearances pruned to zero** — blocking prevents re-creation via the existing topic blocklist machinery. If a topic genuinely becomes real later under the same name, an admin can unblock.
- **Admin protection** — `resident_impact_overridden_at` inside the 180-day window protects impact score from the briefing rerun. Appearance pruning and lifecycle changes still apply — admins override scores, not appearances.

## Testing

**Unit / model tests:**
- `AgendaItemTopic` destruction cascades to `TopicAppearance` (verify existing `dependent: :destroy` on the has_many through the reverse path — or handle explicitly in the job if it doesn't)

**Job tests (`PruneHollowAppearancesJob`):**
- Prunes an appearance when `activity_level == "status_update"` and no motions/public input
- Preserves an appearance when `activity_level == "discussion"` even with no motions
- Preserves an appearance when a motion is linked even if `activity_level == "status_update"`
- Preserves an appearance when `activity_level` is missing (old summary)
- Preserves an appearance when `public_hearing` is non-null
- Demotes a topic to `blocked + dormant` when pruning drops it to 0 appearances
- Demotes a topic to `dormant` when pruning drops it to 1 appearance
- Leaves topic alone and enqueues briefing regeneration when pruning drops it to 2+ appearances
- Respects `resident_impact_overridden_at` window — does not enqueue briefing regeneration inside the window
- Creates a `TopicStatusEvent` audit row per demotion

**Rake task tests:**
- Backfill prunes topic 513's 8 hollow appearances in a fixture-loaded scenario
- Backfill does NOT prune an appearance for a standing-slot title that happens to contain a motion
- Backfill respects `DRY_RUN=1` and does not write anything
- Backfill re-run is idempotent (no-op second pass)

**Integration test:**
- Feed a realistic PUC minutes fixture through `SummarizeMeetingJob`, verify the "SOLID WASTE UTILITY: UPDATES AND ACTION" appearance is detached at the end of the pipeline

## Files to Create or Modify

**New files:**

- `app/jobs/prune_hollow_appearances_job.rb` — the job
- `lib/tasks/topics.rake` — append `prune_hollow_appearances` task (or new file if cleaner)
- `test/jobs/prune_hollow_appearances_job_test.rb`
- `test/lib/tasks/topics_prune_hollow_appearances_test.rb` (or wherever rake task tests live)

**Modified files:**

- `lib/prompt_template_data.rb` — update `analyze_meeting_content` prompt to include `activity_level` field and classification definitions
- `db/seeds/prompt_templates.rb` — keep in sync
- `app/jobs/summarize_meeting_job.rb` — enqueue `PruneHollowAppearancesJob.perform_later(meeting_id)` after summary is persisted
- `app/services/ai/open_ai_service.rb` — if any schema validation on `item_details` structure exists (spot check), update it to expect `activity_level`
- Tests for `summarize_meeting_job` — update fixtures/mocks to include the new field
- `docs/DEVELOPMENT_PLAN.md` — add brief note about the pruning step in the pipeline flow
- `CLAUDE.md` — append a note under "Pipeline: Topic → Homepage Cards" explaining the pruning step

## Rollout

1. Land the prompt template update first (deploy the new `activity_level` definition to production via data migration or admin UI edit).
2. Land `PruneHollowAppearancesJob` and wire it into `SummarizeMeetingJob`. Going-forward meetings will have the field and be pruned cleanly.
3. Run the backfill rake task in `DRY_RUN=1` mode first. Review the list of appearances it would prune. Commit.
4. Run the backfill for real.
5. Verify topic 513 (and any other phantom topics) are no longer on the homepage.

## Open Questions

None remaining at spec time. Implementation plan will surface the usual detail-level questions (exact normalization regex, fuzzy-match threshold for title matching, whether `TopicStatusEvent` has the fields we need or requires migration).
