# Stable decision identities: November 7, 2026

Application revision: `cfc482e0`, based on `6179f9e4` (PR #250) and the source,
extraction and publication foundations in PRs #247–#249. Isolated checkout with
Ruby 4.0.9, Rails 8.1.4.1, PostgreSQL 18.6 and synthetic database/storage.

## Contract and implementation boundary

Parent [#234](https://github.com/AndreRobitaille/TwoRiversReporter/issues/234),
[#236](https://github.com/AndreRobitaille/TwoRiversReporter/issues/236), the
[design](../superpowers/specs/2026-11-07-council-accountability-design.md#evidence-validation-and-correction-contract)
and [pilot contract](../superpowers/plans/2026-11-07-council-evidence-pilot.md)
require evidence references independent of replaceable Motion IDs, no inherited
approval and conservative handling of uncertain identity. Acceptance was derived
before implementation: two opposing motions in one agenda item keep separate
identities; exact replay preserves references; changed, reordered or duplicated
evidence cannot silently take another decision's identity.

`CouncilDecision` supplies an immutable opaque UUID. `CouncilDecisionObservation`
retains one projected raw motion from a completed vote extraction, its original
extraction-array sequence, checked passage, exact agenda context, identity rule/status,
reason and possible prior decision IDs. It references the retained stage rather
than copying person identities into a new directory. Existing Motion rows point
to observations; their own IDs may still change. All writes occur inside the
existing meeting/source publication transaction with database uniqueness guards.
Filtered unseconded entries remain in the raw stage and do not shift the retained
sequence of operative entries or become stable decisions through this projection.

`Minutes::DecisionLedger` rechecks retained passages with code. The first supported
publication can establish an identity baseline when no stable IDs exist, even if
older publications were unlocated; those older observations remain unresolved
and unmapped. A uniquely located and uniquely attributed excerpt can receive an
identity. Later correspondence requires exact excerpt, extraction sequence and
agenda context plus unchanged relative ordering of checked passages. Page/character
locations are compared independently of the provider's array order: header/page
shifts are harmless, while order inversions hold both participants for resolution.
Rewritten descriptions and agenda row IDs are not identity keys. Null
agenda references retain an explicitly unassigned context. Unsupported references,
missing passages, duplicate attribution, changed ordering and unmatched revisions
retain unresolved observations and candidates. No fallback fuzzy match occurs.
Unmatched additions within a revised meeting also await identity resolution.

Identity statuses `introduced` and `matched` are structural correspondence,
**not** semantic validation or human review. Every observation remains `extracted`.
The source excerpt does not prove vote attribution, eligibility, interpretation,
or an amendment relationship. No old approval is copied to new source content.

A stable decision's `current_observation` reads only the current published vote
stage. If the latest published stage leaves that identity unresolved, the method
returns nil while retaining its history. It never substitutes a superseded
observation. The prior coherent publication remains current while replacement
stages are pending, as specified by PR #249. An unresolved decision does not
block unrelated matching decisions from advancing in the new publication.

The projection-rule version permits deterministic repair of prepared cached
stages through existing nightly/jobs. It does not re-extract unchanged input,
add a scheduler or process untouched legacy completion markers. Identical source
restoration reuses the original stage, observations and UUIDs. There is no paid
dispatch path in identity reconciliation. Existing continuity processing is
deterministic; missing-summary eligibility still follows its existing contract.

## Executed workflow evidence

| Workflow / variant | Observed boundary and outcome | Limits |
| --- | --- | --- |
| BG-02, initial and revised evidence | Real download/text publication → vote/attendance jobs with deterministic providers → coherent publication → fresh UUID lookup. Opposing deny/adopt motions share an agenda item but retain distinct IDs across exact passage correspondence. Old raw values and source versions remain inspectable. | Provider accuracy simulated; no factual approval or real-source model evaluation. |
| BG-02, replay and restoration | Repeated jobs, date reprojection, and restoration of the exact prior source make zero new provider calls and preserve observations/identities. Replaced agenda row IDs preserve exact textual context. | No historical production backfill was run. |
| BG-02, unresolved evidence | Changed or reordered passages retain candidates without assignment, including reordered document passages with unchanged provider array order. Duplicate excerpts, unknown locations and unsupported agenda references acquire no guessed IDs. A superseded UUID has no current observation while an unrelated unchanged decision advances. | Review/resolution UI and dependent claim consumers remain separate. |
| BG-02, first supported baseline | A published unlocated stage creates no IDs; a later supported source establishes new identities while preserving the earlier unresolved observations without mapping them. | This is initial identity establishment, not a claimed match or reviewed correction of older records. |
| BG-02, parallel/delayed work | Separate PostgreSQL connections and overlapping providers produce one decision/observation for the published motion. A delayed old extraction remains retained but cannot replace newer identity references. Failed publication rolls back identities, observations and projections; retry uses cached stages. | Real threads/DB locks plus deterministic scheduling; not multi-host load testing. |
| ADM-10 / BG-02, member merge | Current votes move to the canonical Member; new projection uses existing aliases, stable IDs survive, and raw source names remain unchanged. | Conflicting identity corrections still need explicit review. |
| BG-01/RES-08, removal | Source/meeting removal retains UUIDs, observations, stages and original text versions. Duplicate cleanup treats retained decision history as useful content. | Canonical meeting merge and public source-availability presentation remain separate. |
| RES-10, compatibility | Existing real member-page HTTP journey still advances votes/attendance together. Existing API serializers explicitly select fields; this slice adds no public route, API field or visible control. | No new stable-ID browser navigation is claimed. |

## Runner and representative defects

Commands used the permanent shared bundle, explicit Ruby 4.0.9 PATH,
`DATABASE_URL=postgresql:///trr_council_decisions_test` and `PARALLEL_WORKERS=1`.
Application tests and migrations ran serially on this isolated database.

- Initial test against the base: one run/assertion/failure, no errors/skips;
  published motions had no retained decision observation.
- Initial clean focused baseline at `1484475f`: `bin/rails test test/jobs/minutes test/integration/minutes_publication_journey_test.rb test/jobs/extract_votes_job_test.rb test/jobs/extract_committee_members_job_test.rb test/services/scrapers/pipeline_repair_sweep_test.rb test/services/meetings/window_duplicate_cleanup_test.rb`:
  127 runs, 532 assertions, zero failures/errors/skips. The expanded runner includes
  the real PostgreSQL concurrency test and current-reference withdrawal checks.
- An earlier expanded run hit a nested Minitest provider-stub restoration error.
  The test helper now restores the prior provider method safely. This was a
  test-harness failure, not evidence of an application defect; the restored run
  above passed.
- Fault 1: remove excerpt equality from correspondence. Run
  `test/jobs/minutes/decision_identity_test.rb -n /changed_evidence_withdraws/`:
  one run/assertion/failure, no errors/skips; a changed passage is incorrectly
  assigned the prior identity. Restore the clean implementation.
- Fault 2: fall back from current lookup to the latest historical observation.
  The same test fails with one run, five assertions, one failure, no errors/skips;
  a superseded observation is returned as current. Restore the clean lookup.
- Fault 3: ignore duplicate excerpt attribution. With
  `-n /duplicate_excerpt_attribution/`, one run/assertion/failure, no errors/skips;
  two identities are incorrectly introduced for the same passage. Restore the
  guard.
- First-supported-baseline regression: the added test initially failed with one
  run, two assertions, one failure and no errors/skips (zero IDs instead of two).
  After correction, all 12 identity tests passed with 80 assertions. Fault 4
  restored the old initial-publication rule; `-n /first_supported_evidence/`
  reached the same intended failure. Restore the corrected rule.
- Review at `87440c1a` identified source ordering hidden by unchanged provider
  array order. The added pipeline test reproduced three matches instead of two
  unresolved and one unaffected match: one run, two assertions, one failure,
  no errors/skips. The retained-location correction passed all 13 identity tests
  with 89 assertions. Fault 5 disabled the location-order comparison;
  `-n /document_passage_order_changes/` reached the same intended failure. Restore
  the comparison. All five faults reached behavioral assertions, not boot errors.
- Migration up and down/up passed. `bin/rubocop -A db/schema.rb` ran; the inspected
  schema diff contains the two tables, Motion reference, indexes/foreign keys and
  revision. `bin/rubocop` passed for 661 files.
- Restored full `bin/rails test` at `cfc482e0`: 2,245 tests, 14,077 assertions, zero failures or
  errors and one existing PromptRun fixture skip. No local browser journey was
  added because this slice introduces no visible controls or routes.
- Four changed Markdown documents passed 104 local link/anchor checks and fence
  checks; `git diff --check` passed.

## Remaining scope

This is a bounded #236 slice, not completion of that issue. Append-only reviewed
corrections, explicit motion/amendment relationships, broader identity conflicts
and downstream claim withdrawal still need implementation. Existing topic
lifecycle events still contain legacy Motion references; their migration and
reconciliation are not claimed here. Public stable-reference navigation,
version-bound profile reads and service-period denominators remain subsequent
work. Source availability is distinct from retained historical evidence.

No paid AI, production access, database copying/sync/backfill, merge or deployment
was performed. Original working files and all earlier PRs remain preserved.
