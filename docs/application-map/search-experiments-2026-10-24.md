# Search experiments — October 24, 2026

Andre redirected the review from waiting for a demonstrated defect to making
bounded changes, measuring outcomes and adjusting. Troi, Haldir and Orophin
collaborate on product priorities and measurement; Codex implements. Deployment
remains a separate authorization. This supersedes the earlier no-change-until-
defect disposition without making its causal hypotheses established facts.

## Bet 1: durable meeting discovery

[Issue #210](https://github.com/AndreRobitaille/TwoRiversReporter/issues/210)
records the agreed contract. Workflow RES-05 gains a visible archive link,
year-grouped month directory, and monthly lists of past canonical meetings.
The mechanism being tested is persistent internal linking after meetings leave
the 21-day recent window. An archive has resident value even if search does
not improve. Existing backlinks and sitemap entries already provide other
discovery paths; this is not a claim that old meetings were entirely orphaned.

Archive pages contain public date/body/cancellation facts only, including for
approved readers and crawlers. The destination reporting gate is unchanged.
No generated text, private source URLs or topic aggregations are added here.
No schema change, AI generation, indexing notification or sitemap change.

Canonical identity follows `Meeting.preferred_duplicate`, including canceled
and content-bearing records. Calendar grouping uses application local time,
not UTC dates. Future meetings enter the archive only once their time passes.
Months are capped to 50 canonical records per page; additional pages have
ordinary HTML links and distinct canonical paths. Empty/invalid months and
out-of-range pages return 404, while `/page/1` redirects to the month. Query
parameters cannot select a different page under the same canonical path.

## Measurement and decisions

Haldir owns GSC/Bing observations; Orophin owns the fixed AI-search sample;
Troi owns the continue/adjust/stop decision. The clock starts at deployment,
not the October 24 code review. Existing Oct 31/Nov 21 metadata checks remain
distinct; do not silently treat them as archive deployment checkpoints.

- Freeze the pre-release states for meetings 270, 277, 282 and 288. On Oct 24,
  Haldir reported three never crawled and 277 indexed from Sep 27. Preserve
  property disagreements and compare stored content where available.
- Keep the [nine-URL diagnostic baseline](https://github.com/AndreRobitaille/TwoRiversReporter/issues/198#issuecomment-6388376772)
  for context. Newer meetings 297/298 are not matched experimental controls.
- Capture the pre-release 28-day GSC/Bing page and query totals for the frozen
  cohort and all meeting pages, separating brand from non-brand and each
  engine. Compare equal subsequent windows, reporting absolute counts and
  denominators. Historical ranking should use the available year-plus history,
  with WordPress, access changes, seasonality and current-site periods separated.
  Aggregate impressions are exposure, not total query demand. Low-volume or
  incomplete results are inconclusive, not a positive result.
- **2 weeks:** inspect archive ingestion and the fixed past-meeting cohort.
  If the archive has not been crawled, verify its discoverability; if it has,
  count new crawls and refreshed stored copies. Record first-observed crawl
  intervals prospectively: last-crawl dates cannot reconstruct first crawls.
- **4 weeks:** report changes in crawled/indexed counts for the fixed cohort.
  If archive ingestion works but no target progresses, revise the hypothesis
  and choose the next change rather than extending observation indefinitely.
- **8 weeks:** compare non-brand impressions/clicks and resident usage. Claim
  no SEO win without observed improvement. Keep useful archive navigation if
  warranted, but stop treating it as the active SEO growth bet if it has not
  helped. Other releases and content changes prevent strong causal attribution.
- **Rollback:** revert the feature if harmful. If removing published archive
  URLs, plan appropriate redirects rather than creating dead inbound links.

Indexing is necessary for Google's AI supporting links but does not establish
citation success. Orophin's sample records query, engine, date/context, whether
an AI answer appears, TRM citations and competing sources. No AI answer is
distinct from an answer that omits TRM. GSC Web mixes conventional and AI search;
it cannot supply a clean AI-only effect estimate. See [Google's guidance](https://developers.google.com/search/docs/appearance/ai-features).

## Verification

Acceptance derives from #210 and the public-access contract, not the existing
21-day implementation. Synthetic PostgreSQL databases and offline tests verify
RES-05 through HTTP and real browser navigation. Provider search results are
future production measurements, not simulated local test successes.

Base revision `39a9ab39498ed3c717734fb91aa09ae38bf404cf`; branch
`codex/meeting-archive-experiment`. Local Ruby 4.0.7 / PostgreSQL with synthetic
database `two_rivers_reporter_archive_test`, `RAILS_ENV=test`,
`PARALLEL_WORKERS=1`. Commands actually run:

- `bin/rails db:create db:schema:load` for the isolated database.
- `bin/rails test`: 2,121 tests / 12,847 assertions, no failures or errors,
  one existing skip.
- `CHROME_BIN=/usr/bin/chromium bin/rails test:system`: full suite, 19 journeys /
  677 assertions, no failures, errors or skips, run serially after application tests.
- `bin/rails test test/controllers/meeting_archives_controller_test.rb test/controllers/search_metadata_test.rb`:
  12 tests / 273 assertions, no failures, errors or skips (final isolated copy).
  Covers date boundaries, later requests after time advances, canonical
  cancellations/content preference, pagination identities/caps, redirects,
  rejected inputs/formats, full-response content checks and destination gates.
- `bin/rails assets:precompile`, then
  `CHROME_BIN=/usr/bin/chromium bin/rails test test/system/meeting_archive_journeys_test.rb`:
  2 journeys / 22 assertions, no failures, errors or skips. Real browser follows
  Meetings → archive → month → meeting → Back/reload → adjacent month → directory.
  Runs in open and gated anonymous modes; approved-reader and verified/spoofed
  crawler requests are covered by HTTP. Desktop 1280px and mobile 320px rendered
  screenshots were inspected; no horizontal overflow at 320px.
- `RUBOCOP_CACHE_ROOT=/tmp/trr-archive-rubocop bin/rubocop`: 616 files, no offenses.
- `git diff --check`: clean.

The initial browser run discovered all 19 system tests; only the two new
assertions failed because CSS transforms headings to uppercase. Matching was
corrected without weakening the text requirement. A stale local compiled asset
manifest was regenerated before the successful rendered checks. The installed
Chromium and chromedriver are both 155.0.8059.84; Selenium's autodetection warning
mentions another Chrome version, but the explicit binary ran successfully.

An isolated source copy at `/tmp/trr-archive-faults-biedl3pb`, using separate
database `two_rivers_reporter_archive_fault_test`, demonstrated these faults.
Each started green, produced exactly one intended assertion failure (no errors
or skips), was restored, and reran green:

| Mutation | Assertion that detected it |
| --- | --- |
| Select the first duplicate instead of the canonical meeting | Cancellation link identity |
| Increase the month page cap from 50 to 500 | First-page record count |
| Render a saved meeting recap into the archive | Full-response reporting canary after allowed detail content was proven |
| Send the archive link to the homepage | Real browser destination after clicking the visible link |

The final HTTP suite in that copy passed 12 tests / 273 assertions. Local logs
are in the copy and `/tmp/trr-archive-*.log`; browser images are in
`tmp/screenshots/meeting-archive-{mobile,desktop}.png`. These are implementation,
workflow and defect-detection evidence, not evidence of improved search traffic.
No production mutation, deployment, paid generation or live email was performed.
