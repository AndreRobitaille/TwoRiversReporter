# Meeting summaries and structured fact dependencies: November 7, 2026

Based on `ecaad540` ([PR #260](https://github.com/AndreRobitaille/TwoRiversReporter/pull/260)).
Runtime/test revision: `b49e9176`.
Local verification uses Ruby 4.0.9, Rails 8.1.4.1, PostgreSQL 18.6 and an isolated
synthetic database. Provider responses and downloads are deterministic fixtures.

## Requirements and acceptance

Parent [#234](https://github.com/AndreRobitaille/TwoRiversReporter/issues/234),
foundation [#236](https://github.com/AndreRobitaille/TwoRiversReporter/issues/236),
the [evidence/correction contract](../superpowers/specs/2026-11-07-council-accountability-design.md#evidence-validation-and-correction-contract),
[current-result publication](../superpowers/specs/2026-11-07-council-accountability-design.md#from-a-changed-source-to-an-updated-page)
and [QA procedure](maintenance-and-qa.md) govern this slice.

Acceptance was derived before implementation: a changed extracted vote can
invalidate meeting prose even when the document is unchanged. Record the actual
structured motion context consumed by analysis. Reject a late response against
changed context, including first publication. Atomically withdraw known dependent
summaries and illustrations when facts are republished, with retained receipts and
an automated audit. Later resident reads must show current facts without the old
prose. Compatible refreshes must preserve supported analysis; unchanged extraction
reruns and deterministic withdrawal must not request AI or enqueue rewrites.
Unknown legacy dependencies cannot be reconstructed by assumption.

## Implementation and boundaries

`Meetings::MotionContext` retains a versioned receipt for the existing rendered
motion context: meeting identity and metadata, context hash, input status, original
fact publication and vote extraction IDs, and the extraction's source snapshot.
The context still contains motion descriptions, linked agenda titles, outcomes
and deterministic vote totals. The receipt is server-owned and protected through
citation-only repair. It establishes provenance, not approval of the extractor's
interpretation. The provider receives the same context text as before.

Final publication checks the receipt after the provider responds. Compatibility
compares the consumed context and source, not merely publication/extraction IDs;
an attendance refresh or identical vote extraction can preserve the original
summary and receipt. The capture and final check use the existing per-meeting
summary advisory lock. Provider execution happens outside it.

`Minutes::Publish` now acquires that lock before projection and holds it through
`Meetings::WithdrawFactSummaries`, audit and image invalidation in one transaction.
The first summary cannot be inserted invisibly between projection and withdrawal.
The existing Meeting `FOR NO KEY UPDATE` lock permits foreign-key checks during
first summary insertion. A failed audit rolls back publication; a later retry
uses the completed extraction without constructing a provider. This does not
prove every writer interleaving.

Withdrawal compares one newly captured motion context against each known receipt.
It retains the original source, extraction, publication and generated payload.
The automated audit records before/current receipts and publication snapshots.
Dependent pending, processing, ready and failed illustrations become superseded;
attached files remain retained. Source withdrawal also follows the receipt's
minutes dependency when an agenda preview's primary catalog contains only an
agenda. A newly discovered unavailable URL cannot substitute for a pinned source.

## Behavioral verification

The [integration tests](../../test/integration/meeting_summary_fact_dependencies_test.rb)
use real extraction/publication jobs, persisted records, HTTP routing, API auth,
serialization and later reads. Only transport/provider responses are synthetic.
The fixture deliberately starts with an incorrect extracted `no` and explicitly
refreshes it to `yes`; it is a propagation test, not source-accuracy evidence.

| Workflows / variant | Boundary and meaningful result | Limits |
| --- | --- | --- |
| BG-02 / BG-04 / RES-06 / RES-07 / RES-10 / RES-13 | Prove the old summary, one No member vote and API search result; explicitly replace extracted facts from unchanged minutes; later conditional HTML and API omit old prose, the member has one Yes vote, official URL survives, and API freshness includes the changed meeting. | Open-mode resident HTML and authenticated API; no access-policy changes. |
| BG-02 / ADM-20 | Audit failure rolls back the publication and live projection; retry uses the retained completed extraction. The audit page names the meeting and Automated actor. | HTTP admin session established with existing integration helper; login UI is unchanged. |
| BG-02 / BG-04 | Unchanged reruns forbid provider construction and enqueue nothing. Compatible attendance and identical vote refreshes retain exact summary attributes and the original receipt. | Explicit changed-template extraction uses a deterministic provider; no automatic reanalysis is added. |
| BG-04 / RES-06 | A fact change during first-summary generation rejects late output and its followups; explicit current generation restores prose and the current receipt. | No provider cancellation or request coalescing claim. |
| BG-02 / BG-04 | Separate PostgreSQL connections pause first summary insertion, start fact publication, observe a lock wait, then finish both transactions with the old-context summary withdrawn and no deadlock retry. | One concrete concurrency interleaving. |
| BG-02 / RES-06 | Agenda-only primary catalog still pins consumed minutes; changed minutes withdraw the preview. A new unavailable URL leaves the pinned supported summary intact. | Known dependencies only; no guessed replacement source. |
| BG-02 / RES-06 | Date reprojection withdraws old meeting context using cached stages. Missing/null legacy receipts stay unknown rather than being inferred. | Metadata invalidation occurs on fact publication; not every direct meeting edit is covered. |
| BG-04 | Citation-only repair preserves the server-owned motion receipt. | The test does not validate semantic fact accuracy. |

## Execution and defect detection

The first requirements-derived test failed before implementation: the old summary
remained in later HTML beside the corrected vote (1 test, 11 assertions, one
intended failure, no errors/skips). The final focused baseline passed 12 tests /
152 assertions, zero failures/errors/skips. The earlier regression command passed
49 tests / 538 assertions, zero failures/errors/skips; later assertions added
member-page and admin-audit reads and the explicit unknown-provenance case.

Commands use `RAILS_ENV=test`, the isolated PostgreSQL database and
`PARALLEL_WORKERS=1`. Application and browser suites run serially:

```sh
bin/rails test test/integration/meeting_summary_fact_dependencies_test.rb
bin/rails test test/integration/meeting_summary_fact_dependencies_test.rb test/integration/meeting_summary_source_withdrawal_test.rb test/services/meetings/parallel_summary_withdrawal_test.rb test/jobs/minutes/fact_publication_test.rb test/jobs/minutes/parallel_publication_test.rb test/integration/council_fact_withdrawal_test.rb
bin/rails test
bin/rails test test/system/meeting_summary_withdrawal_journey_test.rb
bin/rubocop
```

Nine bounded fault experiments each failed the intended assertion with zero test
errors, then passed after restoring the original implementation. Each targeted
command used the integration file above with `-n /test_name_fragment/`.

| Fault | Demonstrated detection |
| --- | --- |
| Omit fact-dependent summary withdrawal | Later HTML still contains the old synthetic claim. |
| Omit final motion-context check | A stale first summary is saved after a fact change during generation. |
| Remove the fact publisher's summary advisory lock | Publication no longer waits for the first summary insertion. |
| Move summary withdrawal after fact commit | Failed audit leaves the new publication committed instead of restoring the old one. |
| Ignore sources nested in the motion receipt | Agenda preview stays published after its supporting minutes change. |
| Treat publication ID as the compatibility condition | A compatible attendance refresh changes supported summary attributes. |
| Ignore captured meeting metadata | Date reprojection leaves the old-context summary published. |
| Keep the dependent image ready | The summary withdraws but its illustration does not become superseded. |
| Infer a dependency from a null legacy receipt | The unknown summary changes during fact replacement. |

The existing pending-context test now calls the extracted capture service directly;
its presence/absence assertions are unchanged. The unused job wrapper was removed.
No behavioral assertion was dropped during this refinement.

`bin/rails test` at `b49e9176` passed 2,363 tests / 15,441 assertions,
zero failures/errors and one existing PromptRun fixture skip. The existing
withdrawal browser journey passed 1 test / 13 assertions with zero failures,
errors or skips using Chrome 157.0.8103.38. It covers the source-change UI and
navigation as regression evidence; the new fact-change boundary is exercised by
the HTTP/job tests above. `bin/rubocop`
inspected 700 files without offenses. Six Markdown files passed 283 local
link/anchor and balanced-fence checks; `git diff --check` passed.

## Remaining scope and cost

Subsequent [saved agenda dependency work](agenda-summary-dependencies-2026-11-07.md)
adds durable topic-context receipts and withdrawal. The scope below records this
earlier slice as originally verified.

This adds **structured motion dependencies of saved meeting summaries**. Participant
and roster inputs, knowledge context, previously consumed topic-briefing context,
all direct mutable-row writers and complete narrative history remain separate work.
Legacy summaries without a usable receipt remain unverified. Reprojection handles
captured meeting metadata, but direct metadata edits do not all trigger withdrawal.
There is no UI redesign, new migration, backfill or reconstruction of old receipts.

The existing nightly summary repair check remains unchanged. Withdrawal does not
become an automatic paid regeneration request. Meeting-stage caching, request
coalescing and explicit spending/retry limits remain #238 prerequisites before new
paid dispatch. No new schedule, paid call, production operation, merge or deployment
ran. Campaign-source gaps and real extraction evaluation remain separate from
these synthetic propagation checks.
