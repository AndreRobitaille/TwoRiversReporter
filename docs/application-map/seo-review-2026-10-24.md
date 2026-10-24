# October 24 SEO and AI-search review

Review base: `7effc9cf933314bae84db09033186bea1b6a90d0`. The metadata changes
are submitted on `codex/seo-metadata-fixes`. Environment: Linux, Ruby 4.0.7,
PostgreSQL, synthetic test records. No production records were copied.

The owner authorized small fixes and requested that changes materially affecting
appearance or operation remain unaddressed with reasons recorded on GitHub.
The issue proposals are options, not approved product specifications.

## Decisions and scope

| Issue | Local change | Deeper review left open |
| --- | --- | --- |
| [198](https://github.com/AndreRobitaille/TwoRiversReporter/issues/198) | None | Archive/navigation and homepage selection alter resident discovery; IndexNow introduces external notification operations; additional sitemap feeds need a discovery/access contract. Composite member/committee lastmod is deliberately omitted by the Development Plan rather than derived from misleading parent dates. |
| [199](https://github.com/AndreRobitaille/TwoRiversReporter/issues/199) | Public topic descriptions replace boilerplate fallback snippets; names use the existing title formatter. An allowed briefing headline still takes precedence. | Visible dates/badges and freshness provenance; stored-name/H1 casing and acronym rules; duplicate-topic editorial merges. Google indexing recovery is unverified. |
| [200](https://github.com/AndreRobitaille/TwoRiversReporter/issues/200) | Official profile title/description reuse current office or first displayed current membership and its existing badge label. | New navigation links, anonymous committee rosters, and additional Person/role schema. The current-office title exception already existed before this review. |
| [201](https://github.com/AndreRobitaille/TwoRiversReporter/issues/201) | Remove the incomplete Event node, retaining publisher/paywall data, meeting dates and cancellation notices. | Accurate source-backed venue/address data and on-page presentation; richer anonymous snippets. Scraped agenda titles are withheld by the existing access contract and already available to allowed readers through the description fallback. |
| [203](https://github.com/AndreRobitaille/TwoRiversReporter/issues/203) | Homepage WebSite node with canonical root/name; Organization.sameAs links the owner-confirmed Facebook page. | Optional visible footer link is a design decision. Google chooses whether to use the metadata. |
| [204](https://github.com/AndreRobitaille/TwoRiversReporter/issues/204) | None | Rewriting the approved headings or adding subheadings changes page voice and layout. Existing page titles and homepage tagline already identify Two Rivers. |

Related tracker decision: retain #143 for remaining Bing/OpenAI/Anthropic/
Perplexity production retrieval checks, crediting Google's recorded October 24
evidence rather than claiming every provider is verified. #141 retains its
operator-verification prerequisite. Local synthetic crawler tests do not replace
real provider visits. The October 30 Haldir follow-up and Search Console's old
sitemap submission remain outside this local patch.

## Acceptance and affected boundaries

Binding requirements: [Development Plan](../DEVELOPMENT_PLAN.md),
[public access design](../superpowers/specs/2026-07-24-tiered-public-access-design.md),
[crawler policy](../verified-crawler-access.md),
[roster authority](../superpowers/specs/2026-09-03-canonical-committee-rosters-design.md),
and the owner's scope above. Affected workflows: RES-04, RES-06, RES-10,
RES-11 and RES-12. RES-01/05/09 navigation changes are deferred.

- Topic public metadata may reuse the already public dek. Withheld briefing
  text must remain absent for anonymous and spoofed requests. Real HTTP requests
  first prove allowed Google access, then prove anonymous/spoofed fallback;
  title/social tags escape quotes and ampersands. Updating the persisted
  description changes the next request. Blank descriptions retain a fallback.
- Allowed Google, approved members and open-mode readers retain the existing
  briefing snippet. Only a seeded IP-range snapshot is simulated; routing,
  rendering, access decisions and database changes remain real.
- Official titles use the existing current-office priority, then displayed
  membership ordering (City Council first, otherwise alphabetical). Board-specific
  badge titles win over generic roles. Ended/staff/non-voting memberships cannot
  supply a current membership title. Ending offices/memberships changes the next
  request; no current role produces the generic fallback. Names/headings and
  voting access stay unchanged.
- The homepage identifies exactly one WebSite at the canonical apex root,
  including requests to another host or with tracking parameters. Organization
  points only to the confirmed Facebook profile. Other pages need no WebSite node.
- Meeting pages omit incomplete Event markup for anonymous, verified Google
  and open-mode requests, including stored/absent locations. Cancellation notices
  and visible date markup remain. This removes invalid data, not a valid event
  feature. Restoring eligibility needs further review.

Google's [site-name guidance](https://developers.google.com/search/docs/appearance/site-names)
requires the WebSite name/root URL on the homepage. Its
[event guidance](https://developers.google.com/search/docs/appearance/structured-data/event)
requires location/address data. Removing Event markup does not establish event
eligibility or show that a live Search Console error has cleared.

## Commands and results

Baseline before edits:

```sh
PARALLEL_WORKERS=1 bin/rails test test/controllers/seo_markup_test.rb test/helpers/topics_helper_test.rb
```

58 runs, 209 assertions, no failures/errors/skips.

Focused post-change application/HTTP regression run:

```sh
PARALLEL_WORKERS=1 bin/rails test test/controllers/search_metadata_test.rb test/controllers/seo_markup_test.rb test/helpers/topics_helper_test.rb test/helpers/meetings_helper_test.rb test/controllers/members_controller_test.rb test/controllers/members_show_gating_test.rb test/controllers/topics_show_gating_test.rb test/controllers/meetings_gating_test.rb test/controllers/anonymous_leak_sweep_test.rb test/controllers/google_crawler_access_test.rb test/controllers/sitemaps_controller_test.rb
bin/rubocop
git diff --check
```

171 runs, 1,273 assertions, no failures/errors/skips. RuboCop inspected 612
files with no offenses; its sandboxed cache directory was unwritable, so it
continued without caching. A final `XDG_CACHE_HOME=/tmp/trr-seo-rubocop-cache
bin/rubocop` also passed without cache warnings. The final metadata-only rerun
passed 7 tests / 143 assertions after strengthening the active staff/non-voting
fixtures. The initial new-test run exposed an unsupported
CookieJar.clear call; replacing it with deletion of the session cookie fixed
the test harness. No product defect is inferred from that harness error.

HTTP workflow evidence is in
[SearchMetadataTest](../../test/controllers/search_metadata_test.rb).
It runs through the ordinary `bin/rails test` runner. No browser/system suite,
full CI, production SSH, deployment, Search Console inspection, paid AI or real
provider retrieval ran for this patch. Changes affect head metadata only;
visible controls, navigation and dynamic browser behavior were not modified.

## Representative defect detection

An isolated copy of the patched checkout at
`/tmp/trr-seo-faults-awz1wueh` used the separate local database
`two_rivers_reporter_seo_review_test`. Setup and baseline:

```sh
DATABASE_URL=postgresql:///two_rivers_reporter_seo_review_test RAILS_ENV=test PARALLEL_WORKERS=1 bin/rails db:create db:schema:load
DATABASE_URL=postgresql:///two_rivers_reporter_seo_review_test RAILS_ENV=test PARALLEL_WORKERS=1 bin/rails test test/controllers/search_metadata_test.rb
```

The clean baseline and final restored suite each executed 7 tests / 143
assertions with no failures/errors/skips. Each mutation below was applied
alone; the matching `-n /pattern/` run failed at the intended assertion with
one failure, zero errors and zero skips. Each was restored and rerun green.

| Bounded fault | Exact test-name pattern | Observed assertion failure |
| --- | --- | --- |
| Skip the public-description branch | `/topic_snippets_stay_distinct/` | Boilerplate replaced the expected distinctive public description. |
| Remove the headline access guard | `/public_topic_descriptions/` | Anonymous metadata contained the withheld headline after allowed content was proven. |
| Skip current-office precedence | `/current_office_takes_precedence/` | The title used a committee-prefixed role instead of the primary office. |
| Include ended memberships | `/official_metadata_uses/` | An ended Old Board chair supplied the current title. |
| Include active staff/non-voting memberships | `/official_metadata_uses/` | A non-voting board supplied the public current title. |
| Emit Organization instead of WebSite on home | `/home_names_the_website/` | The expected WebSite node was absent. |
| Substitute an incorrect Facebook profile | `/home_names_the_website/` | sameAs identified the wrong profile. |
| Reintroduce incomplete Event JSON | `/meeting_pages_omit_incomplete_event/` | An Event node was present when the expected result was none. |

Full transient output: `/tmp/trr-seo-faults-awz1wueh/fault-results.txt`.
These are demonstrated local assertion failures, separate from implementation
coverage and the unverified production/search outcomes above.

## Tracker disposition

All six SEO issue status notes and review comments were updated and read back
as open on October 24. #143 was retitled and narrowed to the remaining
production-provider checks; #141 received the limited xAI-source review and
retains its verification prerequisite. No issues were closed, code committed,
branches pushed, PRs created, or production changes deployed during the initial
review.

Andre subsequently authorized committing, pushing and opening a PR for the
metadata changes, with deferred items kept open and no deployment. The PR
references #199/#200/#201/#203 without automatic issue-closing keywords;
#198/#204 and the broader deferred decisions above remain open. The PR is a
review artifact, not approval to deploy or evidence of changed search results.
