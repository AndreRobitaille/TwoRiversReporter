# Bounded automatic action matching

Scope: BG-08 → RES-10 and #238 under parent #234. Binding requirements are the
[AI cost contract](../superpowers/specs/2026-11-07-council-accountability-design.md#ai-cost-contract)
and the owner's explicit hold on the full-term backfill.

## Admission and scope

A monthly authorization may opt into `live_actions`, with an explicit starting
date, model, request/daily ceilings, daily request count, input/output limits,
concurrency limit and conservative estimate method. Empty policy is disabled.
The migration creates no authorization. Policy and ceiling are retained; a new
month needs its own authorization. A renewal can retain the already-authorized
live window but cannot move it backwards into older history.

Only `CampaignActionReview` work for meetings on/after that start and no later
than today can derive day/run allowances. This does not enable campaign-source
intake, minutes re-extraction, historical backfill or future feature stages.
The authorizing administrator must still be active when a live grant is derived.
An explicitly supplied pilot run retains its existing independent admission path.

New meeting evidence and the existing nightly action check use this same path.
Unchanged completed comparisons return without grants, reservations or provider
calls. Pending/budget-paused work may resume when its allowance permits; malformed
responses retain the two-attempt maximum. Uncertain/incomplete transport remains
held. A revoked derived run is not silently replaced. Source preparation and
deterministic profile/vote rendering remain available when paid work is held.

Month → day → run → stage reservation locks retain the shared monthly/daily
ceilings. Live requests also share the policy's daily count and monthly in-flight
limit across separate derived runs. Existing lower daily limits are never raised.
Actual request parameters must match the retained estimate before transport.
No new schedule or page-request generation was added.

## Estimates and accounting

Automatic admission explicitly opts into the existing conservative text estimate:
UTF-8 content bytes plus 1,024 framing tokens, maximum completion tokens, checked
Standard API prices including cache-write/long-input uplifts, and no assumed cache
discount. The authorization names `utf8_bytes_plus_1024`; the run retains that
method and pricing reference with the exact prepared-request digest.

This extends use of the planning estimate for an explicitly configured live
policy. It does **not** convert an estimate into measured tokenization or an
invoice guarantee. Unknown request shapes/models, stale pricing, or requests
above the policy's limits remain held. The current pricing table expires on
November 21 and must be checked again before later admission. Reservations stay
consumed even if reported usage is smaller. The read-only spend report now also
shows the live policy, alongside usage at reserved rates and unresolved receipts.

A read-only transaction inspected the six existing real shared action requests.
Their observed usage stayed below the conservative estimates; unchanged inputs
remain reusable. No stage, request, reservation or vote count changed. This small
pilot had only one or two pairs per request, not the maximum twenty-pair batch.
It cannot establish the complete feature's monthly workload. Advocacy/outcomes,
staff recommendations and formal cases still need measurement; campaign intake
and historical backfill must remain separate from recurring cost estimates.

## Verification

Base `054c1f3` plus this patch; Ruby 4.0.9 and isolated PostgreSQL test data.
Only external provider transport is replaced. The real job, stage claim,
authorization, receipt, reservation, validator, persisted result and later member
request execute. There is no new browser control in this slice.

- Combined live/campaign/cost/monthly/daily regression: 42 tests, 457 assertions,
  zero failures/errors/skips. A new source comparison publishes a specific action;
  repeated nightly jobs and later member reads reuse it without new requests.
  Missing policy, old meetings, rollover, exhausted month, daily request count,
  retry exhaustion, uncertain transport, revocation, size and stale pricing holds
  are exercised without resetting attempts or fabricating output.
- The new two-connection test observes a real PostgreSQL lock wait. Only one of
  two automatic runs consumes the last monthly allowance; the other remains
  budget-paused. One test, eight assertions, passing. The existing four parallel
  reservation tests also pass. An initial fixture used unnormalized provider
  parameters and hit the exact-request guard before reservation; it was corrected
  to use the application's actual parameter builder.
  The final combined parallel/monthly regression passed 10 tests, 104 assertions.
- Representative defect: removing only the monthly reservation guard lets the
  next day make a second provider request (expected one, actual two). Restoring
  it passes the same test: one test, 13 assertions. Fault and restoration ran only
  in the isolated synthetic environment.
- RuboCop: 810 files, clean. Migration up and schema formatting ran locally; the
  inspected schema diff contains only the policy, grant provenance, index/FK and
  migration version. Rollback refuses to discard retained live authorization.

Commands:

```sh
bin/rails test test/integration/council_live_action_budget_test.rb test/integration/campaign_action_matching_test.rb test/integration/campaign_cost_preflight_test.rb test/jobs/council_profiles/monthly_spend_test.rb test/jobs/council_profiles/spend_reservations_test.rb
bin/rails test test/jobs/council_profiles/parallel_live_action_budget_test.rb test/jobs/council_profiles/parallel_spend_reservations_test.rb
bin/rubocop --cache false
```

No real policy or allowance was created, and no paid call, production operation,
historical backfill, merge or deployment occurred. Choosing a sustainable live
allowance and enabling production workers remain separate from this implementation.

