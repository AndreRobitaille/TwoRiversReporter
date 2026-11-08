# Saved agenda previews and topic dependencies: November 7, 2026

Based on `2ce9c8d0` ([PR #261](https://github.com/AndreRobitaille/TwoRiversReporter/pull/261)).
Initial implementation: `eef8c72f`; main regression revision: `0f5d88fd`;
admin alias-move review fix: `f1110196`.
Local verification uses Ruby 4.0.9, Rails 8.1.4.1, PostgreSQL 18.6 and an isolated
synthetic database. Provider responses and downloads are deterministic fixtures.

## Requirements and acceptance

Parent [#234](https://github.com/AndreRobitaille/TwoRiversReporter/issues/234),
foundation [#236](https://github.com/AndreRobitaille/TwoRiversReporter/issues/236),
the [correction contract](../superpowers/specs/2026-11-07-council-accountability-design.md#evidence-validation-and-correction-contract)
and [QA procedure](maintenance-and-qa.md) govern this slice.

Acceptance was derived before implementation: a saved preview must stop presenting
known-invalid topic context after the briefing changes or is withdrawn. Retain
what was consumed, withdraw dependent summaries and illustrations atomically with
an audit, reject stale work, and preserve unrelated reporting. A correction to a
historical meeting can affect a different future meeting; later HTML, API search
and incremental reads must reflect that withdrawal. Metadata-only changes and
unconsumed prose must not invalidate supported output. No replacement AI is
requested by deterministic withdrawal.

## Implementation and limits

`Topics::AgendaBriefingContext` now supplies a versioned, server-owned receipt
containing the agenda matching tokens and the exact consumed topic/briefing IDs
and rendered sections. `SummarizeMeetingJob` stores it separately from official
source citations. This is generated background, not a new official source or
approval of an interpretation. Citation-only repair preserves the receipt.
Existing matching, six-topic cap and 1,200-character editorial excerpt remain.

Normal TopicBriefing and TopicAlias saves/deletions acquire their parent topic
locks in ID order before writing. Topic name, status and impact updates, plus
topic deletion, also check known dependents. The existing admin alias-move action
uses the checked model update and records its review event in the same transaction.
`Meetings::WithdrawAgendaSummaries`
compares the captured sections and their continued eligibility, using one
transaction for the triggering mutation, summary flag, audit and image status.
The original payload and consumed context remain retained. A merge or deletion
does not silently replace the recorded identity with another topic or briefing.

The topic locks also cover first preview publication, when there is no summary
row yet. Withdrawal does not acquire meeting advisory locks, because source
writers acquire those before topics. Checked summary consumers lock topics before
summary rows. Knowledge publication includes its additional topic references in
that sorted lock set and rechecks name/alias mappings after waiting; a changed
mapping discards the result. Only entries meeting the existing confidence cutoff
participate in that check; rejected proposals cannot block an independent entry.
Retained knowledge still has proposed status, not factual approval. Pruning
includes the meeting's linked topic IDs.
Provider execution remains outside these locks. The tested interleavings are not
a proof of every writer or concurrent association edit.

API meeting freshness now includes summary withdrawal timestamps, independently
of the available-analysis timestamp. This lets an incremental reader discover a
withdrawn preview even when that meeting and its own agenda did not change. It
does not advertise the withdrawn summary as available analysis.

## Behavioral verification

The [agenda integration checks](../../test/integration/agenda_briefing_context_test.rb)
exercise actual jobs, source publication, identity correction, topic merge,
model callbacks, persisted records and later HTTP/API reads. External provider
and download responses are synthetic; the civic claims are not about real people.

| Workflows / variant | Boundary and meaningful result | Limits |
| --- | --- | --- |
| BG-02 / BG-04 / RES-06 / RES-13 | Two briefings supply a saved preview; identity correction withdraws one briefing and its dependent preview/image. Retain the original payload, both consumed identities and audit. A separate preview using only the unaffected topic stays unchanged. | Open HTML and authenticated API; existing access policy is unchanged. |
| BG-02 / RES-06 / RES-13 / RES-14 | Historical source replacement withdraws a future meeting's preview whose official catalog contains only its own agenda and whose motion receipt has no minutes. Conditional HTML returns changed content, API search omits the old claim, and `updated_since` includes the future meeting. | Real source job and later requests; deterministic transport. |
| BG-04 / ADM-06 / ADM-07 / ADM-08 | Name, approval, impact, alias relevance, briefing removal and actual topic merge invalidate consumed context. The original receipt is retained and an independent target-topic preview survives the merge. | Model/service boundary for these existing controls; no new admin UI. |
| ADM-08 / RES-06 / RES-13, alias move | An authenticated admin POST moves the relevance alias and records the reason; its original preview/image withdraw, original payload and audit survive, later anonymous HTML and API omit the claim, and a separate target-topic preview stays unchanged. | Actual HTTP action; existing controls and browser interaction are unchanged. |
| BG-04 / ADM-20 | Failed withdrawal audit rolls back the briefing and summary; later reads still show the supported version. A retry withdraws once with an Automated actor and before/current context. | Audit persistence verified; unchanged audit UI is covered by existing tests. |
| BG-04, compatible updates | Timestamp changes, record content, description and prose beyond the consumed excerpt preserve exact summary attributes and queue no jobs. A changed consumed coming-up headline withdraws the preview. | This is dependency compatibility, not general meeting-generation caching. |
| BG-04, recovery and consumers | Explicit regeneration restores a current receipt and publication. Late knowledge output from changed context is discarded; already-withdrawn queued knowledge/pruning jobs do not construct providers. Citation repair retains the server receipt. | Previously created knowledge is not retrospectively withdrawn here. |
| BG-04, concurrency | Separate PostgreSQL connections verify first preview versus direct briefing mutation, waiting knowledge versus context withdrawal, additional-topic knowledge links versus a multi-topic writer, and alias reassignment while knowledge waits. Assert persisted outcomes and no deadlock retries. | Deterministic provider responses and real database locks; bounded interleavings only. |

## Execution and defect detection

The initial saved-preview test failed on later HTML containing the old claim:
1 test / 15 assertions, one intended failure, zero errors/skips. A separate
cross-meeting test exposed missing API freshness after withdrawal. A new
concurrency test reproduced a PostgreSQL deadlock between additional-topic
knowledge linkage and a context writer: 1 test / 5 assertions, one intended
failure, zero errors/skips.

The earlier targeted regression command passed 59 tests / 579 assertions; the
agenda baseline passed 21 tests / 324 assertions, all with zero failures/errors/skips.
The final regression command, including knowledge cleanup/scope tests, passed
74 tests / 620 assertions with zero failures/errors/skips. A low-confidence alias
change initially blocked an independent entry (1 test / 5 assertions, one intended
failure); filtering before dependency capture fixed it. Commands use `RAILS_ENV=test`, an
isolated PostgreSQL database and `PARALLEL_WORKERS=1`:

```sh
bin/rails test test/integration/agenda_briefing_context_test.rb test/integration/meeting_summary_fact_dependencies_test.rb test/jobs/extract_knowledge_job_test.rb test/jobs/prune_hollow_appearances_job_test.rb test/services/meetings/parallel_summary_withdrawal_test.rb
bin/rails test test/integration/agenda_briefing_context_test.rb
bin/rails test test/integration/agenda_briefing_context_test.rb test/integration/meeting_summary_fact_dependencies_test.rb test/jobs/extract_knowledge_job_test.rb test/jobs/prune_hollow_appearances_job_test.rb test/services/meetings/parallel_summary_withdrawal_test.rb test/jobs/auto_triage_knowledge_job_test.rb test/models/knowledge_source_test.rb
bin/rails test
bin/rubocop
```

Fifteen bounded fault experiments each failed the intended assertion with zero
test errors, then passed after restoration. Targeted commands used the relevant
integration file with `-n /test_name_fragment/`.

| Fault | Demonstrated detection |
| --- | --- |
| Omit briefing-triggered withdrawal | Later HTML still contains the old claim. |
| Withdraw after commit | Failed audit leaves the changed briefing committed. |
| Omit the briefing writer's parent lock | Direct mutation does not wait for first preview publication. |
| Omit topic-status propagation | Blocked topic context remains in a published preview. |
| Omit alias-removal propagation | A preview remains published after its relevance alias disappears. |
| Bypass callbacks in the admin alias-move action | The HTTP request moves ownership but leaves its original preview published. |
| Do not retain the topic receipt | Historical correction leaves the future preview unchanged; conditional HTML incorrectly returns 304. |
| Omit withdrawal from API freshness | The changed future meeting is missing from `updated_since`. |
| Lock the summary before checking topic context | Concurrent knowledge work queues a deadlock retry. |
| Do not lock additional knowledge topics with the receipt | Knowledge linkage and the multi-topic writer deadlock. |
| Omit the alias mapping recheck | A knowledge entry is created against the superseded captured mapping. |
| Include rejected proposals in dependency checks | An unrelated low-confidence alias change blocks the supported entry. |
| Withdraw compatible context | Unconsumed prose changes supported summary attributes. |
| Leave the dependent image ready | The summary withdraws but its illustration remains ready. |
| Omit the existing nested-minutes source lookup | The isolated minutes-dependent preview stays published, proving that distinct prior coverage remains. |

`bin/rubocop` inspected 701 files without offenses. Seven Markdown files passed
292 local link/anchor and balanced-fence checks; `git diff --check` passed.
The local full `bin/rails test` at `0f5d88fd` passed 2,380 tests / 15,670 assertions,
zero failures/errors and one existing PromptRun fixture skip.

The first full run had two failures and two errors from leaked synthetic knowledge
records: meeting deletion intentionally preserves knowledge. Teardown now removes
its own knowledge fixtures before deleting the meeting. The isolated test database
was checked to contain zero remaining knowledge records before rerunning.

A cached association assertion now reloads the persisted summary after concurrent
work. The existing nested-minutes dependency test suppresses optional topic
context, so topic withdrawal cannot mask a broken minutes-source guard. Its
original source/receipt assertions remain. The citation-repair fixture uses the
provider's actual reporting shape instead of deriving it from the implementation's
server-field list. A mistyped filtered test command executed zero tests; it was
not counted as passing evidence, and the discovered test ran in the final baseline.

## Automatic review follow-up

The code review on `d7c6375` identified an existing application write that bypassed
these callbacks: the admin alias-move action used `update_all`. A new HTTP test
reproduced the finding (1 test / 17 assertions, one failure, zero errors/skips).
The action now uses `update!` and commits the review event in the same transaction.
The agenda and admin repair suites passed 51 tests / 554 assertions at `f1110196`:

```sh
bin/rails test test/integration/agenda_briefing_context_test.rb test/controllers/admin/topic_repairs_controller_test.rb
```

After that passing baseline, restoring the callback bypass failed the intended
publication assertion (1 / 17, one failure, zero errors/skips); restoring the fix
passed 1 test / 29 assertions. This is the fifteenth bounded fault experiment.
RuboCop again passed all 701 files, and whitespace checks passed. The first added
test run hit the last-admin safeguard during fixture cleanup; cleanup now deletes
only its own synthetic passkey after destroying its test session. That errored
run is not defect-detection evidence. Final-head CI and runtime results are
recorded on [PR #262](https://github.com/AndreRobitaille/TwoRiversReporter/pull/262).

## Remaining scope and cost

Legacy previews without receipts remain unverified. Participant/roster inputs,
knowledge inputs, already-produced knowledge and other generated projections,
complete narrative history, and direct SQL or callback-bypassing mutations remain
separate work. No missing provenance is inferred. There is no new migration,
control, schedule or automatic regeneration trigger.

The existing nightly summary repair behavior remains unchanged. General meeting
stage reuse, coalescing and explicit spending/retry enforcement remain #238
prerequisites before new paid dispatch. No paid AI, production operation, backfill,
merge or deployment ran. Campaign-source gaps and real extraction accuracy are
not resolved by these deterministic propagation tests.
