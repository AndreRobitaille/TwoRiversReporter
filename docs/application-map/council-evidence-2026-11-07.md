# Council source artifact foundation: November 7, 2026

Application revision: `504ec74a` (on planning baseline `da8d2588`, with base
application `5d9ff761`). Local isolated checkout, Ruby 4.0.9, Rails 8.1.4.1,
PostgreSQL 18.6, synthetic test database and separate disk storage. Existing
checkout and development data were preserved. This evidence is local, not a
production check or a real-provider accuracy evaluation.

## Acceptance derived before implementation

[#235](https://github.com/AndreRobitaille/TwoRiversReporter/issues/235),
[#236](https://github.com/AndreRobitaille/TwoRiversReporter/issues/236), the
[design's evidence contract](../superpowers/specs/2026-11-07-council-accountability-design.md#evidence-validation-and-correction-contract),
and the Development Plan require retained original sources, no silent replacement
of evidence, separate retrieval/event/publication dates and idempotent work.
The [pilot source check](../superpowers/plans/2026-11-07-council-evidence-pilot.md)
records inspected passages, exact source hashes, real-source gaps, service-date
limits and the next implementation boundaries. Source review does not establish
AI extraction accuracy, complete term coverage, or campaign follow-through.

## Verified boundary and runner evidence

| Workflow / variant | Boundary and meaningful assertions | Coverage |
| --- | --- | --- |
| BG-02, first/replaced download | Deterministic HTTP response → real DownloadJob → PostgreSQL and Active Storage → fresh model read. Distinct synthetic revisions retain exact bytes and hashes; each changed version is collected, with no inherited approval; meeting/retrieval/HTTP dates remain separate and publication unknown. | Verified job/data journey; HTTP transport simulated, downstream AI jobs queued but not executed. |
| BG-02, unchanged/reverted input | Same SHA and 304 preserve current content timestamp; same source/version reuses row/blob, queues no additional analysis; byte reversion reuses its earlier archive. A legacy SHA-only row gains retained bytes on a full response without an analysis enqueue. | Verified download boundary, not full AI stage-cache behavior (#238). Reversion still triggers existing analysis because the current document changed. |
| BG-02, failed/delayed work | 404 preserves existing evidence. Interleaved competing download completes during the first request; late 200/304 cannot replace its bytes or metadata. Rejected archive persistence rolls back current metadata/file and queues no analysis. | Deterministic competing-request simulation, not independent worker/process load testing. |
| BG-01/RES-08, removal | Delete document and run actual queued Active Storage purge jobs; archived version and exact original bytes remain readable with original IDs/URL. | Document-removal boundary verified; no change to canonical meeting merge rules. |
| RES-07, source identity | Existing valid page citation resolves first, then becomes unresolved with `source_changed` after a source change despite the retained artifact. New source URL gets a distinct version; old source URL remains in history. | Model/resolver plus existing HTTP citation tests; no new route or archive presentation. |
| BG-02, persistence guards | Retained metadata/file reject replacement; database unique index rejects duplicate source identity even with model validation bypassed. | Component coverage, separate from the job journey. |

The shared synthetic fixture has two campaign participants, a losing fee vote,
an incomplete roll call and unknown implementation outcome. Download tests use
its distinct original/corrected minutes as deterministic bytes; they do not
parse a real PDF or claim to validate campaign semantics. All fixture people,
URLs and statements are invented. New retention tests fail if the job constructs
an AI provider. Existing PDF/citation compatibility tests use deterministic
responses and do not run paid providers.

Commands used the checkout's permanent external bundle path and the explicit
test-only `DATABASE_URL=postgresql:///trr_council_foundation_test` with
`PARALLEL_WORKERS=1`; Ruby 4.0.9 was prepended to PATH. The ordinary suite is
serial with respect to any browser suite. No browser suite was needed for the
changed boundary: this PR adds no page/control, cookie, CSRF or navigation behavior.

- `bin/rails db:create db:schema:load`, then `RAILS_ENV=test bin/rails db:migrate`.
  Migration succeeded on the isolated database; `bin/rubocop -A db/schema.rb`
  restored repository formatting. Schema diff contains only this table, its
  indexes/foreign key and the schema version.
- `bin/rails test test/jobs/documents/source_version_retention_test.rb test/jobs/documents/download_job_test.rb test/models/meeting_document_version_test.rb test/jobs/documents/analyze_pdf_job_test.rb test/services/citations/source_catalog_test.rb test/services/citations/resolver_test.rb test/controllers/meeting_citations_test.rb`:
  50 runs, 295 assertions, zero failures/errors/skips before the additional
  explicit retention assertion below.
- Clean `504ec74a` baseline: `bin/rails test test/jobs/documents/source_version_retention_test.rb test/models/meeting_document_version_test.rb`:
  11 runs, 68 assertions, zero failures/errors/skips. Confirms actual discovery
  of all new model and job tests.
- `bin/rubocop`: 637 files, no offenses. `git diff --check` clean.

- Restored `504ec74a`: `bin/rails test`: 2,187 runs, 13,657 assertions, zero
  failures/errors, one pre-existing skip (`PromptRunTest`, no meeting fixture).
  This is the green post-fault run and includes all new tests.
- Local documentation checker: six touched Markdown files, 103 relative
  links/anchors, balanced code fences and valid synthetic JSON. Official source
  links/hashes and the referenced PDF pages were checked separately in the pilot.

## Demonstrated defect detection

Each mutation was isolated in the synthetic checkout/database after the clean
baseline, with no other source changes, then restored using Git before rerunning.

1. Change the document's version association from `dependent: :nullify` to
   `:destroy`. Run the retention test with `-n /failed_fetch_and_document_removal/`.
   Result: 1 run, 4 assertions, 1 failure, no errors/skips, specifically
   “Removing a document must retain its evidence version.” This detects actual
   loss of retained evidence, not a syntax/boot failure.
2. Remove the successful-download comparison against `requested_state`.
   Run `-n /a_delayed_successful_response/`. Result: 1 run, 1 assertion, 1 failure,
   no errors/skips: later fresh read contains stale competing bytes instead of
   the corrected minutes. Restore the guard and verify the checkout diff is clean.

## Remaining scope

No full history import, campaign intake, reviewed assertion/correction system,
stable decision identity, member-merge changes, coordinated vote/attendance
publication, new profile sections, source-availability display or paid dispatch
budget was implemented. #236 remains open for those evidence stages; #238's
enforced cost controls remain a prerequisite for campaign AI. Archived source
bytes do not certify the legacy mutable text or extracted rows belong to them.
Current citation access/gating and fail-closed source resolution are unchanged.
No paid call, real email, production access, database sync, backfill, merge or
deployment occurred.
