# Sourced Council service dates: November 8, 2026

Application revision: `25b54e9705f8e52c7875cb671019e85653ff8ba4`, based on
PR #247's retained-source foundation. This is a small part of
[#237](https://github.com/AndreRobitaille/TwoRiversReporter/issues/237), under
[#234](https://github.com/AndreRobitaille/TwoRiversReporter/issues/234).
It is independent of PR #271's vote pagination changes.

## Requirement and scope

The [member-profile design](../superpowers/specs/2026-11-07-council-accountability-design.md#proposed-member-page)
requires actual service dates separate from current office titles. The
[source pilot](../superpowers/plans/2026-11-07-council-evidence-pilot.md)
establishes why the event date matters: the April 16, 2024 organizational
minutes appear in a May 6 packet. The packet's meeting date is not the start
of the elected members' service. Unknown end dates must not become invented
expiration dates or claims of uninterrupted service through today.

`CouncilServicePeriod` stores accepted dates with retained document versions
and PDF page numbers. A member can have distinct repeat terms or appointments.
The existing profile displays the dates and links directly to the retained
PDF. If only a start is documented it says "Term began…"; an end requires
its own date, source and page. Profiles without accepted periods have no new
section. Current roles remain separately displayed.

The public section follows the existing member access contract: information
above Voting Record remains readable in gated mode. It adds no dates to API
responses, metadata, attendance rates or vote filtering. A term selector,
meeting eligibility, reconciled attendance and automated extraction of service
events remain subsequent slices. This does not complete #237 or establish a
complete service history for any real member.

## Accepted-input boundary

One checked source can populate several members through:

```ruby
CouncilServicePeriod.record_starts!(
  period_key: "2024-election",
  source_version: retained_packet,
  page: 5,
  entries: [
    { member_id: first_resolved_member.id, started_on: "2024-04-16" },
    { member_id: second_resolved_member.id, started_on: "2024-04-16" }
  ]
)
```

The caller must have checked the assertions and resolved existing member IDs;
retention alone is not validation. The stable `period_key` identifies the same
period when dates are corrected. A repeat term uses a different key. The method
uses one transaction, preserves unknown end dates and writes nothing for
unchanged inputs. A subsequent `update!` can record a sourced departure or
correct an accepted row. No source extraction, new schedule, automatic import,
AI call or per-profile publishing operation was added. This is the persistence
boundary for accepted source results, not an alternative minutes pipeline.

Member merges move these records with their sources. A conflicting period key
returns the existing merge error path and rolls back; it does not choose between
conflicting dates or silently erase either record.

## Verification

Environment: Ruby 4.0.9, Rails 8.1.4.1, isolated local PostgreSQL database
`trr_council_service_periods_test`, shared external gem store, `RAILS_ENV=test`,
`PARALLEL_WORKERS=1`. Application and browser tests ran serially. The fixture
PDF is six pages of explicitly synthetic text; no real member was populated.
Transport, models, Active Storage and profile requests were exercised without
provider stubs bypassing the persistence or HTTP boundaries. The intake test
fails if an AI provider is constructed.

- `bin/rails db:create db:schema:load db:migrate` succeeded on the isolated
  database. `bin/rubocop -A db/schema.rb` restored formatting; inspected schema
  changes contain only the new table, indexes, foreign keys and version.
- `bin/rails test test/models/council_service_period_test.rb test/integration/member_service_periods_test.rb test/models/member_test.rb test/controllers/members_controller_test.rb test/controllers/members_show_gating_test.rb test/models/meeting_document_version_test.rb test/controllers/admin/members_controller_test.rb`:
  **75 tests, 223 assertions, zero failures/errors/skips**.
- RES-10/11: one source → three persisted member periods → three distinct
  profile requests → retained PDF responses with exact fixture bytes. Repeated
  input preserves IDs and timestamps. A correction retains the period ID and
  appears on the next request. Repeat periods, a departure, empty profiles and
  gated reading of service dates are covered.
- ADM-10: existing member tests plus new service-history movement and conflicting
  period rollback assertions pass. No new admin control or browser merge flow
  was added; the new conflict is verified at the model boundary.
- `CHROME_BIN=/usr/bin/chromium bin/rails test test/system/member_service_period_journeys_test.rb`:
  **1 journey, 7 assertions, zero failures/errors/skips**. At 390px, the resident
  reads the date, clicks the source, reaches the correct retained blob with
  `#page=5`, returns and refreshes. The profile screenshot was inspected and has
  no horizontal overflow. Native PDF page rendering is not asserted; exact PDF
  transport is verified separately over HTTP. The installed Chrome/driver
  version warning did not prevent the journey.
- Representative defect: a process-local override substituted the packet date
  for the supplied service date. The intended profile assertion failed with
  **May 6 instead of April 16** (1 test, 8 assertions, 1 failure, no errors/skips).
  The normal 75-test command then passed. Neither source files nor the running
  vote preview were modified by the fault.
- `bin/rubocop --cache false`: **643 files, no offenses**. Documentation links,
  anchors and whitespace checked. The PDF's fifth page was independently read
  with `pdftotext` and identifies the synthetic April 16 oath record.

No paid AI, production access, shared development-data mutation, backfill,
merge or deployment occurred. Automated source discovery, actual cohort loading,
complete term denominators and full campaign-to-action comparisons remain open.
