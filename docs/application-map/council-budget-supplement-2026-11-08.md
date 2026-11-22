# Explicit council budget supplement — November 8, 2026

The owner approved the prepared local catch-up with a $10 total ceiling. Existing
day/month authorizations are immutable; a new run alone cannot add the required
headroom. This change records a separate approval once and adds its amount to the
named day and month. Original authorizations, receipts and reservations remain
unchanged. No automatic increase, billing UI or recurring activation is added.

Affected workflows: BG-02 minutes extraction and BG-08 council evidence processing.
Acceptance follows the owner's explicit spending limit and the council design's
requirement to reserve before dispatch. A supplement must admit previously held
work, require an active administrator, remain immutable and deduplicate retries of
the same approval. Run/request/attempt limits and revocation continue to apply.

Local PostgreSQL validation on `codex/council-explicit-budget-supplements`, based on
`b6f1efd`, used deterministic provider responses and a separate test database:

- `bin/rails test` with `budget_supplements_test.rb`, `monthly_spend_test.rb`,
  `spend_reservations_test.rb`, both parallel spending/live-budget tests, and
  `council_live_action_budget_test.rb`: **34 tests, 387 assertions**, no failures,
  errors or skips. Dispatch/receipt persistence and later admission were exercised.
- Removed the monthly supplement term locally: the allowed second dispatch failed
  at the intended call-count assertion (expected two, received one). Restored the
  implementation and reran the supplement test file successfully.
- `bin/rubocop`: **878 files**, no offenses. Migration ran on local PostgreSQL;
  schema formatting was corrected and the schema diff inspected.

This verifies the shared spending boundary with simulated provider transport. The
approved real-data catch-up is tracked separately in the history proposal. No
production operation, recurring policy, merge or deployment is implied.
