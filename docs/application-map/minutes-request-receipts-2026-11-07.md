# Minutes request receipts: November 7, 2026

Base: `e6873be3` ([PR #264](https://github.com/AndreRobitaille/TwoRiversReporter/pull/264)).
Implementation revision: `323ba699`. Verification uses Ruby 4.0.9, Rails 8.1.4.1
and isolated PostgreSQL 18.6. Every source, person and provider response in these
tests is synthetic; only download/provider transport is replaced in the new
request-boundary tests.

## Requirement and boundary

The [AI cost contract](../superpowers/specs/2026-11-07-council-accountability-design.md#ai-cost-contract),
the [bounded pilot proposal](../superpowers/plans/2026-11-07-council-evidence-pilot.md#intake-acceptance-dependencies-and-cost)
and [#238](https://github.com/AndreRobitaille/TwoRiversReporter/issues/238) require
bounded requests, durable accounting, unchanged-input reuse and conservative
handling of uncertain charges. The expectations were established before code
changes: cap generated tokens, retain each real attempt independently of the
pruned prompt examples, do not publish partial output, and do not automatically
redrive an unknown or limit-stopped response.

The existing vote/attendance jobs already have source-keyed stages, atomic claims,
completed-output reuse, a two-attempt invalid-output ceiling and uncertain-work
holds. Their actual provider requests had no output-token parameter, and
PromptRun's ten-row history was not durable usage evidence.

`Minutes::Pipeline` now supplies a recorder through `Ai::OpenAiService`. Before
transport, a unique extraction/attempt receipt retains the exact messages and
effective parameters. The request sends the pilot proposal's 4,000-token
completion ceiling, retained in the request parameters. Existing extraction keys
remain unchanged so deployment cannot reset an uncertain attempt. The
[official Chat Completions reference](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)
defines this parameter to include visible output and reasoning tokens. The
response is recorded before interpretation: provider ID/model, finish reason,
body, duration and available input/cache/output/reasoning/total usage. Missing
fields remain unknown, not zero. A received response is not proof of valid facts
or a reconciled invoice.

Non-stop responses are `incomplete` and held without automatic retry, including
valid-looking JSON stopped at the output limit. A transport or receipt-write
failure is held as uncertain. Process interruption leaves the dispatched receipt
and claimed stage. Completed receipts survive prompt pruning and source/meeting
removal, refuse model editing/deletion, and prevent destructive migration rollback.
The existing code-only publication and nightly checks continue; no schedule,
new provider client, generation trigger, public route or control is added.

## Behavioral evidence

| Workflow / variant | Actual boundary and meaningful result |
| --- | --- |
| BG-02, complete extraction | Retained source -> real jobs -> captured transport parameters -> two durable receipts -> two distinct motions and two people's votes/attendance. Full source ending remains in both prompts. Fresh reads retain the matching stage/usage identities. |
| BG-01/BG-02, unchanged delivery | Repeated jobs and existing nightly checks produce no additional transport calls or receipts and preserve projected row IDs. |
| BG-02, preexisting held work | A pre-receipt uncertain stage retains its identity, attempt count and hold through ordinary and explicit-refresh deliveries; neither makes a call. |
| BG-02, incomplete output | After a successful baseline, changed evidence returns syntactically valid but length-stopped JSON. The response/usage is retained, stage data remains unpublished, the prior publication survives, and repeated jobs/nightly checks do not retry it. Null, filtered and missing-finish variants are also held. |
| BG-02, uncertain work | Timeout occurs after the receipt exists. Unknown usage remains null, stage/receipt remain held and a repeated job makes no call. An uncaught process interruption retains `dispatched`/`running` state without retry. |
| BG-02, persistence failure | Receipt creation failure prevents transport. Receipt completion failure after a response retains an uncertain attempt and prevents automatic repeat/publication. |
| BG-02, invalid JSON | Two otherwise completed responses retain separate usage/body receipts; the third delivery and nightly check cannot reset attempts. |
| BG-02, retention | PromptRun pruning and ordinary document/meeting removal preserve the request receipt and retained stage; model edits/deletion and migration rollback are refused. |
| BG-02, concurrency | Separate PostgreSQL workers overlap vote and attendance requests; a duplicate vote worker returns while the first is in flight. A separate connection sees both committed dispatch receipts before release. Exactly two received receipts and one compatible publication result. |

The concurrency test upgrades the existing real-database scenario to exercise
`Ai::OpenAiService` and replace only its transport. It retains its earlier
distinct-person, source compatibility, stable decision and publication assertions.
Other existing component tests still stub AI methods; they establish regression
coverage, not receipt transport coverage. There is no new browser control, so
the changed boundary is jobs/transport/persistence, with fresh database reads.

## Execution and defect detection

Initial regression: one test / two assertions, one intended failure because both
actual requests lacked the completion ceiling, no errors/skips. The first
targeted pass ran 26 tests / 168 assertions. Expanded receipt checks passed
11 tests / 126 assertions. A compatibility test then reproduced the draft's
new ceiling-derived stage key resetting a preexisting uncertain attempt: one
test / two assertions, one intended failure, no errors/skips. The request
ceiling now leaves extraction keys unchanged. Final targeted regression passed
141 tests / 808 assertions, zero failures/errors/skips.

Commands ran with `RAILS_ENV=test`, the isolated database and `PARALLEL_WORKERS=1`:

```sh
bundle config get path
bundle check
bin/rails db:create db:schema:load
bin/rails db:migrate
bin/rubocop -A db/schema.rb
bin/rails test test/jobs/minutes/request_receipts_test.rb
bin/rails test test/jobs/minutes/request_receipts_test.rb test/jobs/minutes/parallel_publication_test.rb test/jobs/minutes/fact_publication_test.rb test/services/ai test/jobs/minutes/identity_correction_test.rb test/jobs/minutes/decision_identity_test.rb test/integration/minutes_publication_journey_test.rb
bin/rubocop
```

Ten fault checks each showed a passing baseline, one bounded fault, the intended
assertion failing without runner errors/skips, and a passing restored run.

| Fault | Required detection |
| --- | --- |
| Omit the outgoing completion cap | Captured requests lack the required bound. |
| Ignore the finish reason | Valid-looking partial output becomes a completed stage. |
| Record dispatch only after transport | A receipt-creation failure occurs after a call escaped. |
| Replace output usage with zero | Recorded output count differs from provider usage. |
| Treat unknown transport usage as zero | Uncertain charge loses its unknown status. |
| Permit finished-receipt editing | A retained usage receipt can be overwritten. |
| Retry incomplete output | The output-limit hold makes an additional request. |
| Retry uncertain output | An uncertain attempt makes an additional request. |
| Omit the job's recorder | Successful jobs have no durable receipts. |
| Include the ceiling in the extraction key | A preexisting uncertain request acquires a new attempt. |

RuboCop inspected 712 files with no offenses. Five Markdown files passed 138
local link/anchor checks and balanced fences; `git diff --check` passed. Owned
synthetic meetings/requests were absent after the runs. The additive schema diff
contains only the request table, indexes, constraint, foreign key and version.
Exact-head full CI, browser-suite discovery, runtime smoke and review evidence
are recorded in the pull request.

## Remaining work

This slice does not implement a spending allowance or authorize paid dispatch.
The fully rendered input still needs model-specific token accounting; the existing
50,000-character source guard is not an input-token ceiling. Request/run/daily
dollar reservations, owner-authorized pricing/budgets, aggregate counters, recovery
of uncertain charges and budget-pause administration remain #238 work. Low-level
AI calls outside the minutes jobs do not automatically acquire these receipts;
other feature stages still need their own integration. No legacy usage is
backfilled or inferred. Model-level retention is not protection against direct
SQL or callback-bypassing administrative writes.

The tests prove control flow and accounting persistence, not real extraction
accuracy, provider billing accuracy or adequacy of 4,000 tokens for every source.
An oversized response requires reviewed partitioning or a separately bounded
request; it is never silently accepted as complete. Authorized pilot spending
remains zero. No paid application AI, production operation, backfill, merge or
deployment ran.
