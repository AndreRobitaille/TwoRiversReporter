# Member record layout checks — November 8, 2026

Scope: RES-10 and the RES-11 access boundary, based on the owner's November 8
direction in [the development plan](../DEVELOPMENT_PLAN.md) and the audience's
[search usage](../AUDIENCE.md). The ongoing record is primary; campaign context
is secondary. Other Votes starts closed. Saved sourced content remains readable
through the existing permitted crawler path.

## Implemented behavior

- Desktop: campaign statements occupy a narrower complementary column beside
  service, committees, attendance and votes. Profiles without statements retain
  their existing single-column width.
- Phone and document order: the main record comes first, with jump links to
  voting and campaign sections. Campaign statements, sources and related actions
  retain their existing wording and controls.
- Other Votes uses a closed native disclosure. Its saved decisions and meeting
  links remain in the permitted response; expanding it needs no extra request.
- A verified Google request receives the same saved campaign text and sources
  as an allowed resident. A spoofed Google user agent remains gated. Reading
  either representation does not invoke generation.

## Local implementation and workflow checks

Environment: branch `codex/member-record-layout`, based on
`6fe4d8efac46d685df8a99d5177ea1b714023fae`, with this change applied; Ruby 4.0.9,
PostgreSQL, Chromium. Automated tests use a separate test database and
deterministic campaign-provider responses.

Commands actually run, serially against that test database:

```sh
bin/rails test test/integration/member_profile_layout_test.rb \
  test/integration/member_campaign_activity_test.rb \
  test/integration/member_campaign_record_test.rb \
  test/integration/member_recorded_votes_test.rb \
  test/controllers/members_controller_test.rb
bin/rails test test/system/member_campaign_activity_journeys_test.rb \
  test/system/member_campaign_journeys_test.rb \
  test/system/member_recorded_votes_journeys_test.rb
bin/rubocop
```

Results: **33 application tests / 380 assertions** and **5 browser journeys /
138 assertions**, all passing with no skips; **779 Ruby files**, no offenses.
The browser runner exercised desktop geometry, phone ordering, disclosure
expansion, related-action expansion, meeting navigation, back/refresh and overflow.
The HTTP test first proves the allowed text exists, then checks the real crawler
verification path with a cached deterministic Google IP feed and rejects a
spoofed address. The IP feed is simulated; access decisions and rendering are not.

## Demonstrated defect detection

The new HTTP checks failed against the original layout: missing primary/sidebar
structure and an open Other Votes disclosure. After implementation they passed.

An isolated test-process response mutation then restored `open` on Other Votes.
The browser journey passed first (**1 journey / 21 assertions**), failed at the
intended closed-disclosure assertion with the fault (**1 journey / 4 assertions,
1 failure**), and passed again after removing it (**1 / 21**). No application
files or real preview data were altered by that fault.

## Real-data browser observation

The existing local civic-data copy was used for Bittner, Brandt and Derby, with
their **3 / 2 / 2** saved campaign statements respectively. No new production
copy or provider analysis was run. Desktop and 390-pixel phone views retained
their statements, sources, recorded attendance and votes without overflow.
The campaign jump lands below the fixed header. Other Votes starts closed;
expanding it exposes real saved decisions. Brandt's vote link reached its
Advisory Recreation Board meeting, then browser back and refresh restored the
member page with two campaign statements and Other Votes closed.

## Limits

This is a layout and access regression check, not a new source-accuracy audit.
The local record still has the previously disclosed historical coverage gaps.
No paid generation, production backfill, merge or deployment was performed.
No live Google visit, indexing result or AI answer inclusion was verified.
Google documents ordinary search eligibility for
[AI features](https://developers.google.com/search/docs/appearance/ai-features);
the local checks establish readable permitted HTML, not a promise of inclusion.

## Sidebar revision after owner feedback

The owner rejected the initial sidebar as a wall of text. The earlier passing
layout checks did not establish that the information hierarchy was useful.
This follow-up on base `32837e210c4a1db40934c6ac0e579e9db3167801` changes the
default reading surface to short, unboxed statement rows. Classification badges,
publisher/date repetition, questions and related vote details no longer compete
with the statements in the initial view. Conditions and deadlines remain visible
because omitting a qualification could change the reader's takeaway.

Each native disclosure opens its supporting source/context and related record;
opening another closes the previous one. Three statements per election are shown
first in existing source order, with remaining statements behind a separate
closed disclosure. This is a presentation limit, not a claim that the first three
are more important. All saved content and source links remain in permitted HTML.

The same focused application command above now runs **34 tests / 392 assertions**;
the browser command runs **5 journeys / 147 assertions**, all passing. RuboCop
still passes across **779 files**. The added checks cover the three-statement
limit separately from source retention, closed initial details, one-at-a-time
expansion, visible qualifications, source navigation and later refresh. Existing
verified-crawler, spoof denial and offline page-read checks remain green.

A test-process fault adding `open` to the first campaign statement reproduced
the rejected expanded default. The publisher-link journey passed first
(**1 / 44**), failed at the intended collapsed-state assertion (**1 / 20,
1 failure**), and passed after removing the fault (**1 / 44**).

Real local Bittner, Brandt and Derby pages retain their **3 / 2 / 2** statements.
Bittner's collapsed campaign section contains 33 visible words, including its
heading and election date, instead of displaying its source and vote detail by
default. Desktop and phone screenshots were inspected; the native keyboard
control opens/closes the evidence, and the 390-pixel views do not overflow.
This verifies the implemented presentation, not resident satisfaction; the
owner's next visual review remains the usability checkpoint. No source analysis
or stored civic evidence was changed.
