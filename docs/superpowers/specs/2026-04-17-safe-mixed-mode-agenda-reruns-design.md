# Safe Mixed-Mode Agenda Reruns — Design

**Date:** 2026-04-17
**Status:** Draft
**Related:** GitHub issue #101 (`Track legacy tech debt from mixed-mode agenda structure rollout`); production risk discovered while investigating meeting 173 (`Advisory Recreation Board Meeting`, 2026-04-15), where reparsing structured agenda rows exposed foreign key failures and unsafe downstream ID churn.

## Problem

The current mixed-mode agenda rollout is correct in direction but unsafe in operation.

`Scrapers::ParseAgendaJob` currently destroys all `meeting.agenda_items` and recreates them from the latest parsed structure. That is safe only for meetings with no downstream links. It is unsafe once a meeting has already produced any of the following:

- `agenda_item_topics`
- `topic_appearances`
- `agenda_item_documents`
- `motions`
- meeting summary `item_details` / citations
- topic briefing context derived from agenda item IDs

In practice, this means a routine rerun caused by a newly arrived document — for example minutes appearing after an agenda, packet, or transcript has already been processed — can fail or detach data if the agenda parse path runs destructively.

This is not just a bug for meeting 173. It is a production safety problem in the mixed-mode pipeline.

## Goals

- Make normal agenda reruns safe for already-processed meetings.
- Preserve existing `agenda_item` IDs whenever possible so downstream links remain valid.
- Allow new documents such as minutes to trigger reruns without requiring a full historical backfill.
- Keep the mixed-mode rollout compatible with legacy meetings that still have `kind = nil` agenda rows.
- Avoid blanket reprocessing of historical meetings; full reruns are expensive (about $55 each) and should only happen when explicitly needed.
- Provide a deliberate repair path for historically bad meetings like 173 without making that expensive path part of every routine rerun.

## Non-Goals

- Performing a global historical agenda normalization/backfill now.
- Requiring all old meetings to become structured before they can continue rendering or updating.
- Replacing the mixed-mode compatibility contract established in issue #101.
- Redesigning topic extraction, summary prompts, or vote extraction beyond what is necessary to keep reruns safe.

## Recommended approach

Use a **hybrid design**:

1. **Normal parsing becomes non-destructive and ID-preserving.**
   - This is the default path used by routine ingestion and reruns.
   - It must be safe when a meeting already has linked topics, motions, summaries, or briefings.

2. **Historical restructuring becomes a separate guarded repair path.**
   - This is used only when a meeting genuinely needs structural correction.
   - It is not triggered automatically for every old meeting.
   - It is appropriate when a meeting like 173 needs a one-time fix because newly discovered source material or a targeted repair justifies the cost and risk.

This design protects normal operations while isolating risky legacy cleanup.

## Architecture

### A. Safe normal rerun path

`Scrapers::ParseAgendaJob` must stop treating `agenda_items` as disposable parser output.

Instead, each run should:

1. Parse the latest agenda structure into an in-memory candidate list.
2. Match parsed candidates to existing `agenda_items` for the meeting using strong identity rules.
3. Update matched rows in place.
4. Create rows only for clearly new items.
5. Leave referenced rows in place if matching is ambiguous rather than deleting/rebuilding them.

The parser becomes an **agenda reconciliation job**, not a destructive rebuild job.

### B. Matching rules for in-place reconciliation

Matching should be conservative and deterministic.

For structured/new rows, the preferred identity is:

- meeting
- normalized item number
- normalized title
- parent/section context
- relative order as a tie-breaker

For legacy flat rows (`kind = nil`), matching should treat them as substantive rows unless proven otherwise, consistent with issue #101.

If a parsed row cannot be matched confidently:

- create a new row only if it is clearly additive and does not conflict with an existing substantive row, or
- abort the destructive part of the rerun and flag the meeting for explicit repair if the ambiguity could cause wrong attribution.

The system should prefer a safe no-op over a risky remap.

### C. Parser-owned vs downstream-owned fields

Normal reruns may update only parser-owned fields on `agenda_items`, such as:

- `number`
- `title`
- `kind`
- `parent_id`
- `order_index`
- `summary`
- `recommended_action`

Normal reruns must not directly destroy or replace:

- `motions`
- `agenda_item_topics`
- `topic_appearances`
- `agenda_item_documents`
- meeting summaries
- topic briefings

Those downstream artifacts may be refreshed later by their own jobs, but their agenda item references must stay valid.

### D. Safety gates before any mutation

Before mutating a meeting's agenda rows, the rerun path must enforce these gates:

1. **No blind delete/recreate** of substantive `agenda_items`.
2. **Stable matching required** before in-place update.
3. **Ambiguity aborts automatic structural conversion** instead of guessing.
4. **Per-meeting transaction** so partial reconciliation cannot leave a meeting half-updated.
5. **Per-meeting lock** so parse/extract/summarize jobs cannot race.
6. **Source fingerprint no-op** when the agenda source has not materially changed.

