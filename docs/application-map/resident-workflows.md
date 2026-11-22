# Resident and API workflows

All entries are **documented, runtime unverified**. Use [inventory.md](inventory.md)
for audience/mode variants. Contracts come from the [development plan](../DEVELOPMENT_PLAN.md),
[Topic Governance](../topics/TOPIC_GOVERNANCE.md),
[public access design](../superpowers/specs/2026-07-24-tiered-public-access-design.md),
[crawler policy](../verified-crawler-access.md), [roster design](../superpowers/specs/2026-09-03-canonical-committee-rosters-design.md),
and [resident API contract](../read-only-api.md). Presentation disagreements remain
unsettled in the [verification register](verification-register.md).

Subsequent [November 1 date and card-label evidence](meeting-card-dates-2026-11-01.md)
covers specific RES-01/02/03/04/05/06/09/11 variants; the historical discovery
status below does not imply complete coverage of those workflows.

## RES-01 — Discover an issue from What's New (P1)

- **Start / data:** approved reusable topics with recent activity and varied
  impact, briefings present/absent, upcoming council events, with/without images.
- **Action:** open homepage; follow Top Story/Wire topic or Next Up meeting.
- **Required state / visible outcome:** intelligible impact/recency-led discovery
  connects to useful topic continuity and upcoming meeting details; labels align
  with timing and allowed audience. Empty selections still allow broader navigation.
  The [homepage design](../superpowers/specs/2026-04-10-homepage-redesign-design.md)
  gives lead slots a 21-day activity window and More Stories a 30-day window.
  Older high-impact topics can move from a lead slot into More Stories.
- **Next:** destination gives the intended topic/meeting; browser Back returns
  usefully. Candidate acceptance: no duplicate story/wire selection in unchanged data.
- **Failures to distinguish:** no briefing/activity/image, stale timestamp,
  unapproved topic, thin/cancelled meeting, missing record.
