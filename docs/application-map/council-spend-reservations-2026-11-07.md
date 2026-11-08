# Council minutes spending reservations: November 7, 2026

Base: `249894d5` ([PR #265](https://github.com/AndreRobitaille/TwoRiversReporter/pull/265)).
Initial implementation revision: `27f7758b`; the subsequent review correction is
recorded below and in the pull request.
Verification uses Ruby 4.0.9, Rails 8.1.4.1 and isolated PostgreSQL 18.6.
All source material, people, provider responses, token counts and prices in the
new tests are synthetic. No allowance has been created outside the test database.

## Requirement and scope

The [AI cost contract](../superpowers/specs/2026-11-07-council-accountability-design.md#ai-cost-contract)
and [#238](https://github.com/AndreRobitaille/TwoRiversReporter/issues/238) require
reservation before dispatch, bounded retries, shared-source reuse and conservative
unknown-charge handling. Acceptance was derived from those requirements before
implementation: a missing/exhausted allowance must prevent the actual call,
parallel jobs must not consume the same remainder, and retries/nightly processing
must preserve budgets and attempts while deterministic work continues.

This slice adds an internal `CouncilProfiles::ExtractMinutesJob` entrypoint for
existing vote/attendance extraction. It permanently selects a meeting for budget
admission of pending/future minutes stages. Ordinary deliveries, nightly repair
and new source versions inherit the requirement. Previously unselected meetings
retain existing ingestion behavior; this does not enroll every AI caller or
retroactively budget work already claimed before selection. There is no new
automatic trigger, schedule, browser control or public response field.
Selection and claims share the meeting lock. Claiming atomically inherits the
persisted budget requirement/run while updating the stage, even when an ordinary
worker prepared its input before selection.

An active administrator records one immutable allowance per application-calendar
day and an immutable run authorization. Runs include request/run limits,
request-count/concurrency/token ceilings, expiry, actor/time/basis and a batch of
prepared estimates. Revocation can stop new requests but cannot be undone.
Model validations protect authorization history; actor deletion retains the
original actor ID, and migration rollback refuses to discard it.

An estimate binds the extraction key and canonical digest of the fully rendered
provider parameters. It supplies an input token count, the output cap, effective
worst-case input/output rates in micro-USD per million tokens and a basis naming
the model, count method, pricing reference and check time. The shared pure
`Ai::OpenAiService.minutes_request_parameters` builder prepares the same payload
used by transport without calling the provider. Changed source/prompt/payload
cannot silently borrow an earlier estimate.

These values are **approved preflight inputs**, not measurements made by this
code. Shape validation and a digest cannot establish that the supplied count or
price is accurate. This slice does not implement a model-specific token counter,
fetch/validate pricing, or verify the estimate's claimed check time. Any real
preflight must account for full prompt framing, effective model/tier/context and
applicable price uplifts without assuming a cache discount. That validation and
owner authorization remain prerequisites; the actual paid-pilot budget is zero.

## Accounting and retention

Admission takes day, run and stage locks in that order. It checks date/expiry,
revocation, the exact estimate/model, declared input/output bounds, per-request,
run and daily amounts, request count and run concurrency. Arithmetic rounds the
full input plus capped-output estimate upward to an integer micro-USD. Distinct
runs sum against the same daily row. Reservation and attempt receipt commit
together before provider transport.

A received response atomically finishes its reservation with the receipt,
releasing the concurrency slot. The complete reserved amount remains consumed,
even if the response reports less usage. This intentionally conservative ledger
does not yet settle to actual usage or invoice amounts. A timeout, process
interruption or response-persistence failure retains both amount and slot;
unknown usage never becomes a free request. Explicit recovery remains separate.

Missing/exhausted budgets produce `budget_paused` and a reason in the retained
stage and existing processing state. They restore the attempt preclaim because
transport never started. The existing nightly sweep may enqueue that work again,
but cannot create an allowance, release an unknown reservation or reset attempts.
Invalid finished responses retain the existing two-attempt ceiling, with a new
reservation for each actual call. New authorizations cannot reset that ceiling.
Completed facts and deterministic date reprojection reuse without admission,
including after revocation or without a current allowance.

## Behavioral evidence

| Workflow / variant | Actual boundary and meaningful result |
| --- | --- |
| BG-02, allowed dispatch | Retained synthetic bytes/text -> actual council job -> real pipeline/client -> deterministic transport -> receipt/reservation -> publication. Both distinct people, opposite votes and attendance survive fresh reads. The source ending is present in both requests. |
| BG-01/BG-02, unchanged reuse | Repeated deliveries and the existing nightly sweep make no additional calls or reservations and preserve publication identity, including after revocation. |
| BG-02, absent/limited allowance | Missing budget, request/run/day amount, declared token and request-count limits pause before transport. Attempts and retained source survive; nightly requeues the missing counterpart without granting another attempt or allowance. |
| BG-02, shared daily limit | After one run spends the day's allowance, another authorized run cannot spend it again. No automatic next-day allowance appears. |
| BG-02, request binding | Changed source/prompt or exact request digest/model cannot use the approved estimate; new stages retain budget admission. |
| BG-02, integer arithmetic | A sub-micro-USD estimate reserves one micro-USD, exhausting a one-micro-USD run and holding the counterpart. |
| BG-02, invalid output | Two malformed finished responses consume two reservations. A new run does not reset attempts or permit a third dispatch. |
| BG-02, unknown outcome | Timeout and uncaught process interruption retain amount/slot and prevent replay; another stage in that run remains concurrency-paused. |
| BG-02, persistence failures | Failure creating the receipt rolls back the reservation before transport. Failure finishing the reservation rolls back the received receipt and retains an uncertain attempt, amount and slot. |
| BG-02, retention | Non-admin authorization, authorization replacement and financial edits are refused. Deleting a source meeting and author retains receipts/reservations/original actor IDs; rollback refuses to discard history. |
| BG-02, real parallel daily admission | Two PostgreSQL connections use different runs. The first pauses after admission checks; the second actually waits on a database lock. After release, only one request/reservation exists, and a fresh read sees the second stage paused at the daily limit. |
| BG-02, selection/ordinary claim race | Separate workers prepare an ordinary unbudgeted stage, commit council selection, then resume the ordinary claim before the council worker resumes. No transport escapes; fresh reads and a later ordinary delivery retain the missing-budget pause, zero attempts and zero receipts. |
| BG-02, real concurrent transport | While the first request awaits its provider response and occupies the run slot, a second worker is held before transport. Finishing the first releases the slot; a later ordinary job publishes the complete source-matched pair with exactly two calls. |
| BG-02, compatibility/correction | Unselected ordinary ingestion creates no council reservations. Selecting already-completed facts adds no call. A later date correction republishes deterministically without an allowance or new extraction. |

The new tests replace only download/provider transport; jobs, estimate checks,
transactions, row locks and publication run normally. Database concurrency tests
use committed fixtures and separate connections. Cleanup removes only their
owned synthetic records. No new browser boundary is introduced; existing minutes
HTTP and provider-service regression tests also run. Existing component stubs
are regression coverage, not additional proof of budget admission.

## Execution and demonstrated defect detection

The initial missing-budget regression failed as intended: one test, two
assertions, one failure and no errors/skips because a provider call escaped.
The first guarded pass ran 13 tests / 143 assertions; the expanded pass ran
27 tests / 271 assertions. The completed new budget suite ran 18 tests /
197 assertions, and the broader targeted suite ran 159 tests / 1,005 assertions,
all passing with zero errors/skips. A retention-test assertion was corrected to
expect the existing dependent-record deletion exception rather than a false
return; the stored-history expectation was unchanged.

Automatic code review then identified a gap between reading a stage's budget
requirement and claiming it. The added real-worker regression reproduced one
unbudgeted dispatch after selection (one test / five assertions, one intended
failure, no errors/skips). Selection and claim now share the meeting lock, and
budget inheritance happens within the stage claim transaction. The new test
passed with 12 assertions. Its scheduling wrappers pause input access and the
publication entrypoint but still execute those original methods; they do not
replace claims, admission, database locks or persistence.
The final serial targeted run passed 160 tests / 1,017 assertions, with zero
failures/errors/skips. The original 159-test result above predates this correction.

Commands use `RAILS_ENV=test`, an isolated database and `PARALLEL_WORKERS=1`:

```sh
bundle config get path
bundle check
bin/rails db:create db:schema:load
bin/rails db:migrate
bin/rubocop -A db/schema.rb
bin/rails test test/jobs/council_profiles
bin/rails test test/jobs/council_profiles test/jobs/minutes/request_receipts_test.rb test/jobs/minutes/parallel_publication_test.rb test/jobs/minutes/fact_publication_test.rb test/services/ai test/jobs/minutes/identity_correction_test.rb test/jobs/minutes/decision_identity_test.rb test/integration/minutes_publication_journey_test.rb
bin/rubocop
```

Fourteen isolated fault experiments each ran a clean passing baseline, one
bounded mutation, an intended assertion failure without errors/skips, and a
passing restored run. They separately removed missing-budget admission,
request/run/day amount limits, input/output token limits, request-count limits,
payload binding, concurrency limits, upward arithmetic rounding, authorization
immutability, paused-attempt restoration, inherited budget requirements and
the shared daily lock. The last experiment used actual competing PostgreSQL
connections: without the daily lock, the second run no longer waited for the
first reservation, and the lock-wait assertion failed.
After the review correction, two further baseline/fault/restored experiments
removed the claim's meeting lock and its budget inheritance separately. Both
produced intended assertion failures without errors/skips and passed after
restoration. This adds selection-order defect detection and re-proves inherited
budget enforcement at its new claim boundary.

RuboCop inspected 723 files with no offenses. Five Markdown files passed 141 local
link/anchor and balanced-fence checks; `git diff --check` passed. The isolated
database retained zero owned synthetic meetings, budget days/runs, reservations
or receipts after the tests. The additive migration/schema diff was inspected.
Exact-head full CI, browser-suite discovery, runtime smoke and automatic reviews
are recorded in the pull request.

## Remaining work and limits

The tests prove admission/control flow and retained arithmetic against synthetic
estimates, not real source interpretation, tokenization, pricing or billing
accuracy. No actual allowance or paid pilot is authorized. Request estimates
currently require explicit preparation/approval; no automated estimate producer,
operator budget UI, aggregate cost dashboard, settlement/recovery workflow or
other profile-generation stage is included. Existing ordinary ingestion remains
outside this selected-meeting budget boundary. Model retention rules do not
protect against direct SQL or callback-bypassing administrative writes.

The concurrency evidence covers the two documented interleavings, not every
possible writer or multi-host load pattern. Reservations are conservative
capacity accounting rather than a reconciled invoice. The daily allowance uses
the application's calendar day; an operator must explicitly authorize a later
day/run. No paid application AI, production operation, sync, backfill, merge,
deployment or issue closure ran.
