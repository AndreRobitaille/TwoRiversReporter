# Extracted knowledge and summary dependencies: November 7, 2026

Based on `ba7dab06` ([PR #262](https://github.com/AndreRobitaille/TwoRiversReporter/pull/262)).
Implementation revisions: `9765a0de`, with summary-version follow-up `f8281fd9`.
Local verification uses Ruby 4.0.9,
Rails 8.1.4.1, isolated PostgreSQL 18.6 and deterministic provider/download/embedding
responses. The browser journey uses the repository's Chrome/Capybara harness.

## Requirements and acceptance

Parent [#234](https://github.com/AndreRobitaille/TwoRiversReporter/issues/234),
foundation [#236](https://github.com/AndreRobitaille/TwoRiversReporter/issues/236),
the [evidence correction contract](../superpowers/specs/2026-11-07-council-accountability-design.md#evidence-validation-and-correction-contract),
[knowledge constraints](../DEVELOPMENT_PLAN.md#knowledgebase--contextual-summaries),
and [QA procedure](maintenance-and-qa.md) govern this slice.

Acceptance was derived before implementation: a known invalid summary must not
leave its extracted knowledge available to fresh retrieval or silently approve
late work. Retain the original dependency and review history, withdraw known
dependents atomically with an audit, and preserve independent manual knowledge.
A dependency receipt is not factual approval. The existing proposal/triage policy
still applies; these synthetic tests do not establish extraction accuracy.

## Implementation

New extraction stores a nullable summary reference and versioned receipt on each
`KnowledgeSource`. The receipt retains summary and meeting identity, summary type
and a canonical payload hash. It does not copy the source document or claim a
human review. Existing records receive no inferred provenance or backfill.

Normal summary payload changes, withdrawal and destruction invalidate mismatched
known dependents in the same transaction. Summary destruction clears the foreign
key but retains the receipt's original identity. Knowledge text, origin, approval
status, confidence, topic links and indexed chunks remain inspectable. A separate
withdrawal timestamp controls availability; future summary regeneration cannot
silently restore an older entry. Timestamp-only changes and JSON key ordering do
not invalidate compatible knowledge. New extraction gets its own current receipt.

`KnowledgeSource.retrievable` centralizes approved, active and non-withdrawn
eligibility. Retrieval, topic-generation dependency capture and pattern inputs use
it. Pattern input also excludes withdrawn briefings. Triage excludes withdrawn
entries and checks current row state plus the consumed payload after the provider
returns. The payload check matters even when two changes share a timestamp.

Ingestion checks availability before constructing an embedding provider, computes
outside locks, and publishes all chunks only if the source is still available and
its text/file input matches. A failed provider preserves the previous index; a
late response cannot replace a subsequent successful ingestion. The asynchronous
indexing period after an ordinary content edit is otherwise unchanged.

Knowledge creation already shares the supporting summary's publication lock;
withdrawal locks dependent knowledge rows after that summary. Triage and ingestion
only acquire the knowledge row for final persistence, without holding a database
lock across a provider call. The tested first-publication interleaving proves a
concurrent withdrawal waits and finds both new entries. It is not a proof of all
writers or arbitrary concurrent topic-link edits.

The shared summary publication guard also compares payload, identity and withdrawal
state, not only the timestamp. A summary edit or withdrawal during a provider call
rejects the old response even when both changes share a timestamp. This applies to
new knowledge and replacement summaries without scheduling a replacement call.

The existing admin index/detail pages identify withdrawn evidence separately from
review status. Re-ingest refuses it without queuing work. Editing or approving a
withdrawn entry does not clear the receipt/withdrawal, and those fields are not
permitted request parameters. The detail page now renders action feedback using
the existing admin flash style; its absence was reproduced in the browser.

## Behavioral evidence

| Workflows / variant | Boundary and meaningful result | Limits |
| --- | --- | --- |
| BG-02 / BG-04 / ADM-12 | Real retained minutes and identity correction -> briefing -> saved preview -> two extracted and triaged knowledge entries -> ingestion -> fresh retrieval/admin search. Both known dependents disappear; an independent manual entry and an unlinked legacy entry remain. Exact source IDs, topic links and distinctive text are checked. | Providers/downloads/embeddings are deterministic; legacy provenance remains unknown. |
| BG-04 / ADM-20 | Withdrawal audit failure rolls back the originating correction, summary and both knowledge entries. A retry withdraws once. Original receipt, body, review state and chunks survive. | Existing audit persistence, not a new audit control. |
| BG-04, replacement/removal | Changed summary generation withdraws prior entries; new extraction has new receipts without inheriting old availability. Ordinary summary destruction retains knowledge and its original summary identity. | No complete historical summary archive is added. |
| BG-04, compatibility | Timestamp changes and JSON key reordering preserve exact knowledge attributes and queue no work. | Receipt compatibility, not a completed extraction-stage cache. |
| BG-04, late work | Summary edits and withdrawals with unchanged timestamps reject late knowledge or summary output. Late triage cannot approve withdrawn or edited input. Late embedding output cannot replace retained or newer chunks; provider failure retains the whole previous index and a successful retry preserves the final passage. Already-withdrawn jobs construct no provider. | No general spending ledger or retry-budget implementation. |
| BG-04, future inputs | Topic generation receipts omit withdrawn knowledge. Pattern inputs omit withdrawn knowledge, inactive notes and withdrawn briefings while preserving independent inputs. | Existing stored patterns and in-flight pattern generation are separate work. |
| ADM-11, HTTP | Allowed detail first; then withdrawal notice, rejected re-ingestion, retained body/review state, and an edit that cannot clear server-owned provenance or reactivate availability. | Test session helper; no new authentication behavior. |
| ADM-11, browser | Captured-email sign-in, sidebar navigation, real Re-ingest/Turbo/CSRF/cookies, queued ingestion and stored chunk first; then withdrawal notice, visible refusal, zero queued ingestion and retained chunk on later reads. Index keeps Approved review status beside Evidence withdrawn. | Synthetic passkey establishes eligibility, not a new credential ceremony. Desktop render inspected; no responsive redesign. |
| BG-04, concurrency | Separate PostgreSQL connections pause first knowledge creation, observe the correcting writer waiting on a real row lock, then verify both dependents withdrawn without a deadlock retry. | Bounded interleaving, not general concurrency certification. |

## Execution and defect detection

The initial pipeline check failed with the two withdrawn dependents still present
in fresh retrieval: 1 test / 8 assertions, one intended failure, zero errors/skips.
The first corrected baseline passed 1 / 25. The expanded regression passed
68 tests / 622 assertions before the final topic-input case. The initial focused
integration baseline passed 14 / 157, and the browser journey passed 1 / 34.
All passing counts have zero failures/errors/skips.

The follow-up summary-version regression passed 90 tests / 897 assertions,
including both same-timestamp cases and the source/fact/agenda withdrawal,
knowledge extraction/triage, pruning and concurrent publication paths. The
new cases first reproduced stale knowledge publication (1 / 4, one failure)
and stale summary restoration (1 / 3, one failure), with no errors/skips.

Commands use `RAILS_ENV=test`, an isolated test database, and `PARALLEL_WORKERS=1`;
application and browser suites run serially against that database:

```sh
bin/rails db:migrate
bin/rubocop -A db/schema.rb
bin/rails test test/integration/knowledge_summary_dependencies_test.rb test/jobs/extract_knowledge_job_test.rb test/jobs/auto_triage_knowledge_job_test.rb test/jobs/extract_knowledge_patterns_job_test.rb test/services/retrieval_service_test.rb test/models/knowledge_source_test.rb test/integration/agenda_briefing_context_test.rb test/services/meetings/parallel_summary_withdrawal_test.rb
bin/rails test test/integration/knowledge_summary_dependencies_test.rb
bin/rails test test/system/knowledge_withdrawal_journey_test.rb
bin/rails test test/integration/knowledge_summary_dependencies_test.rb test/integration/agenda_briefing_context_test.rb test/integration/meeting_summary_fact_dependencies_test.rb test/integration/meeting_summary_source_withdrawal_test.rb test/jobs/extract_knowledge_job_test.rb test/jobs/auto_triage_knowledge_job_test.rb test/jobs/prune_hollow_appearances_job_test.rb test/services/meetings/parallel_summary_withdrawal_test.rb --seed 64056
bin/rails test
bin/rubocop
```

Nineteen isolated faults each failed the intended assertion with one failure,
zero errors/skips, then passed after restoration. Commands used the corresponding
integration or system file with `-n /test_name_fragment/`.

| Fault | Demonstrated detection |
| --- | --- |
| Omit summary withdrawal callback | Fresh retrieval still returns both invalid entries. |
| Omit the new source-summary reference | Correction cannot find the two known dependents. |
| Ignore withdrawal during retrieval | Withdrawn rows still appear in fresh context. |
| Audit/withdraw after commit | Audit failure leaves the originating correction committed. |
| Omit summary-destruction callback | Retained knowledge stays available after its supporting summary disappears. |
| Ignore withdrawal at triage publication | Late output approves withdrawn entries even when timestamps match. |
| Ignore triage payload changes | Late output approves newly edited content with an unchanged timestamp. |
| Omit ingestion's early availability guard | A queued withdrawn entry constructs an embedding provider. |
| Ignore withdrawal at chunk publication | Late embedding output replaces retained chunks. |
| Ignore ingestion input version | Old output overwrites a completed ingestion of newer text. |
| Delete chunks before requesting embeddings | Provider failure destroys the complete previous index. |
| Ignore withdrawal in pattern knowledge inputs | Invalid first-order text enters the next pattern prompt. |
| Include withdrawn briefings in patterns | A withdrawn briefing headline enters the pattern prompt. |
| Queue withdrawn Re-ingest from admin | The browser sees a queued result instead of the refusal. |
| Omit summary locking during first knowledge publication | The concurrent correcting writer fails to wait for dependency registration. |
| Ignore withdrawal in topic-generation receipts | Invalid knowledge remains in the captured dependency set. |
| Queue ingestion after editing withdrawn text | The admin edit silently queues forbidden follow-up work. |
| Omit payload fields from the summary publication version | Late knowledge output survives a changed summary with the same timestamp. |
| Omit withdrawal state from the summary publication version | Late summary output silently restores a withdrawal with the same timestamp. |


The new browser test initially lacked its job-test helper; that errored run is
not behavioral evidence. The subsequent run exposed missing action feedback
(1 / 20, one failure, zero errors/skips), leading to the scoped flash rendering
fix. The badge assertion was then corrected for the existing uppercase CSS.
The integration concurrency observer now reads PostgreSQL activity uncached;
a cached first observation had timed out despite the real writer waiting.
The original retained-state assertion reloads records after triage; a briefing
rollback assertion uses its actual withdrawal field instead of a nonexistent
instance predicate. These test-setup/assertion corrections are not product faults.
An interrupted follow-up run left one synthetic meeting/topic in the isolated
test database. Two regression runs hit duplicate-name setup errors until those
specific records were removed; the 90-test rerun above then passed. No production
or development data was involved.

The full application suite at `9765a0de` passed 2,395 tests / 15,856 assertions,
zero failures/errors and one existing PromptRun fixture skip. RuboCop inspected
705 files without offenses. The additive migration ran locally; schema formatting
was corrected and the schema diff was inspected. Five Markdown files passed
213 local link/anchor checks and balanced fences; `git diff --check` passed.
Exact-head CI/runtime and automatic-review evidence is recorded in the pull
request description.

## Remaining scope and cost

Legacy knowledge without a receipt remains unverified. Additional raw-text inputs
outside the supporting summary's recorded dependencies, already-produced patterns,
complete pattern input manifests and late-pattern rejection, participant inputs,
and withdrawal of other already-generated knowledge-dependent narratives remain
separate work. Direct SQL/callback-bypassing mutations and arbitrary concurrent
association edits are not covered by this slice. Original source availability,
extraction accuracy, campaign coverage and service eligibility are not inferred
from these dependency checks.

The migration is additive and nullable, with no backfill. No new schedule or
automatic replacement-generation trigger was added. Existing source collection
and independent deterministic updates remain available. #238's stage reuse,
spending reservations and retry budgets still precede any new paid dispatch;
authorized paid-pilot spending remains zero. No paid AI, production operation,
production backfill, merge or deployment ran.
