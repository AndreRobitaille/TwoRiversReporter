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
