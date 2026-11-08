# Recorded votes on member profiles — November 8, 2026

This bounded RES-10/RES-11 slice follows the [council design's delivery
adjustment](../superpowers/specs/2026-11-07-council-accountability-design.md#delivery-priority-and-proportionality).
The existing featured voting record is selective. Readers can now choose
**All recorded votes** on the same member page, including procedural motions,
with 25 records per page and links to the meeting and its sources.

## Acceptance and limits

- Show the stored motion description separately from its agenda title: two
  motions under one agenda item remain two decisions. Multi-topic associations
  do not duplicate rows. Display the stored member vote and recorded yes/no tally.
- Preserve newest-first ordering with a stable ID tie-break, view selection
  across pages, and understandable empty/overflow states.
- State that the site's record may omit meetings or votes. Missing records do
  not establish absence or abstention. This is not a complete term denominator.
- Reuse saved records without AI calls. A saved vote correction appears on the
  next request. This slice adds no extraction, mutation, or refresh pipeline.
- Retain existing open/gated/verified-crawler access and reporting cache rules.
  No withheld votes or pagination appear for a gated anonymous visitor.

Service periods, term-scoped comparisons, campaign/action matching and new
attendance calculations remain outside this slice. The forum speaker review is
pending owner input; remind the owner when forum evidence is next needed. It
does not block this recorded-vote view.

## Executed verification

Application revision: `c86ae499ae254aa9dcaefa64da3e0224d5ef632f`, based on planning
revision `36e889accfb8b2f77f75c2b66d8e2b742d36dabe`. Subsequent changes in this
slice's evidence commit are documentation only. Environment: Ruby 4.0.9, isolated
local PostgreSQL database, `RAILS_ENV=test`, `PARALLEL_WORKERS=1`; application and
browser tests ran serially. The shared permanent bundle path was verified and
development boot succeeded.

| Command | Result |
| --- | --- |
| `bin/rails test test/integration/member_recorded_votes_test.rb test/controllers/members_controller_test.rb test/controllers/members_show_gating_test.rb` | 22 tests, 161 assertions, no failures/errors/skips |
| `CHROME_BIN=/usr/bin/chromium bin/rails test test/system/member_recorded_votes_journeys_test.rb` | 1 journey, 39 assertions, no failures/errors/skips |
| `bin/rubocop --cache false` | 635 files, no offenses |
| `git diff --check` | Passed |

HTTP checks exercised real rendering, saved corrections on a later request,
25/1 pagination, no duplicates, empty/overflow pages, open and authenticated
access, logout, anonymous gated HTML/page/JSON requests, and verified crawler
access with a deterministic IP-range cache. The JSON variant returns 406.
An AI-service constructor guard proves these page reads do not call AI.

The browser journey used real magic-link sign-in, cookies, CSRF and Turbo logout;
only email delivery was captured. It switched both views, traversed both pages,
opened the meeting's source in a new window, returned, and checked withheld
content after logout. Desktop (1280px) and phone (390px) screenshots were inspected.
The phone has no horizontal overflow; the voting heading and view controls remain
below the sticky header after anchor navigation. Local screenshots are in
`tmp/screenshots/recorded-votes-{desktop,mobile}.png` (not committed).

All civic records were explicitly synthetic. A local HTTP publisher stood in for
the external source; no assertion claims to validate a live publisher or a real
member's record. Chromium completed the journey despite a driver-version warning.

## Demonstrated defect detection

After a clean baseline, two temporary faults were applied separately and restored:

1. Filtering out a closed-session motion: the five-row assertion failed with four
   rows (1 test, 4 assertions, 1 failure, no errors).
2. Bypassing the member controller's visitor gate: the withheld-description
   assertion failed (1 test, 7 assertions, 1 failure, no errors).

After restoring the exact controller, the new integration file passed all five
tests and 98 assertions. These prove detection of the bounded defects, not their
frequency in production. No paid AI, production operations, data backfill, merge
or deployment ran. Full-suite CI is reported on the pull request separately.


## Owner review follow-up: Featured pagination and procedural votes

Revision `0093a897bffda825da8b125316b8219a275a18f9` addresses the owner's preview feedback. Both views now
paginate 25 distinct saved decisions, with controls above and below the list.
Featured retains topic grouping and opens Other Votes by default. Motion links
show the stored description so separate decisions under an agenda remain clear.

The shared website/API selector omits a procedural motion only when it passed
and every recorded non-absent vote is yes. A no, abstention, recusal, failed vote
or unknown outcome prevents that exclusion. Important-topic links do not bypass
the rule. Local saved records confirmed the closed-session wording variants
"convene," "enter" and "move"; these and consent-agenda acceptance are covered.
The unfiltered All recorded votes view remains available. No new AI calls or
attendance/eligibility denominator is introduced.

Verification on this revision, in the same isolated environment:

- The prior focused application command plus
  `test/controllers/api/resident_api_test.rb`: **47 tests, 890 assertions**, no
  failures/errors/skips, after restoring the fault below.
- `bin/rails test test/system/member_recorded_votes_journeys_test.rb` with Chromium:
  **2 journeys, 50 assertions**, no failures/errors/skips. The additional phone
  journey follows Featured → older page → contested procedural vote → meeting →
  back → newer page. The 390px screenshot was inspected; no horizontal overflow.
- `bin/rubocop --cache false`: **635 files, no offenses**.
- A process-local override reinstated blanket procedural filtering. The assertion
  requiring the contested motion failed (1 test, 2 assertions, 1 failure, no
  errors); the normal suite then passed. The running preview was unaffected.
- Documentation links/anchors and `git diff --check` passed.

The preview now runs independently of the tool session as a local user service
bound to `0.0.0.0:3000`, using the existing development database. Its HTTP response
and listener were verified. No production operation or paid source analysis ran.
