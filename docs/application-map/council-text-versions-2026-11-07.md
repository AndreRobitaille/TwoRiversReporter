# Council PDF/OCR text versions: November 7, 2026

Application revision: `84c4be1e`, on source-artifact foundation `594d668a`
(PR #247) and planning PR #246. Isolated local checkout, Ruby 4.0.9,
Rails 8.1.4.1, PostgreSQL 18.6, test-only database and disk storage. The original
checkout and development data were preserved. No production or paid provider
was accessed.

## Requirement and bounded scope

[#236](https://github.com/AndreRobitaille/TwoRiversReporter/issues/236), the
[design's evidence contract](../superpowers/specs/2026-11-07-council-accountability-design.md#evidence-validation-and-correction-contract),
and the [pilot implementation contract](../superpowers/plans/2026-11-07-council-evidence-pilot.md)
require retained source versions, complete evidence, no silent replacement and
reusable source processing. Acceptance was derived before implementation:
retain pages/full text against exact source bytes, preserve distinct opening and
closing actions, publish a complete result atomically, reject late work and
avoid downstream generation on unchanged successful input.

This second #236 slice adds `MeetingDocumentTextVersion` and
`Documents::PublishText`, integrated into PDF and OCR jobs. Source versions stay
`collected`; text versions are `extracted`, never promoted to approved evidence.
The current pointer resolves only when its artifact matches the current source.
Retained versions survive document removal and reject content edits. Legacy
attachments without download provenance receive atomic/stale-safe projection,
but no invented source history.

## Executed workflow boundaries

| Workflow / variant | Assertions and boundary | Evidence level |
| --- | --- | --- |
| BG-02, PDF replacement | Synthetic HTTP bytes → real DownloadJob → PDF command responses → real publication transaction → fresh model read. Both revisions preserve their own raw/cleaned pages, full text, source identity and readable original bytes. Replacing bytes makes the previous text pointer non-current until extraction completes. | Job/data journey; HTTP and most command responses deterministic, real persistence and job dispatch. |
| BG-02, native parsing | Real `pdfinfo`, `pdftotext`, `pdftoppm` and `tesseract` process the committed synthetic three-page PDF. Both extraction versions retain three numbered pages, a blank middle page and distinct opening/closing actions. Freshly read projection equals retained text. | Installed local tool boundary, separate from deterministic provider tests. |
| BG-02, retry / quality | Unchanged PDF and OCR retries create no additional version or downstream enqueue; a PDF retry preserves completed OCR. A new text-bearing source does not inherit the prior source's OCR-completed status. | Job/persistence boundary; AI construction prohibited in PDF tests and the native journey. No paid AI executed. |
| BG-02, late output | A newer download plus extraction completes during old PDF/OCR work. Late success cannot overwrite it; late OCR failure cannot mark the newer completed result failed. | Deterministic interleaving, not independent-process stress testing. |
| BG-02, incomplete / failed output | Bad command status, missing final OCR image, failed recognition, or second-page database failure preserves prior text/pages/pointer. No partial snapshot becomes current. An attachment inconsistent with retained bytes cannot acquire a text version. | Command/database failures simulated; real rollback and later reads. |
| BG-02, page fidelity | Blank middle/final pages keep identity; long unusable tokens remain in raw text; all twelve OCR pages keep numeric order despite digits in the temporary directory name. | Exact quantity/order/content assertions at source → retained snapshot → mutable projection. |
| BG-01/RES-08, removal | Remove document, execute actual queued blob-purge jobs, then read archived text/pages and original source bytes. | Persisted removal journey. |
| RES-07, compatibility | Existing source catalog/resolver and HTTP citation tests remain passing. | Existing compatibility coverage; no new archive endpoint or citation authority. |

The committed PDF is wholly synthetic, 3 pages, SHA-256
`e922edc86f24bf22acfc79f3e39a262426ce321fce7e81f405f575c24300bb87`.
It contains “SYNTHETIC opening action approved.” and “SYNTHETIC closing action
deferred.” with a blank middle page. The native parser journey used Poppler
26.10.0 and Tesseract 5.5.3, retained two versions for one source, and queued zero
jobs on repeated input. Its temporary data was rolled back. This does not
measure OCR accuracy on historical council scans.

## Runner and defect evidence

Commands use the permanent external bundle directory, Ruby 4.0.9 on PATH,
`DATABASE_URL=postgresql:///trr_council_extractions_test` and
`PARALLEL_WORKERS=1`. Application and browser suites are not run concurrently
against this database. This slice has no new visible controls or response
formats, so local verification targets its job/persistence boundary.

- `RAILS_ENV=test bin/rails db:migrate` and `bin/rubocop -A db/schema.rb`:
  successful isolated migration; inspected schema diff contains only the text
  version table/indexes, current pointer/foreign keys and schema revision.
- `bin/rails test test/jobs/documents/text_version_test.rb`: clean baseline,
  14 runs, 102 assertions, zero failures/errors/skips. Tests discovered by the
  actual Rails runner include the real `pdfinfo`/`pdftotext` fixture journey.
- Native PDF/OCR behavioral runner: actual jobs/persistence/fresh reads, both
  installed extraction paths, original-byte equality and no repeated enqueue.
  Provider construction raises if attempted; none occurred. Only HTTP download
  transport was replaced with the committed fixture.
- Fault 1: remove publication's input-state comparison, then run the text-version
  test with `-n /late_PDF_output/`. One run, three assertions, one failure,
  no errors/skips: fresh text contains the stale approved action instead of the
  newer deferred action. Restore the comparison using Git.
- Fault 2: trust the generated image count in place of the PDF's declared count,
  then run `-n /missing_final_OCR_page/`. One run, three assertions, one failure,
  no errors/skips: incomplete output queues four downstream jobs instead of zero.
  Restore the PDF page-count check using Git. Both faults started from the
  passing baseline and were isolated; neither was a syntax/boot failure.

After restoring both faults, `bin/rails test` completed: **2,202 runs, 13,769
assertions, zero failures/errors, one pre-existing skip** (`PromptRunTest`, no
meeting fixture). The earlier focused job/model/citation/HTTP command ran 60
tests and 362 assertions before adding the final two provenance/status tests;
the 14-test clean baseline and restored full suite include those additions.
`bin/rubocop` inspected 641 files with no offenses. `git diff --check` passed.
Five changed Markdown files passed 104 relative link/anchor checks and balanced
code-fence checks. These counts are execution evidence, not full workflow or
semantic-accuracy coverage.

## Remaining boundaries

Stable decision identity, reviewed assertions/corrections, campaign intake,
coordinated vote/attendance versions and public source-availability display
remain separate #236 work. Existing resident/AI readers still use the mutable
projection; they have not been migrated to retained text-version provenance.
This slice does not repair old mixed-source snapshots or certify that legacy
extracted claims are current. Citation resolution/gating remains unchanged.
Historical byte reversion can still run existing downstream analysis; a complete
AI stage cache, retry/spending enforcement and missed-work recovery belong to
#238 before campaign generation. No scheduler or paid generation was added;
no production sync/backfill, merge or deployment ran.
