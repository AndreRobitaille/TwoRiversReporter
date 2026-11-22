# Saved meeting summaries and source withdrawal: November 7, 2026

Based on `f11ca22f` ([PR #259](https://github.com/AndreRobitaille/TwoRiversReporter/pull/259)).
The initial withdrawal implementation is `ec6653fd`; reader/citation expectations
were reconciled at `133dad5c`. Final runtime/test revision: `c119c050`.
Local verification uses Ruby 4.0.9, Rails 8.1.4.1, PostgreSQL 18.6 and an isolated
synthetic database. Provider responses and downloads are deterministic fixtures.

## Requirements and acceptance

Parent [#234](https://github.com/AndreRobitaille/TwoRiversReporter/issues/234),
foundation [#236](https://github.com/AndreRobitaille/TwoRiversReporter/issues/236),
the [evidence/correction contract](../superpowers/specs/2026-11-07-council-accountability-design.md#evidence-validation-and-correction-contract)
and [QA procedure](maintenance-and-qa.md) govern this slice.

Acceptance was derived before implementation: a changed or removed document must
withdraw saved meeting analysis with a recorded dependency, before new prose is
available. Original source versions and generated payloads remain inspectable;
independent reporting survives. Later HTML, metadata, API, search and consumers
must omit withdrawn analysis. Source publication, audit and withdrawal must be
atomic. First publication and late responses cannot evade the check. Unchanged
inputs and failed fetches must not withdraw analysis or construct providers.
Recovery uses explicit checked generation; this slice adds no paid dispatch.

## Implementation and boundaries

`MeetingSummary.evidence_withdrawn_at` separates published analysis from retained
payloads without a default scope. The nullable migration performs no backfill.
`Meetings::WithdrawSourceSummaries` follows existing `source_catalog` document
identities and compares complete source snapshots in the final source transaction.
Changed bytes, text, provenance or deletion invalidate a known receipt. The audit
records an Automated actor, meeting identity, method, reason and before/current
source snapshots. Dependent pending, processing, ready and failed illustrations
become superseded while attached files remain retained.

`Meetings::SummaryPublication` uses a transaction advisory lock per meeting to
serialize document withdrawal, first summary publication and checked consumers.
It does not acquire the Meeting row after a Document row, avoiding inversion with
existing minutes writers. A moved document locks its previous and current meeting
identities in order. Agenda topic locks precede summary row locks. Publication
rechecks the captured row version and source catalog after waiting; provider work
runs outside these locks. Rejected full recaps preserve independent lower-tier
summaries and do not continue pruning, knowledge or topic generation.
Citation-only repair now follows the source writer's document-before-summary row
order. Summary publication/consumption uses `FOR NO KEY UPDATE`, allowing dependent
image foreign-key checks. Final meeting-image publication also uses that lock mode
on its Meeting row, allowing concurrent knowledge insertion's foreign-key check.
The tested races are not a proof of every writer interleaving.

Resident selectors and API search filter withdrawn summaries. Topic fallback
item descriptions also skip them. The meeting page explains withdrawal and keeps
official links. Queued knowledge, pruning and image work skips withdrawn inputs;
knowledge output checks its captured summary again before saving. Image output
checks publication and the original fingerprint under the summary row lock before
becoming ready. Manual images without a summary dependency remain independent.

## Behavioral verification

| Workflows / variant | Boundary and meaningful result | Limits |
| --- | --- | --- |
| BG-02 / RES-06 / RES-07 / RES-13, source change | Actual download and text publication → deterministic summary with two distinct items → later conditional HTML, API item identities, API summary/search/freshness. Prove both claims first; then both absent, official URL retained, image superseded, raw summary and artifact history retained. | HTTP requests exercise real routing, auth, serialization and persistence; transport/provider fixtures are synthetic. |
| BG-02 / ADM-20, unchanged/failure | Identical bytes, metadata touch and failed fetch preserve exact summary attributes with provider construction forbidden. Failed audit persistence rolls source replacement and withdrawal back; later HTML still presents the supported claim. Audit page names the affected meeting and Automated actor. | DownloadJob catches/logs operational errors; assertions inspect persisted state rather than expecting an exception. |
| BG-02 / RES-06, removal/recovery | Delete supporting document, preserve an independent summary, create a replacement source and explicitly generate a checked preview. New document receipt and restored publication reach later HTML/API. | No automatic rewrite or production repair. |
| BG-04, late work | Source changes during summary, knowledge and image responses; stale output cannot restore prose, create knowledge or publish an image. A newer checked summary also wins over a late response from unchanged sources. | Deterministic provider callbacks, not paid network execution. |
| BG-02 / BG-04, first publication | Separate PostgreSQL connections pause the first insert, start source replacement, observe its lock wait, release publication, and verify both transactions finish with the newly stored summary withdrawn. | One concrete first-publication interleaving; no request coalescing claim. |
| BG-04, queued consumers | Actual knowledge/pruning/image jobs run after withdrawal with providers forbidden; topic links and appearances remain intact. | Already-created knowledge or topic prose is not retrospectively withdrawn here. |
| BG-04, concurrent consumers | Pause knowledge insertion after its summary check, start image generation, observe the image lock wait, then release knowledge. Both records publish and neither job queues a deadlock retry. | Separate PostgreSQL connections and real jobs; image/knowledge providers are deterministic. |
| RES-05 / RES-06 / RES-07, browser | Read both claims, change source, revisit, see withdrawal and official link, use Back to Meetings and revisit again. | No external source navigation or responsive redesign; browser Chrome 157.0.8103.38. |

Tests: [HTTP/source transitions](../../test/integration/meeting_summary_source_withdrawal_test.rb),
[concurrent first publication](../../test/services/meetings/parallel_summary_withdrawal_test.rb),
[browser journey](../../test/system/meeting_summary_withdrawal_journey_test.rb).
The shared fixture is explicitly synthetic and uses real jobs and persistence.

## Execution and defect detection

At `133dad5c`, the reader/citation regression suite passed: 99 tests, 696 assertions, zero
failures/errors/skips. The browser journey passed: 1 journey, 13 assertions,
zero failures/errors/skips. At `ec6653fd`, the new integration/concurrency tests
passed: 8 tests, 111 assertions. An earlier targeted regression run
covered summarization, knowledge extraction, pruning, image generation, agenda
context and concurrent source withdrawal: 87 tests, 480 assertions, zero
failures/errors/skips. The final tests add the full-recap rejection case and
stronger allowed-before-denied knowledge/image evidence.

Commands use `RAILS_ENV=test`, the isolated PostgreSQL database and
`PARALLEL_WORKERS=1`; browser tests run serially with application tests:

```sh
bin/rails test test/integration/meeting_summary_source_withdrawal_test.rb test/services/meetings/parallel_summary_withdrawal_test.rb
bin/rails test test/system/meeting_summary_withdrawal_journey_test.rb
bin/rubocop
```

The 99-test command ran `bin/rails test` with
`test/controllers/meeting_citations_test.rb`, `test/helpers/meetings_helper_test.rb`,
`test/services/citations/pipeline_test.rb`, `test/jobs/topics/generation_evidence_test.rb`,
`test/integration/meeting_summary_source_withdrawal_test.rb`,
`test/services/meetings/parallel_summary_withdrawal_test.rb` and
`test/services/citations/summary_repair_test.rb`.

The migration ran only locally. `bin/rubocop -A db/schema.rb` normalized schema
formatting; the reviewed diff contains only the version and new nullable column.
Five Markdown files passed 273 local link/anchor and balanced-fence checks.

Twelve bounded local fault experiments each failed the intended assertion with zero
test errors, then passed after restoration:

| Fault | Demonstrated detection |
| --- | --- |
| Omit summary withdrawal | Later HTML still contains the withdrawn claim. |
| Withdraw after commit | Failed audit cannot roll back the changed source snapshot. |
| Omit source publication check | Stale full recap reaches citation validation instead of clean rejection. |
| Omit captured-row version check | Older output replaces a newer checked summary. |
| Omit advisory publication lock | Source replacement does not wait for first summary insertion. |
| Accept late knowledge | A changed-source response creates an extra knowledge entry. |
| Accept late image | A changed-source image becomes ready. |
| Select withdrawn resident summary | Withdrawn claim returns to later HTML. |
| Leave withdrawal flag during recovery | Explicit checked generation remains unpublished. |
| Withdraw unchanged snapshot | Metadata touch changes the supported summary's attributes. |
| Lock the summary key during knowledge publication | Concurrent image reservation deadlocks on its foreign key; a ready image is missing. |
| Lock the Meeting key during final image publication | Concurrent knowledge insertion deadlocks on its foreign key; both outputs cannot publish. |

Initial fixture failures were corrected, not counted as defect detection: audit
assertions now identify the affected meeting rather than counting all historical
events, the knowledge response has the required reasoning, and browser cleanup
uses the job-test helper. The local browser's old default driver was bypassed with
the already-installed matching Chrome 157 driver. These checks do not establish
source interpretation accuracy or live provider availability.

The initial full run exposed old assumptions in citation/reader tests: stale
summaries stayed visible, changed input raised a citation error, and helper
doubles lacked publication state. Updated assertions follow the binding withdrawal
contract while still proving original payload retention and valid packet citation
resolution from retained history. Helper fixtures now use actual unsaved
MeetingSummary objects. The withdrawal copy avoids promising a link after source
deletion. No citation-resolution implementation or priority rule changed.

`bin/rails test` at `133dad5c` passed 2,350 tests and 15,280 assertions with zero
failures/errors and one existing PromptRun fixture skip. The later concurrency
test reproduced a real foreign-key deadlock and a queued job retry in the test
log. After the lock-mode correction at `c119c050`, the concurrency/source, knowledge and image
regression command passed 47 tests / 245 assertions, zero failures/errors/skips:
`bin/rails test test/services/meetings/parallel_summary_withdrawal_test.rb test/integration/meeting_summary_source_withdrawal_test.rb test/jobs/extract_knowledge_job_test.rb test/services/generated_images/generator_test.rb test/jobs/generated_images/generate_for_meeting_job_test.rb`.
Final `bin/rubocop` inspected 697 files without offenses; `git diff --check` passed.

## Remaining scope and cost

Subsequent [summary fact-dependency work](meeting-summary-facts-2026-11-07.md)
adds structured motion receipts and fact-publication withdrawal. The scope below
records this source-withdrawal slice as originally verified.

This covers **known document dependencies of saved meeting summaries**. Legacy
summaries without catalogs stay unverified. Fact-publication changes from
unchanged documents, previously consumed agenda topic-briefing context, knowledge
context and other unrecorded dependencies still need durable receipts and
propagation. No missing provenance is guessed. Existing lower-tier cleanup and
summary replacement remain mutable; this is not a complete narrative archive.

No new schedule, paid call, production mutation, backfill, merge or deployment
ran. The existing nightly repair check is unchanged: a withdrawn nonempty summary
does not become an automatic paid regeneration request. Meeting-wide stage cache,
request coalescing and explicit spending/retry limits remain #238 prerequisites
before new paid processing is enabled. Existing source interpretation quality,
campaign-material gaps and owner validation from #235 remain distinct from these
synthetic propagation checks.
