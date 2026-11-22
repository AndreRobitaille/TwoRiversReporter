# Selecting a Council service period

Scope: RES-10/RES-11 under #237 and parent #234. Binding requirements are the
[attendance and decision design](../superpowers/specs/2026-11-07-council-accountability-design.md#attendance-decisions-and-comparisons)
and #237's requirement that period selection consistently scope attendance and
votes and survive navigation. This uses accepted facts; no analysis is generated.

## Resident behavior

The Council record control defaults to the latest usable evidenced service
period. A completed period needs its sourced end date. Only the newest period
can use an explicitly current Council role to support an ongoing window; an
older unknown departure is not inferred from a current role. A member with no
usable period keeps the existing all-records view.

Selecting a period filters both featured and all-recorded votes to the same
eligible Council meeting inventory used for attendance. Explicit special/reorganizational Council titles also include older imports
without committee links; those aliases reconcile with linked copies at the same
meeting time. Other committee
attendance remains separately labeled and uses the period's dates. Current
committee roles remain explicitly current; an old-period view also labels the
current office badge. Source start/end records stay available.

The period key survives Featured/All recorded switches, numbered pagination,
empty-page recovery and browser return from a meeting. Changing the period
starts at page one. Unknown or another member's period key returns 404 rather
than silently broadening the record. A sourced date correction applies on the
next request, without rewriting votes or calling AI.

All available records retains the broader historical/committee vote list and
recorded attendance counts. Those counts do not become a reconciled full-term
denominator. Campaign sources retain their own election labels; accepted action
links in a selected period use that period's Council inventory. In all-records
mode the existing campaign/action view continues to use its latest known service
window. Arbitrary date-range controls and complete historical source coverage are
not added by this slice.

## Verification

Local base `caaacc2` plus this patch; Ruby 4.0.9, PostgreSQL, an isolated synthetic
test database. No provider transport is needed. The assertions cover persisted
service-date corrections, known attendance/unknown records, cancelled/other
committee exclusions, both vote views, later requests, pagination, current-role
labeling and public/gated access. The allowed vote content is established before
testing its absence in gated HTML.

- Initial HTTP regression: 29 tests, 406 assertions, zero failures/errors/skips.
  Real-data inspection then exposed omitted special/reorganizational imports.
  Their regression also exposed a synthetic source-holder incorrectly left in
  the test meeting inventory; the fixture is now explicitly labeled separately.
  Final HTTP regression: 30 tests, 412 assertions, zero failures/errors/skips.
- Browser regression: four journeys, 80 assertions, zero failures/errors/skips.
  The new phone journey selects an older term, switches views, paginates, opens
  its meeting, returns, and selects all records. It checks the period value and
  actual decision identities after the transitions, plus horizontal overflow.
- Defect detection: removing the term parameter from the All recorded link makes
  that journey fail because selection changes from 2021 to 2024. Restoring the
  link passes the same journey (one test, 15 assertions). Separately excluding
  unlinked Council imports makes the real-title regression lose an expected
  present meeting; restoring the filter passes that test (six assertions).
- RuboCop: 802 files, clean after removing one extra blank line.
- Real development data: all three rollout members use their sourced 2024
  periods. Counts were independently read from the selected meeting inventory
  with AI construction forbidden. The phone preview was inspected visually;
  All available records, All recorded votes and page two retained the selection
  and displayed actual saved decisions, without horizontal overflow. Inspection
  of the excluded real votes found two unlinked special/reorganizational meetings;
  their saved votes now appear, with only other-committee votes outside the
  selected Council record. No source or vote rows were rewritten.
- Review follow-up: retain every eligible alias ID for vote and campaign-action
  selection while displaying one attendance representative. A richer duplicate
  must not hide existing votes or trigger new analysis. Targeted HTTP/campaign
  regressions pass (25 tests, 274 assertions); reverting to representative-only
  vote IDs fails the intended later-request assertion, then passes on restoration.

Commands:

```sh
bin/rails test test/integration/member_council_period_test.rb test/integration/member_council_attendance_test.rb test/integration/member_service_periods_test.rb test/integration/member_recorded_votes_test.rb test/integration/campaign_action_matching_test.rb
bin/rails test test/system/member_council_period_journeys_test.rb test/system/member_council_attendance_journeys_test.rb test/system/member_recorded_votes_journeys_test.rb
bin/rubocop
```

The local browser runner reports a Chrome/driver version warning but all journeys
execute and pass. The separate resident-review session could not be contacted
because its app transport failed twice; this new control has not received its
persona review. The previously approved compact campaign panels are unchanged.
No production operation, paid AI, backfill, merge or deployment was performed.
