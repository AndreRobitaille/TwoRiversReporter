# Additional knowledge document dependencies: November 7, 2026

Base: `9ad26642` ([PR #263](https://github.com/AndreRobitaille/TwoRiversReporter/pull/263)).
Implementation revision: `c023c121`. Verification uses Ruby 4.0.9,
Rails 8.1.4.1 and an isolated PostgreSQL 18.6 test database. Downloads, AI responses
and embeddings are deterministic; every claim and person in the fixture is synthetic.

## Contract and implementation

[#236](https://github.com/AndreRobitaille/TwoRiversReporter/issues/236), the
[evidence correction contract](../superpowers/specs/2026-11-07-council-accountability-design.md#evidence-validation-and-correction-contract),
the [changed-source publication rules](../superpowers/specs/2026-11-07-council-accountability-design.md#from-a-changed-source-to-an-updated-page)
and [behavioral QA procedure](maintenance-and-qa.md) govern this slice.
Acceptance was established before implementation: additional document text
consumed by knowledge extraction must have its own dependency, even if that
document was not an input to the supporting summary. A changed or removed input
withdraws affected knowledge without erasing its original evidence or review
state. Late provider output cannot publish against the old input.

New extraction stores the consumed raw document's existing citation catalog and
text-version identity in nullable `KnowledgeSource.source_catalog`. The same
receipt is shared by all entries from that extraction. The supporting summary
receipt remains separate. An empty catalog records that no additional document
text was consumed; older rows remain null without inferred provenance or backfill.
The additive migration also indexes the catalog for dependency lookup.

The document writer's existing transaction and meeting publication lock now
withdraw known knowledge dependents with an audit. The original receipt, text,
approval state, topic links and indexed chunks remain intact. Independent manual
context and unknown legacy dependencies are not swept into the invalidation.
Normal source deletion preserves retained bytes and the old document identity;
a replacement row at the same URL cannot silently become that evidence.

Extraction checks the catalog before constructing providers and again while
holding the existing publication lock. The text and attachment checksum must
match the retained extraction; an edited projection or replaced attachment cannot
borrow an old text-version identity. A retained artifact awaiting its own
text extraction cannot reuse old extracted text. A new text-extraction version
has a distinct receipt even if its text is identical. Unversioned legacy text
can retain its actual identity/hash, with a null archived text-version ID; it
does not gain invented download or extraction history. Unchanged checks, failed
fetches and changes to unconsumed documents preserve compatible knowledge.

The existing retrieval and admin withdrawal behavior handles these entries.
Admin parameters cannot clear the catalog or withdrawal timestamp. This slice
adds no controls, routes, schedule, provider client or replacement-generation
trigger. Existing source collection/text analysis still proceeds independently.

## Observed boundaries

| Workflow / variant | Verified outcome | Limit |
| --- | --- | --- |
| BG-02 / BG-04 / ADM-12 | Actual retained agenda summary plus separate retained minutes -> two extracted entries -> triage -> embeddings -> later admin search. Both distinctive claims appear first, then disappear after minutes replacement; independent context and the unchanged summary survive. | Deterministic providers; not extraction accuracy. |
| BG-04, receipt and retention | Entries preserve exact catalog, text version, review attributes and chunks after withdrawal, with a system audit for each. Source deletion retains bytes and does not transfer provenance to another row at the same URL. | Document dependency, not per-assertion semantic approval. |
| BG-02 / BG-04, compatibility | Identical bytes/text publication, failed fetch and unrelated transcript edits preserve exact knowledge attributes, retained version and zero queued extraction. | This does not implement a complete extraction-stage cache. |
| BG-04, late/pending work | A raw-document change during the provider call rejects all late entries and triage/ingestion. Replacement bytes with old text construct no provider until their text version is ready. Edited text or a replaced attachment cannot borrow a retained text-version ID. | Existing raw-document selection and text-size policy are unchanged. |
| BG-04, atomic correction | Failed withdrawal audit rolls back text publication, page replacement and all knowledge changes. Retry withdraws each known dependent once. | Uses existing audit persistence. |
| BG-04, concurrency | Separate PostgreSQL connections pause first knowledge registration, observe the text writer waiting on the shared lock, then persist both withdrawals without a retry. | One concrete interleaving, not universal concurrency certification. |
| ADM-11, later HTTP edit/read | Forged catalog/withdrawal parameters cannot restore the extracted source or erase its receipt; the later detail page displays Evidence withdrawn. | Existing session helper; no new authentication or browser control. |

## Execution and defect detection

The initial test reproduced invalid raw-source knowledge remaining in a later
HTTP search: 1 test / 14 assertions, one intended failure, no errors/skips.
The first implementation passed 1 / 27. Expanded regression passed 31 / 307;
the expanded targeted regression passed 65 / 620. Explicit starting-count checks
then passed 65 / 625. The two retained-projection cases first failed at the
provider-construction guard: 2 tests / 12 assertions, two intended failures,
zero errors/skips. The final targeted regression passed 67 tests / 641 assertions,
with zero failures/errors/skips.

Commands ran with `RAILS_ENV=test`, an isolated database and `PARALLEL_WORKERS=1`:

```sh
bin/rails db:schema:load
bin/rails db:migrate
bin/rubocop -A db/schema.rb
bin/rails test test/integration/knowledge_source_dependencies_test.rb
bin/rails test test/integration/knowledge_source_dependencies_test.rb test/jobs/extract_knowledge_job_test.rb test/integration/knowledge_summary_dependencies_test.rb test/integration/meeting_summary_source_withdrawal_test.rb test/services/meetings/parallel_summary_withdrawal_test.rb test/jobs/documents/source_version_retention_test.rb test/jobs/documents/text_version_test.rb
bin/rubocop
```

One expanded run exposed a fixture-cleanup error: teardown held cached extraction
rows after a worker replaced them. Its foreign-key error left synthetic data
behind, causing later setup/count failures (65 tests, two failures, ten errors).
Teardown now reloads the meeting; this slice's isolated database was reset and
the 65-test regression above passed. Those errors were not product defect proof.

Twelve bounded faults each use a clean passing baseline, one intended assertion
failure with no errors/skips, restoration and a passing rerun:

| Removed guard | Intended detection |
| --- | --- |
| Document withdrawal callback | Old raw-source claims remain in later HTTP search. |
| Stored document receipt | The two entries lose the consumed document identity. |
| Final source-current check | Late output creates knowledge after its source changes. |
| Pre-dispatch pending-text check | Old text constructs a provider after bytes change. |
| Text-version comparison | A different extraction inherits the older knowledge availability. |
| Withdrawal for a removed source | Retained knowledge remains available after source removal. |
| Audit in the originating transaction | Failed audit leaves the text publication committed. |
| Shared first-publication lock | The correcting writer does not wait for dependency registration. |
| Admin catalog parameter protection | An edit clears the retained source receipt. |
| Source snapshot comparison | Changed legacy text leaves extracted knowledge available. |
| Retained text comparison | Edited projection text constructs a provider using an older extraction ID. |
| Retained attachment comparison | Replaced bytes construct a provider using an older artifact/text identity. |

RuboCop inspected 708 files without offenses. Migration/schema formatting ran
locally and the diff contains only the new column, index and schema version.
Five Markdown files passed 216 local link/anchor checks and balanced fences;
`git diff --check` passed.
The owned synthetic meeting and admin fixtures were absent after the final runs.
Exact-head CI, browser-suite discovery, runtime smoke and review evidence are
recorded in the pull request.

## Remaining boundaries

Retrieval context consumed during knowledge extraction, stored pattern
dependencies and other generated knowledge-dependent narratives remain separate
work. The existing raw-document selection and truncation policy is not expanded
into campaign intake here. Legacy missing provenance stays unknown. Direct SQL
or callback-bypassing changes are not covered by these publication checks.

This is not the complete #238 stage cache, spending ledger or bounded retry
implementation. Re-running the existing knowledge job is not newly certified
as a zero-call cache hit. Those cost controls still precede new automatic paid
enrichment. No paid application AI, production operation, backfill, merge or
deployment ran, and authorized paid-pilot spending remains zero.
