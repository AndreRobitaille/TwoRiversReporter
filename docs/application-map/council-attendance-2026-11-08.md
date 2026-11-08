# Council attendance: November 8, 2026

Application revision: `ff3a980adc41e40aac12c5a61a291d89584b3781`, based on
PR #272's sourced service periods. A bounded part of
[#237](https://github.com/AndreRobitaille/TwoRiversReporter/issues/237) under
[#234](https://github.com/AndreRobitaille/TwoRiversReporter/issues/234).

## Requirement and observed problem

The [attendance contract](../superpowers/specs/2026-11-07-council-accountability-design.md#attendance)
requires missing roll calls to remain unknown, cancellations and out-of-service
meetings to be excluded, and committee service to stay separate. The owner's
November 8 instruction requires real civic data for development acceptance;
the unfilled part of the term does not block this work.

The existing HTML counts only stored attendance rows and compares their
percentages with peers. In the local civic copy, each initial-cohort member has
45 named Council roll calls, while 51 eligible known meetings exist. Six missing
roll calls disappear from the old display. One cancellation appears only in its
title. Three listening sessions are labeled `regular` by the imported type
field, as are work sessions and special meetings.

## Implemented boundary

`ResidentContent::CouncilAttendance` combines the latest accepted service start
with either its sourced end or the member's explicitly current Council position.
The latter supports an ongoing window, without writing an assumed end date.
The current title alone cannot supply a historical start. An unknown former
end cannot establish eligibility; that profile falls back to recorded counts.

The projection reconciles named voting-member roll calls with known Council
meetings. Regular, special, organizational and work sessions are identified by
their explicit titles. Cancellations, future meetings, listening sessions and
meetings outside service are excluded. Existing duplicate identity rules count
one meeting; conflicting duplicate roll calls remain unresolved. Missing rows,
guest appearances and staff appearances do not manufacture a voting-member
presence or absence.

HTML shows present, absent, excused and "Not recorded" counts, the available
record dates, and an expandable list of meeting links and types. The inventory
is incomplete, so there is no complete-term percentage or peer comparison.
Other committees show their recorded counts separately. Reads perform no AI,
persisted recalculation, enqueue or backfill. Added roll calls, cancellations
and accepted service-date corrections appear on the next request.

The section stays public under the existing above-Voting-Record access rule.
Voting access is unchanged. API serialization still uses the legacy attendance
projection and has not acquired new fields or changed its existing percentages.
Term selection, consistently term-scoped votes, partial attendance and complete
historical coverage remain unfinished; this does not complete #237.

## Real-data acceptance

An isolated local database used the existing civic-only export; ordinary test
fixtures were never loaded into it. The three existing member identities and
all 628 cohort votes were preserved. The accepted April 16, 2024 start dates
use the separately inspected [May 6 city packet, PDF page 5](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Packet-0a3667b40f544f5faa60d89c5fc48508.pdf#page=5),
as documented in the [service-source check](council-service-periods-2026-11-08.md).
Current Council positions come from the existing official-roster records;
the [city roster](https://www.two-rivers.org/citycouncil) was checked on November 8.

Independent SQL inventory/roll-call counts were compared with the projection,
rendered counts, all meeting-link identities and retained source responses:

| Member | Present | Absent | Excused | Not recorded | Known meetings |
| --- | ---: | ---: | ---: | ---: | ---: |
| Mark Bittner | 42 | 3 | 0 | 6 | 51 |
| Doug Brandt | 44 | 1 | 0 | 6 | 51 |
| Shannon Derby | 40 | 5 | 0 | 6 | 51 |

The 58-record Council inventory excludes two cancellations, two future meetings
and three listening sessions. Available eligible records span July 7, 2025 to
November 2, 2026. Missing roll calls are July 21, July 28 and August 4, 2025;
October 19, October 26 and November 2, 2026 (Central Time). These are gaps in
this local copy, not claims that the city failed to record attendance.

All three profile-to-retained-PDF responses matched SHA-256
`afe3c7919edcfd522118e7d5be69d1a9b7679ba1027897eb57c54109d117affd` and page 5.
The real-data runner prohibited constructing the AI service. The 628 vote IDs,
motion links, members and values remained identical; no provider ran.

The combined local preview also received these additive changes and the
accepted source dates. Existing campaign cards and numbered vote pagination
were preserved. At 390px, the real Bittner page showed the four counts in two
columns, expanded 51 dated/type-labeled meeting links, opened the October 5
meeting, and returned/refreshed successfully. Brandt and Derby also rendered
their expected counts. This checks an existing-data workflow, not accuracy of
all historical extraction or completion of the absent backfill.

## Regression and workflow verification

Environment: Ruby 4.0.9, Rails 8.1.4.1, isolated PostgreSQL test database,
`PARALLEL_WORKERS=1`. Regression fixtures are deliberately synthetic and separate
from the real development data. External AI is forbidden in the new HTTP tests.

- `bin/rails test test/integration/member_council_attendance_test.rb test/controllers/members_controller_test.rb test/controllers/members_show_gating_test.rb test/controllers/api/resident_api_test.rb test/integration/member_service_periods_test.rb test/models/council_service_period_test.rb`:
  **52 tests, 907 assertions, zero failures/errors/skips**.
- RES-10/11: HTTP requests exercise start/end eligibility, no sourced start,
  unknown former end, empty inventory, cancellations including title-only
  cancellation/no-quorum, excluded meeting types, guest/staff rows, duplicate
  records, subsequent roll-call/cancellation/date corrections, and open/gated
  attendance with unchanged voting access. Existing API tests remain green.
- `CHROME_BIN=/usr/bin/chromium bin/rails test test/system/member_council_attendance_journeys_test.rb`:
  **1 journey, 12 assertions, zero failures/errors/skips**. Expand on a phone,
  open a meeting, return, change a roll call and refresh to updated counts;
  no horizontal overflow. The installed Chrome/driver version warning did not
  prevent execution. Initial text assertions needed whitespace/case corrections
  for rendered line breaks and CSS uppercase; these were test defects.
- `bin/rubocop`: **647 files, no offenses**. `git diff --check` passed.
- Representative defect detection: a clean passing inventory test ran first
  (1 test, 22 assertions). A temporary fault classified missing roll calls as
  absent; the intended count assertion failed (4 absent instead of 1).
  Restoring the service returned the same test to green (1/22). The fault never
  reached the preview or a commit. This demonstrates that boundary, not all
  possible attendance defects.
- The preview applied only PR #272's additive service-period migration locally;
  schema formatting was corrected with `bin/rubocop -A db/schema.rb` and the
  inspected diff contained only that table/index/foreign-key addition.

CI's first run at `58fb6cc4` passed the application suite (2,200 tests,
13,812 assertions, zero failures/errors, one skip) but exposed a browser setup
error: `db:prepare` seeds the City Council committee, while the new helper tried
to create it again. The helper now reuses that canonical committee. Against a
separate database prepared with the same `bin/rails db:prepare` command,
`CHROME_BIN=/usr/bin/chromium bin/rails test:system` passed all **24 journeys,
779 assertions, zero failures/errors/skips**. The changed helper also passed
RuboCop. This follow-up changes test setup only; application code remains at
the revision recorded above. Runtime-image checks and automatic code/security
reviews completed at `58fb6cc4`, with no review findings posted.

No paid generation, production data transfer, historical backfill, merge or
deployment ran. No new schedule or production configuration was introduced.
