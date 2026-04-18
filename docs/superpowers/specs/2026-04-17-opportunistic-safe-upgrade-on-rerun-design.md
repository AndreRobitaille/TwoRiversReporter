# Opportunistic Safe Upgrade on Rerun — Design

**Date:** 2026-04-17
**Status:** Draft
**Related:** GitHub issue #101 (`Track legacy tech debt from mixed-mode agenda structure rollout`); `2026-04-17-safe-mixed-mode-agenda-reruns-design.md`

## Problem

Historical meetings are currently acceptable in their existing mixed/legacy shape. The operational risk is not that they remain legacy forever; the risk is that when a new document arrives later — especially minutes or a transcript — a rerun/reanalysis path may damage existing agenda, topic, motion, or vote relationships.

We do **not** want a broad historical normalization pass. Full reprocessing is expensive, and many historical meetings are "good enough" today.

What we want instead is a meeting-scoped behavior:

- if an old meeting never reruns, leave it alone
- if an old meeting reruns because new source material arrived, try to safely upgrade that one meeting to the better structured agenda shape
- if the upgrade cannot be done safely, fail closed and preserve the current meeting state rather than damaging it

## Goals

- Protect already-okay historical meetings from being damaged by future reruns.
- Opportunistically upgrade a meeting's agenda structure only when that meeting is rerun because of newly arrived source material.
- Preserve existing `agenda_item` IDs and downstream links whenever possible.
- Fail closed on ambiguous upgrade cases instead of guessing.
- Keep the scope meeting-local and event-driven rather than introducing any blanket backfill.

## Non-Goals

- Performing a global historical cleanup.
- Forcing all historical meetings into the new agenda structure immediately.
- Requiring a manual repair workflow for every old meeting before new documents can be ingested.
- Solving every legacy mixed-mode inconsistency in this change.

## Recommended approach

Use **opportunistic safe upgrade on rerun** as the default behavior for historical meetings.

That means:

1. A historical meeting stays in its current shape until a rerun event happens.
2. A rerun event caused by newly arrived source material attempts a safe structural upgrade for that one meeting.
3. The upgrade only proceeds if reconciliation is unambiguous and non-destructive.
4. If reconciliation is not safe, the meeting remains in its prior legacy shape and the rerun path does not damage its existing data.

This sits between two bad extremes:

- **too passive:** never upgrade anything, leaving fragile legacy behavior forever
- **too aggressive:** always restructure old meetings whether or not the data can be matched safely

## Rerun trigger model

The safe-upgrade logic is only relevant when a meeting is actually being rerun because a new document has arrived or a deliberate reanalysis has been requested.

Typical triggers include:

- minutes PDF arrives for a previously agenda/packet-only meeting
- transcript arrives after the meeting
- another newly discovered meeting document causes reanalysis of the meeting pipeline

If none of those happen, historical meetings remain untouched.

## Architecture

### A. Base rule: preserve before improving

The rerun path must prioritize not breaking existing data over improving structure.

That means the system should attempt to reuse existing substantive `agenda_items` first and only restructure when it can do so while preserving identity and downstream references.

### B. Safe opportunistic upgrade conditions

During a meeting rerun, the system may upgrade a legacy/mixed meeting toward the structured shape only if all of the following are true:

1. Existing substantive rows can be matched to parsed candidates with high confidence.
2. Structural parent/child relationships can be assigned without ambiguity.
3. Existing downstream records remain valid against the preserved agenda item IDs:
   - `motions`
   - `agenda_item_topics`
   - `topic_appearances`
   - `agenda_item_documents`
4. The upgrade does not require destructive replacement of substantive agenda rows.

If those conditions hold, the rerun may safely transform the meeting from legacy-flat toward structured.

### C. Fail-closed behavior

If the meeting cannot be upgraded safely during rerun:

- do not destroy or replace the existing agenda rows
- do not guess at ambiguous matches
- do not partially upgrade the meeting into a mixed broken state
- leave the meeting in its prior usable legacy shape

This is a deliberate trade-off. A missed upgrade is acceptable; corrupted civic data is not.

### D. Scope of upgrade during rerun

The upgrade should be **meeting-scoped and opportunistic**, not a generalized cleanup workflow.

The normal rerun path should only do the minimum necessary to:

- preserve stable item identity
- add section/parent structure when it can be inferred safely
- allow new downstream analyses (votes, summaries, topics) to run against the improved structure for that meeting

It should not attempt to solve historical debt across unrelated meetings.

## Behavioral contract

### Historical meetings with no new documents

No change. Leave them alone.

### Historical meetings with a new rerun-triggering document

Attempt safe upgrade for that one meeting.

Possible outcomes:

1. **Safe upgrade succeeds**
   - the meeting now has improved structure
   - downstream jobs can use the improved structure
   - prior links remain valid

2. **Safe upgrade is not possible**
   - the meeting stays in its prior legacy shape
   - no destructive damage occurs
   - the system may continue using legacy-compatible downstream behavior for that meeting

### Newly parsed meetings

Continue using the structured forward path. This design is about historical meetings that later rerun.

## Risks and mitigations

| Risk | Mitigation |
|------|-----------|
| Safe-upgrade logic guesses wrong on a historical meeting. | Require unambiguous matching; fail closed on doubt. |
| A rerun partially upgrades some rows before erroring. | Keep the upgrade atomic per meeting using locking + transaction boundaries. |
| Old meetings never get improved structure. | Acceptable. This change optimizes for protection first, upgrade second. |
| Engineers later assume all old meetings were upgraded. | Document explicitly that upgrades are opportunistic and event-driven only. |
| New documents arrive but the rerun path never attempts structural improvement. | Wire the relevant rerun entry points so new-document analysis uses the safe-upgrade-capable path. |

## Testing

Required behavior to verify:

- A historical meeting with legacy-flat agenda rows can rerun safely when a new document arrives.
- If parsed candidates match cleanly, that meeting upgrades to structured parent/child rows without breaking downstream links.
- If matching is ambiguous, the meeting remains unchanged.
- Existing motions, topic appearances, topic links, and document links survive the rerun.
- Historical meetings with no rerun-triggering event remain untouched.

## Rollout intent

This design is explicitly **not** the final historical cleanup strategy.

If the opportunistic rerun path works, issue #101 should be updated to clarify the remaining debt:

- some historical meetings may still never upgrade unless a rerun event occurs
- full historical normalization remains a separate future decision
- legacy compatibility paths may still be needed until or unless a broader cleanup is chosen

## Decision summary

- **Default stance toward historical meetings:** leave them alone.
- **When new documents arrive later:** attempt a safe meeting-scoped upgrade during rerun.
- **If safe:** upgrade that one meeting.
- **If not safe:** preserve the current meeting state and fail closed.
- **Global historical cleanup:** still deferred.
