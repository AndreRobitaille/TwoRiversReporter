# Resident and API workflows

All entries are **documented, runtime unverified**. Use [inventory.md](inventory.md)
for audience/mode variants. Contracts come from the [development plan](../DEVELOPMENT_PLAN.md),
[Topic Governance](../topics/TOPIC_GOVERNANCE.md),
[public access design](../superpowers/specs/2026-07-24-tiered-public-access-design.md),
[crawler policy](../verified-crawler-access.md), [roster design](../superpowers/specs/2026-09-03-canonical-committee-rosters-design.md),
and [resident API contract](../read-only-api.md). Presentation disagreements remain
unsettled in the [verification register](verification-register.md).

## RES-01 — Discover an issue from What's New (P1)

- **Start / data:** approved reusable topics with recent activity and varied
  impact, briefings present/absent, upcoming council events, with/without images.
- **Action:** open homepage; follow Top Story/Wire topic or Next Up meeting.
- **Required state / visible outcome:** intelligible impact/recency-led discovery
  connects to useful topic continuity and upcoming meeting details; labels align
  with timing and allowed audience. Empty selections still allow broader navigation.
- **Next:** destination gives the intended topic/meeting; browser Back returns
  usefully. Candidate acceptance: no duplicate story/wire selection in unchanged data.
- **Failures to distinguish:** no briefing/activity/image, stale timestamp,
  unapproved topic, thin/cancelled meeting, missing record.
- **Observed:** [HomeSelection](../../app/services/resident_content/home_selection.rb),
  [homepage](../../app/views/home/index.html.erb) and partials link all stories/wire
  entries to topics. The approved April 10 homepage design independently requires
  these destinations; older playbook wording was reconciled. Exact empty-zone
  differences remain under V-04; see [reviewed contracts](behavior-contracts.md).

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
- **Unresolved contract:** fixed sections/empty messages in the March 1 meeting
  design differ from conditional/legacy rendering. Existing behavior stays intact
  pending the #171 owner choice; see [behavior contracts](behavior-contracts.md).

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
  source chips are not clickable; that policy conflict needs V-05.

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

- **Start / data:** active/dormant committees, council/nonprofit/independent groups,
  sourced and attendance-derived memberships; staff/non-voting and ended memberships.
- **Action:** Committees → body → roster official or recent topic.
- **Required state / visible outcome:** clear governance/context; current public
  roster uses authority precedence and meaningful office titles, not guest attendance
  as membership. An empty roster is incomplete evidence, not proof of no officials.
- **Next:** official page matches person; activity link goes to the approved topic;
  historical membership stays distinct from a current office.
- **Failures to distinguish:** missing canonical coverage, changed names/aliases,
  withdrawn source, manual override, stale office, gated roster policy V-05.
- **Observed:** [CommitteeDirectory](../../app/services/resident_content/committee_directory.rb),
  [committee controller](../../app/controllers/committees_controller.rb),
  [CanonicalRosters](../../app/services/canonical_rosters/synchronizer.rb).

## RES-10 — Inspect an official's attendance and voting record (P1)

- **Start / data:** civic Member with current office/memberships, attendance and
  linked/unlinked substantive/procedural motions; an official with no record.
- **Action:** roster name → official → voting topic/meeting; disclose Other Votes.
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
- **Next:** inspect original sources; follow `links.next`; GET/HEAD only. An admin
  key cannot write/run jobs/open admin, and browser cookie alone yields 401.
- **Failures to distinguish:** invalid/revoked/expired key (401), absent/unapproved
  resource/write verb (404), invalid filter (422), owner/IP limits (429 with Retry-After).
- **Observed:** [API base](../../app/controllers/api/base_controller.rb),
  [handbook](../../app/services/api/handbook.rb),
  [serializer](../../app/services/api/v1/serializer.rb),
  [ResidentQueries](../../app/services/api/v1/resident_queries.rb).

## RES-14 — Discover newly available evidence for an old event (P1)

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
