# Monthly council spending limits

Scope: BG-02 and BG-08, parent #234 and #238. The owner's November 8 direction
requires sustainable recurring API costs and personal approval before a full-term
historical backfill. This extends the existing request/run/day limits; it does not
authorize that backfill, activate paid production work, or cover unrelated AI jobs.

## Contract and operation

Paid council dispatch now also requires an explicit `CouncilAiBudgetMonth` for
the run's calendar month. It is an immutable administrator authorization, with
one record per first-of-month date, an integer micro-USD ceiling and irreversible
revocation. The migration creates no allowance. A new month needs its own
authorization; a day or run allowance cannot replenish the month.

Admission locks month → day → run → stage and commits the reservation with the
request receipt before transport. Every reservation in the month's retained
budget days counts, including older reservations created before this migration.
Completion releases concurrency only. Low measured usage, an uncertain outcome,
retries, new runs and nightly recovery do not refund or reset the ceiling.

Missing, revoked or exhausted months pause new paid work before transport without
consuming an attempt. Completed extraction and matching results still reuse for
free. Existing source collection and deterministic publication remain independent.
All current council-budgeted stages use this admission path: selected minutes,
campaign statements, campaign/topic matching and campaign/action matching.

Read the local ledger without changing it:

```sh
bin/rails 'council_profiles:spend_report[2026-11]'
```

The report separates reservations, unfinished requests and missing usage by
stage. `usage_at_reserved_rates_microusd` prices reported input/output counts at
each request's approved preflight rates, including any uplifts already in those
rates. It does not assume cache discounts, refund reservations, fetch prices or
call the provider. It is neither an invoice nor the whole application's AI bill.
`remaining_microusd` is arithmetic headroom; a missing/revoked authorization or
any existing request/run/day guard still prevents dispatch.

Keep recurring action matching separate from one-time campaign intake and
historical catch-up when estimating operating cost. A partial-history workload
census cannot establish the complete monthly workload. Advocacy, issue-outcome,
staff-position and formal-case processing require their own bounded measurements
as implemented. This slice does not yet implement automatic future run/day
authorization, an admin budget form or a provider billing reconciliation service.

## Verification

Local revision: `04cba14` plus this monthly-cost patch, Ruby 4.0.9/PostgreSQL,
isolated synthetic test database. Provider transport is deterministic; admission,
transactions, persisted receipts, publication and subsequent deliveries are real.

- Initial minutes regression: 23 tests, 247 assertions, no failures/errors/skips.
- Monthly/parallel and campaign extraction/topic/action regression: 33 tests,
  376 assertions, no failures/errors/skips. These cover a successful dispatch
  first, a fresh day failing to replenish the month, paused recovery, cached
  replay, missing/revoked authorization, no automatic month rollover, retained
  unknown usage, and read-only report output. Independent database connections
  prove dispatch waits for the monthly lock. Existing daily concurrency tests
  remain intact.
- Full RuboCop: 798 files, no offenses. Migration/schema diff inspected.
- Defect detection: removing only the monthly ceiling check makes the cross-day
  test dispatch a second request and fail its intended call-count assertion.
  Restoring it returns the same test to green.
- Real development copy: the new table was migrated locally, with no allowance
  created. The CLI report recognizes prior receipts in all three campaign stages
  while correctly reporting missing monthly authorization. No paid call or
  historical processing was made for this check. The report omits source text.

Commands:

```sh
bin/rails test test/jobs/council_profiles/monthly_spend_test.rb test/jobs/council_profiles/spend_reservations_test.rb test/jobs/council_profiles/parallel_spend_reservations_test.rb
bin/rails test test/jobs/council_profiles/monthly_spend_test.rb test/jobs/council_profiles/parallel_spend_reservations_test.rb test/jobs/extract_campaign_source_job_test.rb test/integration/campaign_extraction_test.rb test/integration/campaign_topic_matching_test.rb test/integration/campaign_action_matching_test.rb
bin/rails test test/jobs/council_profiles/monthly_spend_test.rb -i '/another_day/'
bin/rubocop
```

The first attempt at the combined command referenced a nonexistent service-test
directory; an initial fault-test filter also matched no tests. Neither attempt supplies verification evidence; the corrected command above is the executed evidence.
No browser controls changed. CI, production operation and full-feature recurring
cost remain separate evidence, not implied by these local checks.
