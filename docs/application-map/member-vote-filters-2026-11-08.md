# Member vote search and filters — November 8, 2026

Scope: RES-10/11, #237 under #234. Binding requirements are the
[council decision record](../superpowers/specs/2026-11-07-council-accountability-design.md#decision-record)
and member-page specification: a searchable, filterable record, with unchanged
term eligibility, clear member/Council results, source navigation and low cost.
The owner requires compact controls and real-data development verification.

## Reader behavior

Search applies all entered words, case-insensitively, to the saved motion and
agenda context title. A closed Filter votes disclosure offers approved topic,
meeting body, substantive/procedural and divided-vote selections. Divided requires
both a recorded yes and a recorded no; abstention, absence and recusal do not
create dissent. Filtering reuses the existing procedural/featured rule: featured
still omits unanimously approved procedural decisions, while All recorded keeps
them. No new classification, conclusion or AI call is introduced.

Filters apply before the 25-row pagination. A decision linked to multiple topics
appears once. Search/filter state survives page and view navigation and the period
form; changed searches reset the page. Clear keeps the chosen term and view.
Topic/body options come only from that member's scoped records, with unapproved
topic identities omitted. Unknown/non-scalar choices are ignored, search is
bounded to 200 characters, and punctuation is literal rather than a SQL wildcard.

The form uses native GET navigation to preserve its voting-record anchor. Turbo
GET submission dropped the fragment during real browser verification. Hidden
state fields omit IDs so they do not compete with visible control labels.
Anonymous gated responses never construct or expose the filter inventory; normal
permitted HTML and existing verified-crawler behavior remain in place.

## Executed evidence

Isolated checkout `codex/member-vote-filters`, base `b07cbc9`, Ruby 4.0.9,
PostgreSQL `trr_member_vote_filters_test`. No production operations, paid AI,
backfill, merge or deployment. No test fixtures were loaded into the real preview.

- `bin/rails test test/integration/member_vote_filters_test.rb
  test/integration/member_recorded_votes_test.rb
  test/integration/member_council_period_test.rb`: **22 tests, 293 assertions**,
  no failures/errors/skips. Covers combined search, topic uniqueness, literal
  punctuation, pre-pagination counts, corrected votes, body/term scope, distinct
  procedural modes, view/period/clear links, unique label IDs and gated reads.
- Browser journey exercises visible controls → search → filters → page two →
  meeting source → back → clear, preserving the service period and record view.
  The focused journey and existing period journey ran serially on the same test
  database: **2 tests, 31 assertions**, no failures/errors/skips. The initial test filled the old form before Turbo finished switching
  views; it now waits for the selected view before typing. This was test timing,
  distinct from the real lost-anchor behavior fixed in the application.
- Representative isolated faults: dropping the search predicate produced 27
  matches instead of 26; bypassing access exposed the filter form to an anonymous
  visitor; restoring Turbo form handling lost the voting-record fragment. Each
  intended assertion failed, the fault was restored, and the checks reran green.
- Full `bin/rubocop`: **825 files, clean**. Documentation link checks and
  `git diff --check` passed. No
  migration or data write is needed for these controls.

## Real-data behavior

Guarded patches added only this slice to the combined development preview; forum,
campaign and other session work was preserved. The real local copy was neither
reimported nor reset. On Doug Brandt's selected Council period, searching for
`concession` returns two December 1, 2025 decisions. Both remain when narrowed to
Neshotah Beach and divided votes: the renovation funding authorization and the
operations plan. Those are distinct recorded decisions, not project completion.

The actual form was exercised in Chromium at 390 and 1280 CSS pixels. Native
submission retained `#voting-record`, placed the heading below the fixed header,
and showed the two recorded motions with their source links. No horizontal
phone overflow was observed. Screenshots were inspected locally; the development
server remains bound to `0.0.0.0:3005`.

The other review session's voter agents remain unreachable through the app's
local transport. No new persona review is claimed. Full-term coverage, later
source backfill and the remaining non-filter acceptance under #237 remain
separate from this slice.

Review follow-up: preload agenda parents and skip constructing search text for
empty searches. Three distinct parent headings now load in one batch; the
regression verifies matching parent text and at most two agenda queries. Removing
the preload caused four agenda queries and the intended assertion failed; the
restored test passed (1 test, 3 assertions). Full RuboCop remained clean.
