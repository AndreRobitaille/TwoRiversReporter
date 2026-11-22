# Person merges and retained evidence: November 7, 2026

Final runtime revision: `9938d867`, based on `70de6739`
([PR #253](https://github.com/AndreRobitaille/TwoRiversReporter/pull/253)).
Initial guards: `c0f7920d`; test refinements: `c84a337d`.
Isolated checkout, Ruby 4.0.9, Rails 8.1.4.1, PostgreSQL 18.6 and synthetic data.

## Requirements and scope

Parent [#234](https://github.com/AndreRobitaille/TwoRiversReporter/issues/234),
[#236](https://github.com/AndreRobitaille/TwoRiversReporter/issues/236), the
[identity and correction contract](../superpowers/specs/2026-11-07-council-accountability-design.md#evidence-validation-and-correction-contract)
and [pilot contract](../superpowers/plans/2026-11-07-council-evidence-pilot.md#reusable-code-and-resolved-boundaries)
require identity changes to preserve evidence and review history. Person identity
continues to use Member and MemberAlias. A merge cannot establish which of two
contradictory source records is correct. Acceptance was derived from those
requirements before inspecting the existing duplicate-discard tests.

This slice changes only duplicate vote/attendance handling in `Member#merge_into!`
and renders its existing controller result on the admin member page. No schema,
provider, generation trigger, public route or access rule changes.

## Behavior

Votes deduplicate only when both value and evidence basis match. An explicitly
recorded absence and an attendance-derived absence are different evidence even
when their displayed values match. Attendance deduplicates only when status,
attendee type and capacity match. Differences refuse the entire transaction,
including any vote moves/deletions already attempted before an attendance
conflict. Both people and all original records remain available.
The merge reloads the source at entry, so previously loaded associations cannot
hide a conflict recorded before the call. This is not a concurrency lock.

The controller's existing ArgumentError path returns to the source member. That
page now renders the existing flash component with an escaped explanation naming
the conflicting motion or meeting. Compatible merges display their success
message. Neither refusal nor success calls AI or changes factual validation.

Compatible merges keep the source name as an alias. Rebuilding display motions
and attendance from completed extraction stages resolves both raw names to the
surviving person without changing the retained source, observation, audited
decision assignment or topic evidence. Original raw attribution remains part of
the extraction history; the merge does not rewrite it as if the source used the
canonical name.

## Behavioral verification

| Workflow / variant | Real boundary and outcome | Limits |
| --- | --- | --- |
| ADM-10 → BG-02 → RES-10, compatible merge | Synthetic download/text publication → deterministic vote and attendance jobs → authorized HTTP merge → cached reconstruction forced by a meeting-date correction → fresh member reads. Three named voters become two people, with the same two retained extraction stages, one observation/review/event and the original three raw names. No additional provider construction is allowed. | The aliases are synthetic known duplicates, not real-person identity validation. |
| ADM-10 / RES-10, conflicting vote | Both authorized member pages first show their distinct votes. Actual HTTP merge refuses; fresh reads preserve each value. Snapshots of people, aliases, votes, attendance, observations, assignments and events remain identical. | Synthetic contradictory current projection; no factual correction is performed. |
| ADM-10, attendance conflict after vote deduplication | Actual HTTP merge encounters attendance disagreement after matching votes. Transaction rollback preserves both votes, people and attendance statuses. | Serial merge; concurrency is separate. |
| ADM-10, evidence distinctions | Model checks separately exercise differing vote values/bases and attendance status/type/capacity. Each refusal preserves both record identities and attributes without creating an alias. Identical duplicates retain the existing successful path. | Exact equality is deliberately conservative; no automatic conflict resolution. |
| ADM-10, cached caller state | Load source votes/attendance, persist a conflicting change through another record instance, then invoke the real merge on the earlier member instance. Fresh evidence is checked and both records survive. | Changes before the call, not concurrent writes during the transaction. |
| ADM-10, browser control and later read | Browser email sign-in, real session/CSRF/Turbo/native confirmation, successful matching merge, then refused conflicting merge with visible explanation and usable form. Later target visit retains its own vote and the accepted alias. | Final email transport is captured; passkey is an eligibility fixture, not a WebAuthn ceremony. |

The browser runs locally on Linux with Chrome 157.0.8103.38 and matching
ChromeDriver. No requested Mac/browser session is substituted. Prepared synthetic
pages enter real text publication; native PDF/OCR accuracy is not retested here.
No private notes or real civic conclusions are introduced.

## Execution record

Commands use the permanent shared bundle, Ruby 4.0.9 PATH,
`DATABASE_URL=postgresql:///trr_council_member_merges_test` and `PARALLEL_WORKERS=1`.
Application, browser and fault tests run serially against this isolated database.
Development boot/eager loading and local `SELECT 1` passed before test setup.

- Before implementation, `bin/rails test test/models/member_test.rb test/integration/member_evidence_merge_journey_test.rb`
  ran **48 tests, 121 assertions, four intended failures, no errors/skips**.
  Conflicting records were discarded instead of refusing the merge.
- The first expanded HTTP run exposed absent flash rendering after a correct
  refusal; the page now displays the controller's result. Initial fixture issues
  (bare agenda reference and the profile's agenda-title label) were corrected
  before the recorded red baseline; they were not product defects.
- `bin/rails test test/models/member_test.rb test/integration/member_evidence_merge_journey_test.rb test/controllers/admin/members_controller_test.rb`:
  **54 tests, 198 assertions, zero failures/errors/skips**.
- The first full run found one preexisting ambiguous continuity assertion:
  `find_by(lifecycle_status: "resolved")` could select cross-body progression
  instead of the motion event. The revised assertion requires exactly one
  motion-outcome event, resolved status and its exact motion ID/outcome. The
  expanded targeted command adds `test/services/topics/continuity_service_test.rb`:
  **63 tests, 223 assertions, zero failures/errors/skips** at `c84a337d`.
- `bin/rails test test/system/member_merge_journeys_test.rb`:
  **one test, 33 assertions, zero failures/errors/skips**.
  The first browser attempt used a mismatched system ChromeDriver and failed
  before assertions. Reusing the already installed matching temporary driver
  resolved the local environment failure; system packages were not modified.
- `bin/rubocop`: **672 files, no offenses**.
- Restored full `bin/rails test --seed 36977` at `c84a337d`:
  **2,281 tests, 14,458 assertions, zero failures/errors**, one existing
  PromptRun fixture skip. Full `bin/rails test:system` at that revision:
  **23 tests, 793 assertions, zero failures/errors/skips**.
- A subsequent cache-boundary regression reproduced silent conflict loss before
  the entry reload: one test, one assertion, one intended failure, no errors/skips.
  Final expanded targeted suite at `9938d867`: **64 tests, 235 assertions, zero
  failures/errors/skips**. The browser merge journey also passed again with
  33 assertions, and RuboCop remained clean. The preceding full local runs
  predate this final reload; exact-head CI is separate verification.

After the passing baseline, isolated faults below each reached one intended
assertion failure with no errors/skips. Each fault was restored exactly and its
same test rerun to green before the next mutation. Filters use
`bin/rails test <file> -i <filter>`. The first attendance-type experiment exposed
a cached fixture association that masked the removed check; reloading the people
between cases fixed the test, and the complete fault sequence was repeated.

| Bounded fault | Test/filter | Failure assertions | Restored assertions |
| --- | --- | --- | --- |
| Ignore vote conflicts | `member_evidence_merge_journey_test.rb`, `/conflicting_votes/` | 13; HTTP incorrectly redirects to the surviving target after allowed pages proved distinct votes | 29 |
| Compare vote value but omit evidence basis | `member_test.rb`, `/contradictory_vote/` | 1; derived and explicit evidence incorrectly merge | 12 |
| Ignore attendance conflicts | `member_evidence_merge_journey_test.rb`, `/attendance_conflict/` | 3; merge succeeds instead of rolling back matching-vote deletion | 18 |
| Omit attendee type from comparison | `member_test.rb`, `/contradictory_attendance/` | 7; staff/guest distinction is lost after the status variant passed | 18 |
| Omit capacity from comparison | `member_test.rb`, `/contradictory_attendance/` | 13; clerk/manager distinction is lost after prior variants passed | 18 |
| Suppress only alert text in the page | `member_merge_journeys_test.rb`, `/admin_merges/` | 24; successful merge feedback is proved first, then the refusal explanation is missing in the browser | 33 |
| Omit the source-name alias | `member_evidence_merge_journey_test.rb`, `/compatible_member_merge/` | 16; resolving the old raw name creates a different person instead of the survivor | 39 |
| Replace the motion source ID with an unrelated ID | `continuity_service_test.rb`, `/sets_status_to_resolved_if_motion_passed/` | 4; the strengthened assertion rejects the wrong retained source reference | 4 |
| Omit the entry reload | `member_test.rb`, `/checks_current_records/` | 1; cached matching votes conceal a persisted disagreement | 12 |

The first eight faults ran at `c84a337d`, the final one at `9938d867`.
Five changed Markdown files passed 203 local link/anchor and balanced-fence
checks; `git diff --check` passed.

## Remaining boundaries

This refuses ambiguous merges; it does not supply a factual vote/attendance
correction editor or automatically reconcile contradictory extraction rows.
New paid analysis is not a remedy for a merge conflict. Existing membership and
office-term duplicate rules, concurrent person merges/publication, direct alias
editing, old merged-person URL redirects, existing stored prose withdrawal and
source-wide semantic validation remain separate work. No full #236 completion
or profile rollout is claimed.

No paid AI, production access, copying/sync/backfill, GitHub merge or deployment
was performed. The original checkout and preceding PRs remain preserved.
