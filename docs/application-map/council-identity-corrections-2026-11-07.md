# Audited decision identity corrections: November 7, 2026

Application revision: `9a909f8f`, based on `77dc24e2`
([PR #251](https://github.com/AndreRobitaille/TwoRiversReporter/pull/251)).
Isolated checkout, Ruby 4.0.9, Rails 8.1.4.1, PostgreSQL 18.6 and synthetic data.

## Binding requirements and scope

Parent [#234](https://github.com/AndreRobitaille/TwoRiversReporter/issues/234),
[#236](https://github.com/AndreRobitaille/TwoRiversReporter/issues/236), the
[correction contract](../superpowers/specs/2026-11-07-council-accountability-design.md#evidence-validation-and-correction-contract)
and [pilot](../superpowers/plans/2026-11-07-council-evidence-pilot.md) require
append-only correction history, preservation or an explicit conflict on replay,
no inherited approval for changed sources, and continued unrelated updates.
Acceptance was derived from those requirements before implementation.

This slice handles **decision identity correspondence**. It supplies the internal
service and persistence boundary for a future review interface. It does not
correct vote values or attendance, approve an extracted factual interpretation,
or add a public/admin route. Every observation remains extracted evidence.

## Implemented contract

`CouncilDecisionAssignment` holds the effective observation → decision mapping.
Database uniqueness allows only one observation per decision in a vote stage.
The migration initializes it from the existing extracted identity mappings;
original observations and their identity basis remain immutable.

`CouncilDecisions::ResolveIdentity` requires a currently active administrator,
the current published source, an expected prior correction and a UUID request
key. It can assign an existing same-meeting decision with an explicit retained
basis observation, introduce a new identity, or withdraw an assignment. Creating
an identity needs a uniquely located retained passage. Withdrawing an existing
mapping does not require inventing replacement evidence. An unlocated record
without an assignment cannot receive an identity review.

`CouncilDecisionCorrection` retains the actor's ID/email snapshot, timestamp,
reason, before/after identities, prior correction, command manifest and source
references. Its review scope is explicitly `decision_identity_only`. Private
review provenance is not added to public serializers, HTML or metadata. Existing
request replay returns its original receipt without reapplying an older mapping;
reusing the key for a different command fails. A stale expected correction also
fails. Review and source publication use the same meeting/document locks, and
review/audit/assignment writes commit or roll back together.

Review updates every equivalent retained observation: same source, raw data,
sequence and agenda context. The audit retains each affected assignment's before
and after state. Returning to a cached older extraction therefore preserves a
later withdrawal of the same mapping. If an older stage has another observation
occupying the target identity, both historical assignments retain a conflict;
the valid current review still publishes. Model writes require a recorded audit
transition, and ordinary assignment/review deletion is refused.

Effective stable reads use `Motion#council_decision` and
`CouncilDecision#current_observation`. The latter still selects only the current
published stage. An observation's `council_decision` is the original extracted
basis, not an effective override. Effective history uses a decision's
`observations`; its original extraction history remains available through
`extracted_observations` and correction before/after references.

Reprojection of unchanged evidence preserves the correction without AI. A new
extraction from the same retained source can carry it only when the raw observation
and correspondence remain compatible. Changed source content or interpretation
cannot inherit that review. The new assignment retains conflicting correction
IDs and no current decision mapping; subsequent source versions preserve that
conflict. Explicit re-review records which conflicts it resolved. An empty first
identity baseline cannot erase prior reviews by repeatedly treating rewritten
evidence as new. Unchanged unrelated supported passages can still advance.

Actor deletion nulls the live account pointer and preserves its audit snapshot.
Source/meeting removal retains the review, original observation, text version and
opaque decision. A removed meeting has no current observation. Schema rollback
refuses to discard any recorded reviews; an empty local schema can roll back and
reapply. No migration was run against production.

## Behavioral evidence

| Workflow / variant | Boundary exercised and required outcome | Limits |
| --- | --- | --- |
| BG-02 / ADM-10, ambiguous identity | Real source download/text publication → deterministic vote/attendance jobs → unresolved observation → authorized review service → fresh stable-ID and Motion reads. Reviewed mapping survives replay and date reprojection; raw identity and evidence status remain unchanged. | Internal service, not an operator browser journey or a factual accuracy evaluation. |
| BG-02, source/extraction revision | Same-source compatible extraction carries review. Changed source or interpretation withdraws the old current identity and preserves conflict references; unrelated matching decisions advance. Repeated revisions cannot reset unresolved review history. | Canonical meeting merging and motion/amendment relationships remain separate. |
| BG-02, retries and concurrency | Concurrent review commands use separate PostgreSQL connections; one stale edit loses. Concurrent copies of one request commit one audit and return the same receipt. Replaying an older accepted request cannot undo a later withdrawal. | Deterministic thread scheduling, not distributed load testing. |
| BG-02, delayed work | A review committed during a deterministic provider response survives the later same-source publication. A failed assignment rolls back its new identity/audit; the same request can retry. | Provider transport is simulated. |
| ADM-10, member identity | Existing member merge/aliases preserve current votes while reviewed decision identity and original source names survive replay. | No new person directory or identity resolver is introduced. |
| ADM-03 / BG-01 / RES-08, retention | Real User/model and document/meeting deletion retain review history; old current lookup disappears on meeting removal. A rollback guard refuses to drop reviewed history. | Existing HTTP deletion controls are unchanged; this verifies their new persistence dependency. |
| RES-10, compatibility | Existing member-page HTTP publication journey remains in the focused regression command. No new correction fields or controls are exposed. | No public correction UI or new stable-link navigation is claimed. |

## Execution record

Commands use the permanent shared bundle, explicit Ruby 4.0.9 PATH,
`DATABASE_URL=postgresql:///trr_council_corrections_test` and `PARALLEL_WORKERS=1`.
Database work, application tests and fault experiments run serially.

- Initial test against PR #251: one run/assertion/failure, no errors/skips; the
  published observation had no independent effective identity assignment.
- A first concurrency assertion used `assert_equal` with a possible nil winner,
  which Minitest rejects. It was replaced with an explicit nil assertion for that
  valid outcome. This was a test-harness failure, not a product defect.
- A first-supported-baseline regression exposed an overly broad hold: one review
  blocked an unrelated supported decision. The added test reached one intended
  failure with two assertions and no errors/skips. Reconciliation now retains the
  review conflict and permits the unrelated identity.
- Cached restoration initially revived a mapping withdrawn in a later extraction
  of the same evidence. The added test failed at the intended current-reference
  assertion: one run, four assertions, one failure, zero errors/skips. Equivalent
  assignment propagation and historical collision checks now cover this boundary.
- Initial focused command: `bin/rails test test/jobs/minutes test/integration/minutes_publication_journey_test.rb test/jobs/extract_votes_job_test.rb test/jobs/extract_committee_members_job_test.rb test/services/scrapers/pipeline_repair_sweep_test.rb test/services/meetings/window_duplicate_cleanup_test.rb`:
  145 tests, 674 assertions, zero failures/errors/skips at the initial implementation.
- Final identity/regression baseline: `bin/rails test test/jobs/minutes/identity_correction_test.rb test/jobs/minutes/parallel_identity_correction_test.rb test/jobs/minutes/decision_identity_test.rb`:
  31 tests, 230 assertions, zero failures/errors/skips. This includes the cached
  restoration correction and real PostgreSQL review concurrency.
- `bin/rubocop`: 667 files, no offenses. Development eager loading and an isolated
  database `SELECT 1` also passed using the configured permanent bundle.
- Migration up and empty down/up passed. `bin/rubocop -A db/schema.rb` ran and the
  inspected diff contains only the two tables, indexes, foreign keys and revision.
  A separate synthetic database was seeded using PR #251's schema and real jobs:
  three observations, two stable identities and one unresolved mapping. Migration
  at `fcb83b59` retained all three; later code-only projection repair reused them
  with providers forbidden and no duplicate identity or audit. The schema is
  unchanged by the subsequent cached-review propagation fix.

Each fault below started from a clean passing baseline, changed one bounded
behavior, ran `bin/rails test test/jobs/minutes/identity_correction_test.rb -n`
with the listed filter, reached the intended assertion failure and was restored.
Every fault run had one test, one failure, zero errors/skips. The current-lookup
fault was repeated after the lookup became a single database snapshot.

| Fault | Filter | Assertion reached |
| --- | --- | --- |
| Read extracted identity instead of the effective reviewed assignment | `/reviewed_identity_resolves/` | Three assertions; the corrected stable lookup incorrectly returns nil. |
| Ignore the expected prior correction | `/unassignment_is_append_only/` | Six assertions; a stale review silently replaces a later withdrawal. |
| Remove active-administrator authorization | `/only_an_active_administrator/` | Two assertions; a member can create a review. Allowed admin review is established first. |
| Drop conflicting correction references | `/rewritten_evidence_cannot_erase/` | Four assertions; an unresolved review loses its retained dependencies. |
| Forget an existing review when source content changes | `/review_carries_across_unchanged/` | Five assertions; changed content silently regains the earlier identity. |
| Update only the current extraction's assignment | `/restoring_a_cached_extraction/` | Four assertions; cached restoration revives a withdrawn mapping. |

Restored full `bin/rails test` at `9a909f8f`: **2,263 tests, 14,218 assertions,
zero failures/errors**, one existing PromptRun fixture skip. Four changed
Markdown documents passed 106 local link/anchor checks and balanced-fence checks;
`git diff --check` passed. No local browser journey was added because this slice
adds no visible control or route.

## Remaining work

The operator review screen and its HTTP/session gates are not implemented here.
Factual vote/attendance corrections, semantic validation provenance, migration of
legacy topic lifecycle references and dependent narrative withdrawal remain #236
work. New profile claims will need correction references in their dependency
manifests. This slice does not close #236 or complete the first working member page.

No paid AI, production access, database copying/sync/backfill, merge or deployment
was performed. Existing checkout work and earlier pull requests are preserved.