- **Observed:** [HomeSelection](../../app/services/resident_content/home_selection.rb),
  [homepage](../../app/views/home/index.html.erb) and partials link all stories/wire
  entries to topics. The approved April 10 homepage design independently requires
  these destinations; older playbook wording was reconciled. Owner clarification
  October 11 (#171) preserves the quiet message, omission of empty Wire/More
  Stories, and visible Next Up/navigation; see [reviewed contracts](behavior-contracts.md).

### November 20 homepage freshness verification

Local patch on `da8d25881a6ca2365fd12e3d7269f223c14ffa63`, Ruby 4.0.9 and
PostgreSQL 18.6, in the Rails test environment with synthetic records.
The [homepage test](../../test/controllers/home_controller_test.rb) checked
that a 20-day-old topic leads, moves to More Stories at day 21 with its original
topic link and no duplicate, and disappears from the homepage at day 30.
The [API test](../../test/controllers/api/resident_api_test.rb) checked that an
authenticated key receives a 22-day-old topic in `wire_cards` and a more recent
topic in `top_stories` (RES-13). The checks exercised rendered HTTP responses and
JSON. Browser and production behavior were outside this verification.

```sh
PARALLEL_WORKERS=1 bin/rails test \
  test/controllers/home_controller_test.rb test/controllers/home_gating_test.rb \
  test/controllers/api/resident_api_test.rb \
  test/services/generated_images/homepage_topic_selector_test.rb \
  test/services/generated_images/topic_eligibility_test.rb \
  test/jobs/generated_images/refresh_homepage_topics_job_test.rb \
  test/jobs/topics/update_topic_briefing_job_test.rb \
  test/services/topics/meeting_reanalysis_service_test.rb \
  test/tasks/topic_reanalysis_task_test.rb
```

The suite passed with 86 tests, 997 assertions, and zero skips. `bin/rubocop`
reported zero offenses across 633 files. Re-running just the two freshness tests
with the lead window temporarily reset to 30 days reproduced both ordering
failures. Restoring 21 days passed both tests with 12 assertions and zero skips.

Follow-up on November 20 used an authorized read-only production snapshot in
development with 612 topics, 311 meetings, and 307 topic briefings. A temporary
`bin/rails runner -e development --skip-executor` script requested `/` through
the development Rack stack with both lead windows and a simulated clock. Both
windows showed the city manager search and Flock on November 20. At 6 p.m.
Central on November 23, the 21-day window moved Flock to the first More Stories
card, and the revolving loan fund took the second lead slot. The card's
original topic URL returned 200. Flock dropped off the homepage at day 30.
The manager search moved into More Stories at 6 p.m. Central on December 7 in
the same snapshot. Those future results assume the stored activity stays fixed.

## RES-02 — Browse active topics and continue the list (P1)

- **Start / data:** more topics than a page, ties in activity, approved/proposed/
  blocked and several lifecycles; appropriate audience/access mode.
- **Action:** Topics → select hero/list card; use Show more where available.
- **Required state / visible outcome:** approved topic identities lead to their
  detail; active list and hero exclusions behave coherently; gated visitors see
  the allowed first-two tier, not a walkable catalog via page variants.
- **Next:** return and continue without reintroducing already shown cards in
  unchanged data. Search is RES-03; Explore is explicitly unfinished.
- **Failures to distinguish:** empty active set, tied ordering, Turbo-stream or
  page variants, removed/blocked target, duplicate hero/list identity.
- **Observed:** [TopicsController](../../app/controllers/topics_controller.rb),
  [HTML index](../../app/views/topics/index.html.erb) and
  [Turbo index](../../app/views/topics/index.turbo_stream.erb).

## RES-03 — Search topics without revealing withheld reporting (P1)

- **Start / data:** a match by canonical name/alias/description; a separate match
  only in withheld briefing text; multiple pages and no-match query.
- **Action:** enter topic query, submit, inspect cards, clear search, follow result.
- **Required state / visible outcome:** approved relevant results or useful empty
  state. Anonymous gated result identity/quantity does not reveal hidden headline
  matches and remains capped to first-page allowed identities.
- **Next:** result opens correct topic; clearing returns active browsing. Allowed
  audiences may search generated headlines; website search is narrower than API research.
- **Failures to detect:** query normalization errors, hidden-text search oracle,
  page-2 identity bypass, blocked result, hidden bytes in attributes/streams.
- **Observed:** [Topic search scopes](../../app/models/topic.rb) and
  [TopicsController#index](../../app/controllers/topics_controller.rb).

## RES-04 — Trace a topic across meetings and decisions (P1)

- **Start / data:** approved topic with multiple past/future appearances,
  briefing/history, linked motions/votes; separately no briefing/no upcoming/no decisions.
- **Action:** read What to Watch/Story/Record, follow upcoming/history meeting and
  decision details; expand relevant decision presentation.
- **Required state / visible outcome:** continuity distinguishes factual record,
  attributed observation and editorial context, without invented resolution,
  consensus or motive. Relevant source/meeting identities remain traceable.
- **Next:** linked meeting matches the event/date/body; reload after a new
  appearance reflects new history. No future meeting is not evidence of resolution.
- **Failures to distinguish:** ambiguous history matching, unlinked motion,
  unsupported vote, stale/legacy briefing, unavailable analysis, deleted/blocked topic.
- **Observed:** [topic show](../../app/views/topics/show.html.erb),
  [TopicsHelper](../../app/helpers/topics_helper.rb),
  [controller](../../app/controllers/topics_controller.rb). Actual sections adapt
  to available data. The April 10 topic design's detailed section-visibility
  matrix governs those expected variants; see [reviewed contracts](behavior-contracts.md).
- **October 24 metadata review:** topic snippets use an allowed briefing headline,
  then the public dek with the existing title casing. Visible headings and dates
  are unchanged; see [scope and evidence](seo-review-2026-10-24.md).
- **November 2 upcoming meeting correction:** Coming Up shows one card per
  meeting, using the first linked item in agenda order. Distinct meetings at the
  same time remain separate; appearance rows and the full record remain intact.
  See [verification evidence](../testing/2026-11-02-topic-upcoming-meetings.md).

## RES-05 — Find an upcoming or historical meeting (P1)

- **Start / data:** upcoming/recent enriched and thin meetings, a historical
  document-text match, duplicate/cancelled identities, several search pages.
- **Action:** Meetings → browse/disclose compact rows or search → open meeting;
  clear query or continue search pages.
- **Required state / visible outcome:** scheduling and available-content labels
  support discovery; matches use public source text/body/date/topic context;
  canonical identities avoid confusing duplicates.
- **Next:** detail matches chosen event; source unavailable or AI missing does
  not make the schedule/source record disappear.
- **Failures to distinguish:** missing start time, no documents, no results,
  deduplication across distinct bodies/times, stale cancellation, gated headline.
- **Observed:** [MeetingsController](../../app/controllers/meetings_controller.rb),
  [index](../../app/views/meetings/index.html.erb),
  [Meeting](../../app/models/meeting.rb). Website lists use 21-day recent/upcoming
  windows; API meeting catalog is not limited to those windows.
- **October 24 archive experiment:** permanent month navigation supplements
  those windows, with canonical past meetings and 50 records per page. See the
  [experiment contract and verification](search-experiments-2026-10-24.md).
- **Reviewed contract:** approved April 10 homepage Next Up cards open the
  selected meeting identity. Story/Wire cards open topics; see
  [behavior contracts](behavior-contracts.md). The new browser navigation
  journey verifies both destinations; enriched historical/search variants remain separate.

## RES-06 — Understand a meeting and share its reporting (P1)

- **Start / data:** structured recap with distinct decisions, speakers and agenda
  details; variants agenda-only, transcript-only, minutes plus transcript,
  legacy markdown, no recap, cancellation, and image missing/disabled.
- **Action:** open detail; read source banner; follow explicit decision→agenda
  anchor, topic door, roll-call disclosure; Share → copy or external/native share.
- **Required state / visible outcome:** correct source tier/timing; distinct
  substantive actions survive projection; factual vote/identity fields retain
  support. Sharing contains only audience-allowed content and correct meeting link.
- **Next:** clipboard actually contains intended text; navigation reaches the
  linked item/topic. A success label does not prove clipboard or external post completion.
- **Failures to distinguish:** ambiguous/missing agenda ID, missing briefing,
  malformed/legacy data, clipboard permission, popup/native-share cancellation.
- **Observed:** [meeting show](../../app/views/meetings/show.html.erb),
  [MeetingsHelper](../../app/helpers/meetings_helper.rb),
  [share JavaScript](../../app/javascript/controllers/share_controller.js),
  [preferred summary](../../app/services/resident_content/meeting_selection.rb).
  Known source changes withdraw saved analysis and explain its absence while
  preserving official links; see [summary withdrawal journey and HTTP checks](meeting-summary-withdrawal-2026-11-07.md).
  Corrected extracted votes also withdraw summaries with incompatible motion
  receipts, even with unchanged minutes; later member and meeting reads are
  covered in [summary fact-dependency checks](meeting-summary-facts-2026-11-07.md).
  A later topic-briefing correction also withdraws a preview with a known receipt,
  including a different future meeting; see [saved agenda dependency checks](agenda-summary-dependencies-2026-11-07.md).
- **Approved contract:** owner clarification October 11 (#171) preserves the
  conditional sections and legacy/agenda-only branches. The March 1 fixed-section
  proposal is superseded; see [behavior contracts](behavior-contracts.md).
- **October 24 navigation correction:** approved topics remain reachable when
  communications appear only in Public Input, without a generated agenda-detail
  card. Structured pages show existing compact topic links for those otherwise
  unlinked topics; inline links are not duplicated and gated visitors retain
  the same access boundary. See [validation evidence](../testing/2026-10-24-topic-context-validation.md).
- **October 24 search metadata review:** incomplete Event markup is omitted;
  venue display and richer anonymous snippets remain deferred. Existing date,
  cancellation, share and access behavior is retained. See [evidence](seo-review-2026-10-24.md).

## RES-07 — Verify a generated claim against its actual source (P0)

- **Start / data:** recap/briefing references with retained source catalog;
  validated PDF page, whole-source recording, changed version and ambiguous legacy reference.
- **Action:** open source chip/citation or recording attribution; inspect linked
  original and supported location. Compare website and API projection.
- **Required state / visible outcome:** sources remain authoritative. Validated
  links identify the actual supplied artifact/version/location; no inferred PDF,
  fabricated transcript page/timestamp, or transcript-derived official vote.
- **Next:** changed/ambiguous reference stays explicitly unresolved; recorded
  remarks remain preliminary/attributed; reading a summary cannot rewrite official evidence.
- **Failures to distinguish:** source revision changed/unreachable, insufficient
  page extraction, missing catalog, packet's old minutes confused with current action.
- **Observed:** [Citations::Resolver](../../app/services/citations/resolver.rb),
  [citation partial](../../app/views/meetings/_citations.html.erb),
  [source catalog](../../app/services/citations/source_catalog.rb). Current gated
  source chips are not clickable for gated anonymous readers, as approved by
  the owner October 11 (#172). Allowed readers retain actual destinations;
  [source verification](policy-matrices.md#public-reporting-and-source-navigation-172) includes a real browser
  request to a distinctive offline publisher and separate raw-URL withholding.

## RES-08 — Open a duplicate or cancelled meeting (P0)

- **Start / data:** same committee/exact timestamp with alternate URLs/title,
  cancellation evidence and stale recap; separate distinct committee/time control.
- **Action:** discover/search/open either duplicate URL; later ingestion sees an older listing.
- **Required state / visible outcome:** one canonical event; cancellation wins
  across list/detail/metadata/sharing. Stale generated recap must not describe a
  cancelled event as held. Original records/documents are preserved.
- **Next:** old duplicate detail URL resolves to the same canonical record; a
  non-cancelled older listing cannot undo cancellation. Distinct events remain distinct.
- **Failures to detect:** lost source/history, conflated bodies/times, stale
  cancellation projection, old analysis still entering API research results.
- **Observed:** [Meeting](../../app/models/meeting.rb),
  [MeetingsController#show](../../app/controllers/meetings_controller.rb),
  [resident selection](../../app/services/resident_content/meeting_selection.rb),
  [discovery job](../../app/jobs/scrapers/discover_meetings_job.rb).

## RES-09 — Find a governing body and current officials (P1)

- **November 22, 2026 mobile election guide (RES-01/09/11).** On a regular
  Council visit the closed guide sits immediately above the roster. A link to
  `#spring-election` opens it. At 390 × 844, Chromium showed all nine local
  roster links before opening the guide. At 1366 pixels the guide was open in
  the right column. On `10aed114` with working changes, the committee, election
  and source-access tests listed below passed 28 tests and 842 assertions.
  `bin/rails test test/system/resident_navigation_journeys_test.rb` passed
  six tests and 99 assertions with zero skips. Forcing the guide open on every
  visit failed the mobile journey’s closed-state assertion. The journey also
  caught a return from a member profile that left the guide closed. Reading
  the URL fragment after Turbo navigation fixed the return trip.

- **November 22, 2026 committee pages (RES-09/11).** Non-Council bodies use
  the Council’s compact roster in a single column. On the local Plan Commission
  page at 390 × 844, the recent topics heading moved from 858 to 582 pixels
  down the page. Chromium opened the full description by keyboard and followed
  both a member link and a topic link. The Library Board at 1366 pixels used
  three roster columns, Explore Two Rivers at 320 used two, and the Board of
  Appeals displayed its empty-roster message. All four omitted the election panel.
  On `10aed114` with working changes, Ruby 4.0.9 and isolated PostgreSQL,
  `bin/rails test test/controllers/{committees_controller,committees_show_gating}_test.rb test/integration/{council_election,source_access_contract}_test.rb`
  passed 28 tests and 840 assertions with zero skips. Temporarily loading the
  election for every committee failed the Commission sidebar assertion. It
  passed after restoring the Council condition.

- **November 22, 2026 Council page (RES-01/09/11).** The ordinary Council
  entry leads with its role, roster and work. Wide screens show the guide
  beside the roster. The homepage election link opens `#spring-election`
  directly on a phone. Each name with a profile links straight to that
  person’s record. The Clerk link is public, including in gated mode.

  In the initial layout review on `ca449a42` with local changes, Ruby 4.0.9 and isolated PostgreSQL,
  `bin/rails test test/integration/council_election_test.rb test/controllers/committees_controller_test.rb test/controllers/committees_show_gating_test.rb test/controllers/home_controller_test.rb`
  passed 43 tests and 254 assertions with zero skips. Keeping the signature
  reminder after filing closed failed the February assertion. Restoring the
  deadline check passed. Chromium at 320, 390 and 1366 pixels reached all
  three section links and opened the dated Brandt statement with the keyboard.
  On a 390 × 844 phone the Council-work heading began at 2,204 pixels on the
  live page and 643 pixels on the local preview. Both simulated reviewers
  found the roster and work on their return visit. Local topic descriptions
  exercised the fallback for missing briefing headlines.

  The follow-up removed the three header shortcuts and replaced the election
  disclosures with direct profile links. On the same local revision, the
  command above plus `test/integration/campaign_platform_test.rb` passed
  48 tests and 332 assertions with zero skips. A test-only view that sent
  Shannon Derby’s link to another member failed the profile URL assertion.
  Chromium checked all three destinations against the roster at 390 and 1366
  pixels and followed links to Brandt and Bittner. The phone check started
  from the homepage election link. `bin/rubocop` passed.

- **Spring election (RES-01/09/10/11).** During the published guide’s dates,
  Home → City Council opens the election first. Term sources and candidacy
  sources are recorded separately in the [election guide](../../config/council_election.yml).
  Each edition has a fixed timeline and three sourced seat holders. Home,
  Council and member pages select the next edition one week after the first
  Tuesday in April, using the local calendar date. The schedule contains the
  elections through spring 2029. Add a sourced edition for later terms.
  A reader can open a member’s profile to see dated campaign
  statements, qualifications, linked actions, and sources.
  A withdrawn or misattributed statement link gives an unavailable message.
  Gated visitors can reach the Clerk’s public election information.

  On November 22, the local suite above plus the platform and member-gating
  tests passed 51 tests and 402 assertions with zero skips on `ca449a42` with
  working changes. A test-only one-day delay still showed 2027 on April 13
  and failed the homepage assertion. Restoring the seven-day cutoff passed.
  With a simulated Central clock, 390px Chromium displayed the three expected
  member links and filing and election dates for each of the three editions.

- **November 21, 2026 local verification.** Patch on `97cf231d`, Ruby 4.0.9,
  PostgreSQL 18.6. With `RAILS_ENV=test`, a separate local database and
  `PARALLEL_WORKERS=1`, the following command passed 66 tests and 455
  assertions with zero skips. Redirecting a statement link to a missing
  statement failed the selected-position assertion. Bypassing the committee
  access check exposed the term source and failed the gated-response assertion.
  Both changes were restored. `bin/rubocop` passed (882 files).

  ```sh
  bin/rails test test/integration/{council_election,campaign_action_matching,member_profile_layout}_test.rb \
    test/controllers/{committees_controller,home_controller,members_show_gating,committees_show_gating,home_gating}_test.rb
  ```

  A 390px Chromium preview read the existing local cohort data with a read-only
  database connection. The three seat names were visible together. Each person’s
  link opened their own 2024 position. The Hamilton redevelopment example
  led through supporting details to the September 21 meeting and its minutes
  link. Confirmed-candidate behavior was exercised with synthetic records.

- **Start / data:** active/dormant committees, council/nonprofit/independent groups,
  sourced and attendance-derived memberships; staff/non-voting and ended memberships.
- **Action:** Committees → body → roster official or recent topic.
- **Required state / visible outcome:** clear governance/context; current public
  roster uses authority precedence and meaningful office titles, not guest attendance
  as membership. An empty roster is incomplete evidence, not proof of no officials.
- **Next:** official page matches person; activity link goes to the approved topic;
  historical membership stays distinct from a current office.
- **Failures to distinguish:** missing canonical coverage, changed names/aliases,
  withdrawn source, manual override, stale office. Owner decision October 11
  (#172) withholds the entire roster for gated anonymous readers; allowed
  readers retain the current roster.
- **Observed:** [CommitteeDirectory](../../app/services/resident_content/committee_directory.rb),
  [committee controller](../../app/controllers/committees_controller.rb),
  [CanonicalRosters](../../app/services/canonical_rosters/synchronizer.rb).

## RES-10 — Inspect an official's attendance and voting record (P1)

- **Election profiles (RES-09/10/11, November 22, 2026).** The guide opens a
  saved overview with the spring term end, official contact and election dates.
  The first screen leads with the saved story. Its sentence-level sources open
  together. A thin meter and count lead to one list grouped by outcome.
  Opening a promise shows its finding, reason and supporting records. The
  original campaign words and their sources open immediately below. Votes,
  committee memberships, Council attendance and the full record share a
  panel, collapsed on phones and open on desktop. Vote lookup returns
  paginated decisions, member ballots, results and minutes without rebuilding
  attendance, peer comparisons or staff recommendations.
  Meeting and topic roll calls carry the specific member decision into the profile.
  A direct minutes link uses a resolved retained passage when available or the
  unambiguous whole minutes for an older vote. The campaign and issue archives
  load separately. The first page shows a brief campaign excerpt until the
  first usable summary is saved. The [election guidance](../ELECTION_FEATURES.md)
  defines coverage and tone. The [weekly job checks](../../test/integration/council_term_summary_test.rb)
  cover the persisted summary, spending, thin evidence, thresholds, sources and gated access.
  The November 22 development run used the three actual members and retained three provider responses. Revalidating those responses against the reviewed positions required no additional request. One of Derby’s sentences cited an excluded remark and was replaced with the sourced opening from her existing platform.
  A development HTTP check compared all three campaign lists with the original review, checked their vote searches and sampled their excluded statement URLs. The pages retained 11, 10 and 10 positions and omitted 30, 19 and 26 unselected source statements respectively. Chromium opened the count on each profile at 390 pixels. An unchanged Tuesday check across all three issued zero additional requests.
  The subsequent [meeting-record audit](council-promise-record-audit-2026-11-22.md) checked 22 unresolved findings and corrected two housing assessments. The profile now shows each assessment, explanation and citations directly in the page. Evidence search and weekly eligibility apply to sitting members beyond the current election guide.
  On the November 22 development checkout (`e0fb82a7` plus profile changes), Chromium
  opened the three members from the roster at 390 × 844 and 1280 × 900. At 320,
  390 and 1280 pixels the profiles fit without horizontal overflow. All 30
  findings, reasons, quotes, source documents and nine overview sentences matched
  the saved reports. The [minutes page directions](../../config/council_profile_minutes_locations.yml)
  use the exact PDF and finding or agenda item. Bittner’s September Hamilton
  resolutions occupy pages 2–3, Brandt’s water main award page 5, and Derby’s
  Paddlers Park contract pages 3–4. A browser followed the Paddlers Park
  search result through to the original PDF. Development has the real votes
  and documents but no meeting summaries in this data set. The integration
  journey exercised the meeting roll-call link, and the real-data check opened
  Derby’s decision URL directly.
  In the first design pass, across five phone runs per version, the median from opening search to the
  visible Paddlers Park result was 1.78 s before and 0.43 s after. The actual
  profile and full lookup were exercised with automated input and scrolling.
  The earlier short Bittner and Brandt finding paths gained 0.10 s and 0.05 s
  respectively using the index, while Derby’s park finding fell from six
  scroll steps to one. The separate public before run took 5.98 s for the vote
  lookup. These measurements exclude human reading time.
  Loading the full record inside the focused search in an isolated test made
  the query-boundary assertion fail with three unrelated queries. The restored
  [term-summary tests](../../test/integration/council_term_summary_test.rb)
  cover that boundary, the decision link, gated access and weekly spending.
  The subsequent story-first revision retained the 30 findings with their
  reasons, quotes and source links, and the nine saved sentences with their
  original citations. Comparing the profile with the full council record
  confirmed all four current committees for each member and their attendance,
  including meetings with no recorded status. At 390 pixels each profile
  initially showed two links in the article. Each selected finding and its
  minutes were readable after two disclosures. In five phone runs the median
  from roster click to finding was 0.39 s for Bittner and 0.40 s for both
  Brandt and Derby. Opening vote search through the Paddlers Park result took
  0.37 s. Direct finding and search fragments opened the right disclosures
  on both phone and desktop. A test-only change that opened
  the full promise list on arrival failed the closed-list assertion.

- **Scan the promise verdicts (RES-10/11, BG-08, November 22, 2026).** Each heading gives its count, verdict and point value on a red, amber or green band. “Unfulfilled in the public record” earns zero and counts in the denominator. The three featured votes show the motion, disposition, split and date in text. Chromium checked the actual three profiles at 320, 390 and 1280 pixels, including all 30 findings, the unchanged score arithmetic, heading text contrast and visible vote results. Frank and Dana’s simulated phone reviews distinguished zero credit from the rental reversal and identified a possible ambiguity about grant funding. The compact vote line now names the grant application beside the 6–2 result. The [Tuesday refresh integration](../../test/integration/council_term_summary_test.rb) exercises the new wording on a saved assessment after a simulated provider response. Temporarily restoring the old neutral label failed that assertion. No provider request is needed to apply these display rules to published findings.

- **Credit for a specific campaign position (RES-10/11, BG-08, November 22, 2026).** Brandt offered a rental lottery and part-year owner residency as alternatives. His January market argument and his April 9–0 motion permitting rentals in R-1 now appear with the zero-credit finding. A 390-pixel deep link exposes the status, point value, recording timestamp and minutes page. The [regression](../../test/integration/council_term_summary_test.rb) reproduced positive credit from a named motion in a reviewed miss and a cached credit contradicting the same cited finding. Dated reviews now supply the verdict until a later, directly matched personal action or an updated source review changes the evidence. Unmatched votes remain available for the in-office story. A development replay checked every recorded classification across the 30 positions. Counts were Bittner 4/11, Brandt 5/9 and Derby 4/10. A separate test accepts a subsequent directly matched lottery vote. Neither verification used paid generation.

- **Direction of a promise (RES-10/11, BG-08, November 22, 2026).** The [30-position source review](council-promise-record-audit-2026-11-22.md) found one supported deduction. Brandt’s five results and one reversal give him four points across nine positions (44%). Bittner has four across eleven (36%) and Derby four across ten (40%). A 390-pixel Chromium journey opened the red −1 from the roster, read the finding, and checked the hearing timestamp and minutes. Frank and Dana independently explained the arithmetic in simulated mobile reviews. The featured vote now opens the individual decision, including the 9–0 motion to table the October 5 ordinance. Derby’s Paddlers Park search opens the 9–0 award with the minutes at page 3. Across four phone runs after warm-up, the median times from the roster click to the same findings changed from 349 to 325 ms for Bittner, 345 to 322 ms for Brandt and 348 to 334 ms for Derby. Search to the park decision took 375 ms before and 374 ms after the scoring revision. These measurements include automated interaction and paint, and exclude human reading time.
- **Checking mixed evidence (BG-08).** The [weekly assessment tests](../../test/integration/council_term_summary_test.rb) exercise a previously credited position with a newly matched opposing decision, a subsequent decision supporting a previously negative finding, and a work-session objection. The [comparison tests](../../test/integration/campaign_action_matching_test.rb) trace a yes and a no on the same repeal through stored matching and the weekly evidence. A test-only reversion to counting positive results alone produced 56% instead of the expected 44%. After restoring the deduction, all 46 focused tests passed with 636 assertions and no skips. A development replay of all 30 classifications matched the source review, including the two April 6 Brandt awards whose original saved matches predated direction checks. The integration tests used simulated provider responses. The Tuesday schedule and spending limits retain their existing settings.
- **Reading a whole term without expanding a control (RES-10/11, November 22, 2026).** On the development checkout at `e0fb82a7` plus profile changes, the three profiles print the campaign and in-office passages, name missed opportunities, and show each promise and its outcome. The roll call appears at the corresponding promise. On 320-, 390- and 1280-pixel Chromium views, scrolling exposed all 30 findings across the three members. The nine approved narrative passages, original findings, campaign wording and source URLs matched the saved records. Direct finding links opened their evidence, and the phone vote search returned Derby’s 9–0 contract award with the minutes at page 3. The [integration regression](../../test/integration/council_term_summary_test.rb) failed when a test-only response omitted the second visible passage while keeping the sources available.
- **Reading a promise and checking a vote (RES-10/11, November 22, 2026).** The previous profile layout led with one campaign promise and a dated Council vote. The Violet Inn agreement passed 8–0, the Neshotah grant application passed 6–2, and the Paddlers Park contract passed 9–0. The vote links to its original numbered finding. The four outcome groups on these profiles show counts and open independently of the full term story. Phone and desktop journeys checked each highlighted finding, its minutes, the two pace bars and the Paddlers Park search. The integration test binds the illustration to the credited finding, reviewed text and sources. Across four timed phone runs after warm-up, the median roster-to-featured-finding times changed from 0.34 to 0.31 seconds for Bittner, 0.34 to 0.32 for Brandt and 0.35 to 0.30 for Derby. The Paddlers Park search took 0.37 seconds before this visual revision and 0.38 afterward. The earlier full-record lookup took 1.78 seconds. A test-only wrong outcome count failed its assertion, then passed again without the fault.
- **Term pace and promise findings (RES-10/11, BG-08, November 22, 2026).** The member profile compares the earned share with the elapsed share of the scheduled term. The three April 2024 seat holders had 149 days left and 86% elapsed on November 22. The results were Bittner 4/11, Brandt 5/9 and Derby 4/10. The original Derby minutes document the rental ordinance, Sandy Bay stormwater funding, individual business financing decisions and the Paddlers Park award. The revised classifications distinguish two missed opportunities, a housing vote without a confirmed affordability result, and three evidence gaps for her remaining six positions. The September library source still accompanies the more specific overview sentence. The source review and [election scoring rules](../ELECTION_FEATURES.md) explain the distinction between a missed opportunity and an incomplete record. The [integration tests](../../test/integration/council_term_summary_test.rb) exercise early and late pace, attempted and lost votes, missing evidence and corrected historical findings.
  On `e0fb82a7` plus development changes, Chromium opened all three profiles from the roster at 320, 390 and 1280 pixels. Derby’s housing finding linked to the 6–3 roll call on page 4. The next-Tuesday replay reused all three saved profiles without a new request. The focused Rails suite passed 45 tests and 725 assertions. A test-only constant green rating failed the expected amber assertion, then passed with the calendar calculation restored. RuboCop passed.

- **November 21 campaign consolidation (BG-08 → RES-09/10/11).** The election
  guide and member sidebar use the same positions for each election. The
  [2024 source review](../../config/campaign_platform_2024.yml) groups repeated
  proposals before looking at council activity. Sources without current review
  keep their original issue or statement display. Qualifying new extractions
  can supply comparison headings during normal intake. The original interviews remain available at their sources. The site displays
  statements behind the retained positions.
- On the local preview based on `97cf231d`, a 1440 × 1000 desktop browser
  followed the citywide race to all three profiles. Bittner’s committee appeared
  once with both forums. Brandt’s two rental alternatives were distinct, and
  his annual pipe priority showed his existing attributed contract motion and
  its minutes. Derby’s housing entry showed one financing vote. The three
  source disclosures contained 49, 32 and 42 accepted statements respectively.
  The [HTTP regressions](../../test/integration/campaign_platform_test.rb) exercise
  separate campaign sources, an archive-only statement, gated access, and
  correction of the minutes and campaign source. A test-only change grouping
  by individual statement produced two rows where one was required. Restoring
  consolidation returned the check to green. Future provider wording was
  simulated in the intake test.

- Before the corrections below, with local records from April 16, 2025 through November 21, 2026, the
  read-only comparison preview reused 33 saved decisions about relevance and
  identified nine new comparisons across four batches. Two older batches had
  reached their retry limit. One meeting lacked usable minutes in this snapshot.
  The three profile requests showed 11, 10 and 10 positions respectively.
  Brandt’s water-main motion remained visible and the rental-fee votes stayed
  off both rental proposals. The [job-to-profile tests](../../test/integration/campaign_platform_test.rb)
  run the normal jobs with simulated provider responses and check the saved
  evidence on a later member-page request. Temporarily grouping by individual
  campaign statement produced four comparisons for two decisions and failed
  the repeated-position test. Restoring grouping by position passed.

- The local profiles show directly cited council minutes and staff reports under
  the position they address. Bittner’s recruitment record shows his Violet Inn
  motion. The two motel improvement votes still appear under Brandt’s broader
  position on city financing. The park contract, subdivision paving and rental
  licensing ordinance identify the member’s role. The Coenen purchase, concerns
  about city notices and loss of housing tax credits are reported separately
  from individual votes. The dated citations include records from the first
  year of the term. The full first year has yet to be imported.

- **Saved motion reuse:** substantive attributed motions in published minutes
  recaps reach compact recorded-action cards with the agenda subject and exact
  source passage. They enter the existing cached campaign comparison path, not
  an automatic topic-overlap match. See
  [saved-motion checks](council-saved-motion-actions-2026-11-08.md).

- **November 8 direct evidence matching:** specific campaign positions can show
  matched recorded work and separately labeled issue updates, including an
  unsuccessful proposal with no vote. Topic overlap alone cannot publish the
  connection. All-records issue history includes documented terms and excludes
  service gaps. See [matching evidence](campaign-issue-evidence-2026-11-08.md).
- **November 8 formal cases:** verified case records supply dated events in a
  closed section, with independently opened source passages. Complaints,
  dispositions and appeals remain distinct; missing records are incomplete
  coverage. Documented service and known identity control inclusion, including
  a post-term disposition about earlier service. See
  [formal-record evidence](council-formal-records-2026-11-08.md).
- **November 8 work beyond votes:** shared official evidence can show attributed
  proposals/requests even without a vote or prior campaign/topic record. Known
  identity and service dates control the projection; short actions and closed
  sources remain separate from issue outcomes and campaign matching. See
  [recorded-action evidence](council-recorded-actions-2026-11-08.md).
- **November 8 vote search:** search and approved-topic/body/type/divided filters
  apply before pagination in both recorded and featured views. Controls preserve
  service period and view through search, paging, source navigation and clearing,
  with no AI. See [filter evidence](member-vote-filters-2026-11-08.md).
- **November 8 saved-analysis reuse:** published minutes agenda summaries now
  supply shared issue history through existing topic links and citations, with
  no new extraction stage or AI request. Retained supplemental evidence takes
  precedence for the same agenda item; generic summaries are not automatic
  campaign matches. See [reuse checks](council-saved-history-2026-11-08.md).
- **November 8 shared issue updates:** selected official minutes can supply a
  short project/policy update to every relevant profile without another vote.
  Source/report dates, conditions and body remain separate from member credit
  and campaign alignment. Reads use current saved evidence only; details are
  independent disclosures. See [issue-update evidence](council-issue-updates-2026-11-08.md).
- **November 8 peer votes:** selected terms offer a closed alphabetical comparison
  table with inspectable shared yes/no fractions and a separate divided subset.
  The detail route preserves the term through pagination and source navigation,
  shows exclusions and keeps official outcomes separate. Corrected facts recalculate
  on subsequent reads without AI. See [peer-vote evidence](council-peer-votes-2026-11-08.md).
- **November 8 period selection:** the Council record selector defaults to the
  latest usable evidenced service period, scopes attendance and votes to its
  eligible Council inventory, and preserves the period through view switches
  and pagination. All available records keeps the broader recorded history;
  current roles remain labeled when viewing an earlier period. See
  [period-selection evidence](council-period-selection-2026-11-08.md).
- **Start / data:** civic Member with current office/memberships, attendance and
  linked/unlinked substantive/procedural motions; an official with no record.
- **Action:** roster name → official → voting topic/meeting; disclose Other Votes.
- **November 8 layout adjustment:** the primary record precedes campaign context
  in document/phone order; campaign context sits in a secondary column on desktop.
  Jump links retain easy access to both. Other Votes starts closed but its saved
  decisions and links remain server-rendered for permitted readers, including
  verified Google requests. See [layout checks](member-record-layout-2026-11-08.md).
  The subsequent issue sidebar shows every issue heading per election, with
  only the first position open. Citations/full statements appear once at the
  bottom. Opening one issue or statement does not close another; topic scores
  and vote history do not hide issue headings. The owner rejected automatic
  topic-based vote pairs as misleading, so the campaign section no longer renders
  them. Votes remain in the main record. The subsequent bounded direct-comparison
  slice adds only supported specific statement/decision links, preserving the
  member vote and Council result separately; it does not grade promises or
  infer inaction. See [matching checks](campaign-action-matching-2026-11-08.md).
  A matched issue opens with one position and at most two compact decision rows;
  explanations and full source passages stay behind Supporting details. Other
  matched positions remain available in a closed disclosure, without generating
  new summaries for presentation.
  Reads use existing analysis with no new AI. See the
  [issue sidebar checks](member-issue-sidebar-2026-11-08.md).
- **November 8 recorded-vote view:** switch from Featured votes to All recorded
  votes (`?votes=all`), paginate 25 saved decisions at a time in either view, and
  follow a motion to its meeting and sources. Featured omits procedural motions
  only when passed with all recorded non-absent votes affirmative; All recorded
  votes keeps them. Both views retain motion descriptions and use accurate
  recorded-vote labels without a leading disclaimer. A numbered pager appears
  only below the list, with the current page identified. No new
  term denominator or campaign comparison is implied. See
  [acceptance and evidence](member-recorded-votes-2026-11-08.md).
- **October 24 navigation experiment:** an already visible voter name in a
  meeting roll call or topic Key Decisions section also leads to the stored
  member profile. The profile's existing topic/meeting links complete the
  return journey; access still follows RES-11. See
  [acceptance and evidence](member-navigation-2026-10-24.md).
- **Required state / visible outcome:** public identities and meeting-specific
  evidence; appropriate attendance comparison; voting record avoids unsupported
  inferences and remains distinct from website account data.
- **Next:** links recover source meeting/context; no votes is not a claim of abstention
  or perfect attendance. Gated audience cannot obtain withheld vote content.
- **Failures to distinguish:** identity alias error, membership-window mismatch,
  absent record versus absence, cancellation, procedural grouping, inactive office.
- **Observed:** [OfficialProfile](../../app/services/resident_content/official_profile.rb),
  [MembersController](../../app/controllers/members_controller.rb),
  [member show](../../app/views/members/show.html.erb).
- **October 24 metadata review:** title/description identify the current office,
  or the first displayed current committee and its existing role label.
  Subsequent requests drop ended roles. No roster links or voting access were
  added; see [evidence](seo-review-2026-10-24.md).
- **November 7 identity reconstruction:** compatible person merge → source-name
  alias → cached minutes reconstruction preserves the surviving person's current
  votes and attendance, original retained attribution, decision review and topic
  evidence. Fresh authorized member reads are checked; no public route or access
  change. See [scope and limits](council-member-merges-2026-11-07.md).
- **November 7 corrected fact propagation:** a corrected extracted vote reaches
  the same member record while known stale meeting prose is withdrawn. See
  [later member and meeting reads](meeting-summary-facts-2026-11-07.md).
- **November 8 campaign records:** accepted statements from the current supplied
  source version appear on the existing member page, grouped by election, with
  conditions, timing, original question and publisher link. Unresolved identities
  or passages do not publish; no candidate creates a new civic person or office.
  Reads and unchanged publication call no AI. RES-11 applies to the entire
  generated section. See [real-data and regression checks](member-campaign-records-2026-11-08.md).

- **November 8 related issue records (superseded display):** the earlier slice
  exposed eligible topic votes beneath statements. Owner review found that this
  implied a connection the matching had not established. Those automatic pairs
  are now omitted from campaign content; the main vote record remains available.
  Eligibility/query coverage is retained separately. Historical evidence remains
  in [the earlier report](member-campaign-activity-2026-11-08.md).

- **November 8 explicit recommendations:** a closed member section links each
  recommending source's all/divided fraction to included decisions and exclusions.
  Same-proposal semantics, known pre-decision timing and actual service dates bound
  comparison; no unified staff position is inferred. Details and evidence are in
  [the verification record](council-staff-recommendations-2026-11-08.md).

## RES-11 — Cross an access-mode or audience boundary (P0)

- **Start / data:** distinctive allowed/withheld content, more than two topics,
  known identities, both modes, eligible/anonymous/stale-session/crawler audiences.
- **Action:** browse all reporting surfaces; admin changes open→gated→open; repeat
  normal, HEAD, search/page, Turbo-stream/format and cached requests.
- **Required state / visible outcome:** pages stay reachable; full content appears
  only for the allowed audience. Withheld content/identity cannot appear in DOM,
  attributes, metadata, share payload, inline JSON, alternate format or result shape.
- **Next:** prior full responses cannot reappear for a newly anonymous/gated
  audience. Crawler permission does not unlock Account/Admin or authenticate API.
- **Failures to detect:** spoofed crawler identity/IP/proxy, expired feed, stale
  cache/conditional response, rotating topic cap, hidden-text search oracle.
- **Observed:** [SiteAccess](../../app/controllers/concerns/site_access.rb),
  [access helpers](../../app/helpers/access_helper.rb),
  [crawler verifier](../../app/services/crawlers/verifier.rb),
  [mode update](../../app/controllers/admin/site_settings_controller.rb).

## RES-12 — Understand the site and discover available pages (P2)

- **Start / data:** public About/static discovery files; sitemap with approved,
  blocked, duplicate, dissolved and private resources.
- **Action:** About → source/access links; fetch robots/llms/sitemap; optionally
  follow a deliberately created diagnostic probe or development OG preview.
- **Required state / visible outcome:** honest site/access guidance; sitemap respects
  audience and canonical identity. No account/admin/catalog leakage into static guidance.
- **Next:** links lead to the documented front doors; probe expires and contains
  only synthetic diagnostics; Explore promises no presently implemented research controls.
- **Failures to distinguish:** obsolete access copy, cached full catalog, missing
  page, expired probe, unsupported format, development-only route expected in production.
- **Observed:** [PagesController](../../app/controllers/pages_controller.rb),
  [SitemapsController](../../app/controllers/sitemaps_controller.rb),
  [static cache middleware](../../lib/middleware/discovery_file_caching.rb),
  [probe controller](../../app/controllers/crawler_probes_controller.rb),
  [Explore placeholder](../../app/views/topics/explore.html.erb). Probe lifecycle is BG-07.
- **Reviewed contract:** approved accounts and simple topic/meeting search are
  supported by later auth/API requirements. Explore's research/filter interface
  remains unfinished in [#62](https://github.com/AndreRobitaille/TwoRiversReporter/issues/62);
  a placeholder response is not a completed research journey.

## RES-13 — Research resident content through the API (P1)

- **Start / data:** valid saved key from AUTH-13; approved topics/canonical meetings,
  narratives, sources, committees and civic officials with distinctive hidden internal fields.
- **Action:** authenticate GET `/api`; search meetings and topics; follow handbook
  URLs into detail, appearances/decisions, agenda/documents and official votes; exhaust pages.
- **Required state / visible outcome:** resident JSON in both modes, fixed read-only
  scope, explicit source/AI/illustration labels, no internal prompts/accounts/credentials.
  Searches consider resident narrative/source fields, not internal generation fields.
  `/api/v1/home` uses the same 21-day lead and 30-day More Stories windows as RES-01.
- **Next:** inspect original sources; follow `links.next`; GET/HEAD only. An admin
  key cannot write/run jobs/open admin, and browser cookie alone yields 401.
- **Failures to distinguish:** invalid/revoked/expired key (401), absent/unapproved
  resource/write verb (404), invalid filter (422), owner/IP limits (429 with Retry-After).
- **Observed:** [API base](../../app/controllers/api/base_controller.rb),
  [handbook](../../app/services/api/handbook.rb),
  [serializer](../../app/services/api/v1/serializer.rb),
  [ResidentQueries](../../app/services/api/v1/resident_queries.rb).

## RES-14 — Discover newly available evidence for an old event (P1)

- **November 7 withdrawal freshness:** `updated_since` includes a summary withdrawal
  even when the meeting and its own document did not change; available-analysis
  metadata still excludes withdrawn prose. See [cross-meeting API evidence](agenda-summary-dependencies-2026-11-07.md).

- **Start / data:** historical meeting/topic; newly changed document, recap,
  briefing, alias or appearance; separately unchanged scrape and extraction rerun.
- **Action:** API list with inclusive timezone-qualified `updated_since` and
  `sort=updated`; follow pages and updated resource links.
- **Required state / visible outcome:** old event surfaces by content-update time;
  source and analysis freshness are distinguishable from meeting date/activity.
  Unchanged document fetch does not masquerade as new document content.
- **Next:** preserve timestamp precision; overlap polls/deduplicate IDs and updates.
  Live offset reads do not promise exact replication, deletion history or an event stream.
- **Failures to detect:** child update omitted, precision loss, confusing `from/to`
  meeting dates with update dates, concurrent offset shifts, internal-field-only search match.
- **Observed:** [ContentUpdates](../../app/services/api/v1/content_updates.rb),
  [meeting API](../../app/controllers/api/v1/meetings_controller.rb),
  [topic API](../../app/controllers/api/v1/topics_controller.rb), [API contract](../read-only-api.md).

## RES-15 — Read a complete revision-consistent transcript (P1)

- **Start / data:** readable transcript longer than a chunk, Unicode text and
  a known final phrase; separate missing/replaced/changed transcript.
- **Action:** first API transcript request, append text and follow every `links.next`.
- **Required state / visible outcome:** complete text without skipped/truncated
  ending; continuation pins document ID/checksum; recording remains supplemental,
  never official minutes. Limits/offsets count Unicode characters.
- **Next:** revision change gives 409 and requires restart at zero; continuation
  without revision pins gives 422, absent transcript gives 404.
- **Failures to detect:** mixing revisions, bytes-versus-characters mismatch,
  duplicate/missing chunks, missing last chunk, invented transcript page/timestamp.
- **Observed:** [MeetingsController#transcript](../../app/controllers/api/v1/meetings_controller.rb),
  [API transcript contract](../read-only-api.md). Compare source→all chunks→assembled
  text count and distinctive ending, not just first-request status.
