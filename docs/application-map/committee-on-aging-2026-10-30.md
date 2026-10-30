# Committee on Aging correction — October 30, 2026

## Contract and affected workflows

[Issue #219](https://github.com/AndreRobitaille/TwoRiversReporter/issues/219)
requires the correct meeting name in resident headings, listings, sharing and
metadata, continued correction on the next scrape, preservation of unrelated
bodies and review of historical meetings/topic links. This affects BG-01,
RES-04/05/06 and RES-09. Binding requirements are the Development Plan's
[meeting identity](../DEVELOPMENT_PLAN.md#meeting-identity-and-cancellation)
and [roster source precedence](../superpowers/specs/2026-09-03-canonical-committee-rosters-design.md#source-precedence).

Discovery corrects a mislabeled `/bc-coa/` listing and may reuse an older bad
title only when the older record has the same source path and exact start
timestamp. It cannot overwrite an unrelated same-time meeting. The migration
selects affected source-backed meetings before selecting any mislabeled
committee. A committee with unrelated source references is retained; when no
Aging committee exists, the migration creates one instead of renaming a
mixed-source committee. Existing meeting/topic URLs and identities survive.

Conflicting active memberships are not resolved by guessing that the row
already on the destination committee is authoritative. Any difference in role,
source, title, dates or verification evidence aborts the transaction for explicit
review. Both records and all earlier migration writes are preserved by rollback.
Only identical membership data can be consolidated. No callback, AI call or
summarization job is needed for the correction.

## Data and execution evidence

The owner authorized `bin/sync_prod_db --force`, which restores production into
the local development database. The production revision inspected through the
persistent tunnel was `d3f26a00abbd45ed682e90d14ff8a5d46595e4ce`.
The synced source contained one affected row, meeting 302, with a blank committee
link. Committee 11 was already Committee on Aging with slug `committee-on-aging`.
Sixteen older Aging meetings already had that committee link. There were no
topic appearances for meeting 302 and no Committee On Agenda committee to merge.

After `bin/rails db:migrate` on the synced copy, 61 table fingerprints matched
the pre-migration snapshot (excluding meeting 302 from the meetings fingerprint).
Only that meeting's `body_name`, `committee_id` and `updated_at` changed. Local
HTTP requests confirmed the corrected detail page, list entry, OG/Twitter title
metadata and sharing payload. A second migration invocation made no corrections.
The schema dump differed only in column ordering; after `bin/rubocop -A
db/schema.rb`, the tracked schema was retained without unrelated reordering.

Synthetic tests run separately from that copy, using isolated PostgreSQL
databases and Ruby 4.0.7. The focused runner is:

```sh
PARALLEL_WORKERS=1 DATABASE_URL=postgresql:///trr_pr220_test_20261030 bin/rails test test/services/scrapers/committee_on_agenda_name_test.rb test/services/scrapers/committee_on_agenda_repair_safety_test.rb test/integration/committee_on_aging_correction_test.rb
```

It discovers and runs 12 tests / 154 assertions with no failures, errors or
skips. Service tests cover source scope, same-time identity, mixed-source
committees, membership conflict rollback, identical duplicate consolidation,
stable topic/meeting links, idempotency and no enqueued jobs. The HTTP test
first proves the incorrect title exists, applies the repair, verifies headings,
listing, title/OG/Twitter metadata and both share payloads, rediscovers the
original bad listing and verifies those later requests again. It also checks
the corrected title and withheld share payload for an anonymous gated reader.

Fault checks use a separate local checkout and PostgreSQL database. Each starts
from the passing fixed code, introduces one fault, observes the intended
assertion failure with zero errors, restores the file and reruns to green:

- Remove the stored-source restriction: unrelated same-time meeting is renamed.
- Restore the unscoped committee selection: unrelated committee is renamed.
- Remove membership conflict refusal: expected exception is absent.
- Omit the meeting body-name update: resident heading remains incorrect.

These are deterministic service and HTTP boundaries; external discovery HTTP
transport is represented by listing HTML, and no provider/AI calls are made.
This record does not claim browser clipboard behavior or reader satisfaction.

The complete local application suite passed 2,135 tests / 13,048 assertions,
with no failures or errors and one existing `PromptRunTest` skip for a missing
meeting fixture. The browser suite ran separately and passed 20 journeys / 701
assertions with no failures, errors or skips. Full RuboCop, Brakeman,
bundler-audit and importmap audit passed. No production provider call was made.

## Follow-up: rename check and redirect cache

The migration version `20261030124500` is already recorded in production, so
editing its body does not run again on deploy. Production's deploy of `9d0d8312`
reported one renamed meeting, zero topic appearances and zero committee merges.
`write_redirect` runs only after a successful merge, so no redirect row was
written and `redirects/lookup_map` does not hide one. A public request to
`/committees/committee-on-agenda` is 404; `/committees/committee-on-aging` is
200. No production data change and no one-time cache delete are required.

The rename-only path now uses `outside_references?`, the same leftover meeting
and topic-appearance check the merge uses after the corrected rows move. A
non-corrected `/bc-coa/` meeting, or an appearance on a meeting that is not
being corrected, leaves the Committee On Agenda row in place and creates
Committee on Aging for the corrected meetings. `write_redirect` schedules
deletion of `Redirect::CACHE_KEY` (`redirects/lookup_map`) with
`ActiveRecord.after_all_transactions_commit`, because `insert` and
`update_columns` skip the model callback. Invalidating before commit lets a
concurrent request cache the old rows; invalidating after the outer commit
ensures later requests load the committed redirect. Rollback runs no deletion.

Focused runner, Ruby from this environment, PostgreSQL test database:

```sh
PARALLEL_WORKERS=1 DATABASE_URL=postgresql:///trr_pr221_test_20261030 bin/rails test test/services/scrapers/committee_on_agenda_name_test.rb test/services/scrapers/committee_on_agenda_repair_safety_test.rb test/services/scrapers/committee_redirect_commit_test.rb test/integration/committee_on_aging_correction_test.rb
```

18 runs / 209 assertions, no failures, errors or skips (Ruby 4.0.7, isolated
PostgreSQL database). The redirect tests disable transactional fixtures and
clean up their synthetic records explicitly, so their commits actually occur.
They retain insert/update cache checks, 301 status/destination and hit history,
add a real second-connection lookup while the writer is uncommitted, and prove
the later HTTP request redirects after commit. A separate rollback variant
verifies the cache survives and the original meeting/committee state returns.

The original branch's rename fault checks found:

- Rename whenever no Aging row exists, without the leftover check: the two new
  rename tests fail because the Committee On Agenda name becomes Committee on
  Aging. Zero errors.
- Keep only the older URL check (`exclusively_bc_coa?`): those same two tests
  fail, and the existing mixed non-`/bc-coa/` test still passes. Zero errors.
- The original cache tests caught omitted invalidation but did not cross an
  actual outer commit or another database connection.

Subsequent fault checks ran `committee_redirect_commit_test.rb` in an isolated
checkout and PostgreSQL database: clean 4-test baseline, one bounded fault,
intended failures with zero errors, restoration and 4 tests green again.

- Clear immediately before commit: concurrency and rollback assertions both
  fail (two failures). The committed redirect is hidden by the stale map and
  rollback incorrectly clears the cache.
- Omit invalidation entirely: insert, update and concurrency assertions fail
  (three failures), including nil/new destination and `/stale`/updated destination.

The cache transport is a retained `MemoryStore`; PostgreSQL transactions,
connection isolation and HTTP redirect middleware are real. Production's
Solid Cache transport is not simulated as a separate cache database by these
tests. This edits an already-applied migration, so deploy does not exercise
these new write paths against production rows.

The updated full application runner passed 2,141 tests / 13,103 assertions,
with no failures or errors and the existing missing-meeting-fixture skip.
Full RuboCop, Brakeman, bundler-audit and importmap audit passed. Ordinary and
browser suites use the same isolated test database serially; the synced
production copy stays in the development database.
The updated browser run passed 20 journeys / 701 assertions with no failures,
errors or skips. `bin/sync_prod_db --force` completed again before release;
the copy confirms migration `20261030124500` is already applied and meeting
302 remains Committee on Aging with committee 11.
