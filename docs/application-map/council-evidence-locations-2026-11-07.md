# Minutes passage locations: November 7, 2026

Application revision: `951fa723`, based on `74785d5c` (PR #249), following retained-artifact and text-version PRs
#247/#248. Isolated local checkout, Ruby 4.0.9, Rails 8.1.4.1, PostgreSQL 18.6,
synthetic database/storage and deterministic providers. No production data or
real campaign claims are used.

## Requirements and boundary

Parent [#234](https://github.com/AndreRobitaille/TwoRiversReporter/issues/234),
[#236](https://github.com/AndreRobitaille/TwoRiversReporter/issues/236), the
[evidence contract](../superpowers/specs/2026-11-07-council-accountability-design.md#evidence-validation-and-correction-contract)
and [pilot decision contract](../superpowers/plans/2026-11-07-council-evidence-pilot.md)
require exact source locations and forbid silent inheritance of old validation.
The current extractor supplied descriptions but no motion passages. Matching
revisions by those descriptions would be an unsafe basis for stable decision IDs.

`Minutes::LocateEvidence` runs with code when a new vote extraction completes.
It reads only that stage's retained text version, checks its identity and supplied
text, and locates each requested `source_excerpt`. It never uses today's mutable
page rows or model-provided URLs/page numbers. Whitespace is normalized; wording,
case and punctuation are preserved. The excerpt must occur exactly once.

The extraction retains the rule version, source key, text-version ID and one
result per raw motion, in source order. A located passage has cleaned-page text
hashes and zero-based character ranges with exclusive ends. Unicode characters
are counted as characters, not bytes. Cross-page excerpts retain each covered
page separately; blank pages keep their original numbering. Missing, malformed,
unmatched, repeated or unretained evidence remains `unresolved` with a reason.
Completed checks are immutable alongside the raw parsed output.

`located` means text occurrence, **not** semantic validation, approval, proven
identity, service eligibility, vote attribution or public source availability.
Existing display rows do not become certified evidence through this check.
Historical stages with no check remain unchecked; no backfill or AI refresh is
triggered to fill the column. Both this check and unchanged replay use zero new
AI calls. Source correction requires a new stage/check against the new version.

The vote prompt requests one distinct operative motion per array entry and
explicitly named votes only. It asks for contiguous supporting minutes text,
preserves separately failed motions, and no longer asks the model to infer yes
votes from attendance or confidence. Allowed input remains complete; metadata
now states the existing 50,000-character ceiling accurately. The production
template population task was not run. Prompt adherence and real extraction
accuracy still need a separately authorized evaluation; deterministic responses
prove the application boundary, not model performance.

## Executed workflow evidence

Affected workflow: BG-02, source extraction through retained evidence and later
reads. No route, public response, control or access policy is added.

| Variant | Boundary and meaningful outcome |
| --- | --- |
| Distinct opening/closing actions | Real download and text publication, real vote job and AI service with deterministic transport, two source-order location records on pages 1 and 3, exact text read back from retained pages. Full closing action reaches the prompt and PromptRun. |
| Unsupported provenance | Provider-supplied wrong URL/page never becomes a checked location. Legacy text and mismatched source/version identity receive unresolved reasons. |
| Ambiguity and incompleteness | Five distinct motions survive even with null, malformed, blank, absent or multiply occurring excerpts; none acquires an invented location. |
| Page boundaries | Whitespace-normalized excerpt crosses a blank page and Unicode text; stored character ranges reconstruct the exact passage on the original page numbers. |
| Revised/removed source | Replacement arrives during provider work; old result remains attached to the original pages, new work checks the new version, and both remain readable after document removal. No stale current publication occurs. |
| Reuse and immutability | Unchanged real job replay dispatches no provider call; completed location data cannot be edited in place. Old unknown evidence is not relabeled as validated. |

The initial pipeline test failed against the base: one run/assertion/failure,
no errors/skips, because no retained passage check existed. This establishes
the missing behavior separately from representative fault tests.

## Runner and defect detection

Commands used explicit Ruby 4.0.9 PATH, the permanent shared bundle,
`DATABASE_URL=postgresql:///trr_council_locations_test` and `PARALLEL_WORKERS=1`.
Database test runs and migration checks were serial.

- Focused baseline: `bin/rails test test/jobs/minutes test/integration/minutes_publication_journey_test.rb test/services/ai/minutes_input_test.rb test/jobs/extract_votes_job_test.rb test/jobs/extract_committee_members_job_test.rb test/lib/prompt_template_data_test.rb test/services/scrapers/pipeline_repair_sweep_test.rb`:
  115 runs, 457 assertions, zero failures/errors/skips. After strengthening the
  Unicode fixture, `bin/rails test test/jobs/minutes/evidence_locations_test.rb`
  passed six tests and 53 assertions.
- Fault 1: remove the repeated-occurrence guard. The same file with
  `-n /unsupported_missing_absent/` fails with one run, two assertions, one
  failure and no errors/skips; the repeated excerpt incorrectly loses its
  unresolved reason. Restore from the clean baseline.
- Fault 2: use the current document's text version instead of the pinned stage
  version. With `-n /source_revision_during_extraction/`, one run/assertion/failure
  and no errors/skips; the retained check points to the replacement version.
  Restore from the clean baseline. Neither failure is a boot/syntax error.
- Migration down/up passed. `bin/rubocop -A db/schema.rb` ran; the inspected schema
  diff contains only the nullable JSONB column and schema revision. Existing rows
  are not assigned fabricated checks. `bin/rubocop` passed for 656 files.
- After restoring both faults, `bin/rails test` passed 2,232 tests and 13,985
  assertions, with zero failures/errors and one existing PromptRun fixture skip.
  Four changed Markdown files passed 102 local-link/anchor checks and balanced
  fences; `git diff --check` passed.

No local browser journey was added: the changed boundary is deterministic
evidence persistence, with no new public controls or response formats.

## Remaining scope

Stable decision identities/reconciliation, correction history, semantic and
identity acceptance, version-bound profile readers, source-availability display,
service windows and #238's dollar ledger remain separate work. A source-order
sequence here is an extraction position, never a stable decision ID. No claim
or review status is inferred from an excerpt's mere occurrence.

No paid AI, production access, database copying/sync/backfill, merge or deployment
was performed. Parent #234 remains the governing goal; #236 is not complete.
