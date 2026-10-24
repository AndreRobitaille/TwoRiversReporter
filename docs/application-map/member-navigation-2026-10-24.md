# Voter-profile navigation experiment — October 24

Base: `39a9ab39498ed3c717734fb91aa09ae38bf404cf`; branch
`codex/member-vote-profile-links`. Related: [#200](https://github.com/AndreRobitaille/TwoRiversReporter/issues/200).
This follows the owner's instruction to make bounded SEO/AEO bets with Troi,
Haldir and Orophin. It supersedes the initial deferral of these particular
links in the [metadata review](seo-review-2026-10-24.md), without changing the
other deferred roster, schema or access decisions.

## Bet and acceptance

Haldir's October 24 history review found 38 member-page clicks, 31 topic-page
clicks and 5 meeting-page clicks in the final July 25–October 22 GSC window.
This makes existing official profiles a reasonable next investment; it does
not prove missing links caused the current performance. Most query rows are
withheld, so this is a page-type comparison, not a measured name-query total.

Already visible voter names become ordinary server-rendered links to the
stored member ID in meeting roll calls and topic Key Decisions. They update
automatically as vote records change. The profile's existing topic and meeting
links let readers continue researching the same record. A missing member on
a meeting vote retains the existing plain-text `Unknown` fallback.

Binding requirements: the [Development Plan](../DEVELOPMENT_PLAN.md),
[public access design](../superpowers/specs/2026-07-24-tiered-public-access-design.md)
and [verified crawler policy](../verified-crawler-access.md).
Affected workflows: RES-04, RES-06, RES-10 and RES-11.

- Open readers, approved members and verified crawlers can follow links where
  they already receive votes. Anonymous and spoofed crawlers in gated mode
  receive neither the vote identity nor its new link, including hidden HTML
  and head metadata.
- Link creation does not resolve names. `ExtractVotesJob` already resolves
  names from `minutes_pdf` text; absent votes use attendance created by
  `ExtractCommitteeMembersJob`, which also requires minutes text. These are
  city-posted minutes, not a new claim of formal approval or perfect historical
  extraction accuracy. Transcript prose is not a writer of these vote rows.
- No new AI call, reprocessing job, database field, sitemap policy or crawler
  verification rule is needed. The existing reporting gate stays in place.

## Measurement and rollback

Haldir owns the search read after the actual deployment: check referring-page
discovery and recrawl at one week; compare the member cluster's impressions,
clicks, CTR and number of URLs with impressions against the preceding 28 days
at four weeks. Keep the existing member sample (4, 71, 213) and record which
members actually received inbound links. URL Inspection referring URLs are
an incomplete sample, not a complete internal-link inventory.

Keep the deploy date and prior #209 metadata change in the results. Concurrent
changes and small counts prevent clean causal attribution. Treat historical
page/query comparisons as directional. User navigation is a separate benefit;
do not label this an SEO success without search evidence or promise AI citations.
An access leak or wrong destination warrants correction or reverting the two
view changes. A noisy search-count fluctuation alone does not.

## Local verification

Synthetic records only; Linux, Ruby 4.0.7, PostgreSQL database
`two_rivers_reporter_archive_test`, `RAILS_ENV=test`, `PARALLEL_WORKERS=1`.
Browser: Chromium/chromedriver 155.0.8059.84, explicit
`CHROME_BIN=/usr/bin/chromium`. Selenium's discovery warning refers to a
different installed Chrome; the explicit binary ran successfully.

Commands:

```sh
bin/rails test test/integration/vote_profile_navigation_test.rb test/controllers/meetings_controller_test.rb test/controllers/topics_controller_test.rb test/controllers/search_metadata_test.rb
bin/rails test test/system/resident_navigation_journeys_test.rb
RUBOCOP_CACHE_ROOT=/tmp/trr-member-links-rubocop bin/rubocop
git diff --check
```

The HTTP tests prove allowed content before denial checks, correct member
identity, profile-to-record navigation and voter-name absence from head metadata.
Only the provider IP-range snapshot is simulated; routing, access decisions,
rendering and records are real. The browser journey signs in through the real
magic-link confirmation flow with captured synthetic email, follows meeting →
profile → topic → profile → meeting, and checks the link after a reload. The
390px screenshot was inspected and the page has no horizontal overflow.

The focused application/HTTP run passed **100 tests / 565 assertions**; the
navigation browser file passed **5 journeys / 87 assertions**. Neither had
failures, errors or skips. RuboCop inspected **613 files** with no offenses.
Links are underlined so the new action is visible on touchscreens as well as
on hover. A simplification review retained the direct view changes; no new
abstraction was necessary.

A subsequent browser order exposed a harness issue: the new mobile journey
left the viewport narrow for an existing desktop-navigation test. Resetting
the viewport in this file's setup restores test isolation. The failing seed
(`28876`) was rerun after that correction.

An isolated checkout at `/tmp/trr-member-faults-3e7lca1s` used the separate
`two_rivers_reporter_archive_fault_test` database. Its baseline HTTP tests
passed 2 tests / 47 assertions and the new browser journey passed 1 / 24.
Each fault below produced exactly one intended failure and zero errors;
each was restored and rerun green. Final HTTP results were again 2 / 47.

| Isolated fault | Test filter | Detected outcome |
| --- | --- | --- |
| Meeting voter link points to home | `/member_follows_a_voter_profile/` (browser) | Destination was not the member profile |
| Topic voter link becomes plain text | `/open_readers/` (HTTP) | Expected stored-member link absent |
| Disable visitor gate | `/verified_crawlers/` (HTTP) | Anonymous response exposed the member link after allowed access was proven |

Outputs: `/tmp/trr-member-links-{tests,browser,rubocop}.log` and the isolated
copy's `results.json`. The font/link-decoration adjustment was separately
rendered after asset compilation; the fault checks target navigation and access.

No real email, paid AI, production data copy, merge or deploy is part of this PR.
Local checks cannot establish real provider recrawl or search gains.