These rules are what make minutes-triggered reruns safe.

### E. Separate historical repair path

Some meetings already contain the wrong shape of data or have motions/topics linked to structural headers. Those meetings need more than safe rerun reconciliation.

Add a dedicated repair service/job for targeted historical normalization.

That repair path should:

1. Parse the desired structured agenda.
2. Build an explicit old→new agenda item mapping.
3. Relink dependent records deliberately where safe:
   - `agenda_item_topics`
   - `topic_appearances`
   - `agenda_item_documents`
   - `motions`
4. Refresh downstream derived artifacts after relinking:
   - topic extraction where needed
   - meeting summary item-details/citations where needed
   - topic briefings/continuity where needed
5. Only remove obsolete rows after all dependent references have been migrated successfully.

This path should be used only when:

- a new authoritative document appears and the meeting truly needs structural repair,
- an operator explicitly requests repair for that meeting, or
- a broader intentional reprocessing event is approved for another reason.

It should not run automatically across the historical corpus.

## Operational behavior after this change

### Future meetings

For newly ingested meetings, agenda parsing should be safe to rerun repeatedly as documents arrive. If minutes appear later, the meeting should be able to rerun without taking down the meeting page or invalidating topic/vote links.

### Existing mixed-mode meetings

Most old meetings should continue working without forced normalization.

If they already have stable legacy rows and no urgent reason to restructure them, routine document-triggered reruns should avoid destructive agenda replacement and preserve the current data shape.

### Expensive full reruns

Because a full backfill/reprocess costs about $55, the system must not assume global replay is acceptable.

The design therefore treats historical repair as **meeting-scoped and opt-in**, not a default maintenance strategy.

## Risks and mitigations

| Risk | Mitigation |
|------|-----------|
| Normal reruns still delete agenda rows indirectly through old logic. | Remove `destroy_all` behavior from the routine parse path first. |
| Matching logic chooses the wrong existing row and silently corrupts links. | Use strong matching rules; if ambiguous, abort and require explicit repair. |
| Concurrent jobs race when minutes/agenda/topic extraction all fire near the same time. | Add a per-meeting lock and transaction boundary around agenda reconciliation. |
| Legacy meetings remain inconsistent forever. | Accept this temporarily; provide a separate repair path and only use it where justified. |
| Historical repair becomes too expensive to run broadly. | Make it explicit and meeting-scoped; do not automatically full-backfill. |
| Downstream summaries/briefings cite stale item context after repair. | Treat downstream refresh as part of the explicit repair workflow, not the normal rerun path. |

## Testing

### New tests for safe normal reruns

- `ParseAgendaJob` does not destroy and recreate agenda rows for a meeting with existing downstream references.
- A meeting with `topic_appearances` linked to an agenda item can rerun parsing without foreign key failure.
- A meeting with linked `motions` can rerun parsing without losing `agenda_item_id` links when the matched row is the same substantive item.
- A meeting with `agenda_item_documents` keeps those links after a normal rerun.
- An ambiguous match aborts safely and leaves existing data unchanged.
- A no-op rerun occurs when the agenda source fingerprint has not changed.

### New tests for the guarded repair path

- A targeted repair can migrate references from a legacy structural header or legacy flat row to the correct structured child row.
- Dependent rows are relinked before obsolete agenda rows are removed.
- A repair failure rolls back cleanly.

### Regression verification

- Existing structured parsing tests still pass.
- Existing vote extraction tests still pass.
- Existing topic extraction behavior for legacy meetings remains compatible.

## Rollout order

1. Remove destructive delete/recreate behavior from the normal parse path.
2. Implement in-place agenda reconciliation with stable matching and ambiguity aborts.
3. Add per-meeting locking / transaction protection for reruns.
4. Add regression tests covering meetings with downstream references.
5. Introduce the explicit historical repair path.
6. Use that repair path for meeting 173 and any other specifically justified meeting.
7. Update issue #101 with the newly discovered rerun/relinking constraint.

## Open questions (to settle during implementation planning)

- What exact agenda-source fingerprint should define a meaningful parse change: raw extracted text hash, parsed structure hash, or both?
- Should ambiguous rerun cases emit an admin-visible flag/job result, or only log and abort?
- Which downstream refresh steps belong in the targeted repair path by default vs optional follow-up jobs?

## Decision summary

- **Routine reruns:** safe, non-destructive, ID-preserving.
- **Historical restructuring:** separate, guarded, explicit.
- **Global backfill:** deferred; not required and not cost-justified right now.
- **Minutes-triggered reruns:** should become safe after the destructive parse path is replaced with reconciliation logic.
