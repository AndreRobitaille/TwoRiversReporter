# Campaign source sidebar — November 8, 2026

Scope: RES-10 and its RES-11 access boundary, following the owner's source/sidebar
review in [the development plan](../DEVELOPMENT_PLAN.md). Approved topic links
organize campaign evidence; they do not prove that a Council action addressed a
specific proposal. Direct campaign-to-action comparisons remain unfinished.

## Final reader contract

- Three issue rows appear per election; the first is open. Other issues and
  full sources start closed. Opening another issue or statement never closes
  the reader's existing selection. Native disclosures need no extra request.
- A small white panel with a side rule separates the saved position from
  Campaign sources. It contains a paraphrase, not a fabricated quotation.
  Qualifications and deadlines remain beside the position.
- Campaign sources retains distinct saved statements, their qualifications,
  publisher links and dates. The full statement archive retains questions and
  source context. All permitted content remains server-rendered.
- Follow this issue is removed. Automatic topic-based vote pairings and their
  Council results are omitted from campaign content. Existing votes and meeting
  links remain in the main record. A shared utility topic does not connect an
  added-water-users proposal to a sewer-charge ordinance.
- Navigation reuses approved topic links and existing impact/activity. Repetition
  does not raise priority. Written-source summaries lead when available; distinct
  forum positions remain in the sources. Exact duplicate evidence groups combine
  for navigation only. Retrospective claims stay in the full statement archive.
- Without approved topic links, retain the statement-list fallback. Verified
  crawlers receive the same saved evidence as permitted readers; spoofed crawlers
  remain gated. No generation step, new job or schedule is introduced.

## Verification

Environment: `codex/member-issue-sidebar`, initial base `961bee1`, with the owner
revision following `c4cc052`; Ruby 4.0.9, PostgreSQL, Chromium, a separate regression
DB and deterministic provider responses. Commands actually run:

```sh
bin/rails test test/integration/member_profile_layout_test.rb \
  test/integration/member_campaign_activity_test.rb \
  test/integration/member_campaign_record_test.rb \
  test/integration/member_recorded_votes_test.rb \
  test/controllers/members_controller_test.rb
CHROME_BIN=/usr/bin/chromium bin/rails test \
  test/system/member_campaign_activity_journeys_test.rb \
  test/system/member_campaign_journeys_test.rb \
  test/system/member_recorded_votes_journeys_test.rb
bin/rubocop --cache false
```

**36 application tests / 409 assertions**, **5 browser journeys / 150 assertions**,
all passing without skips; **780 Ruby files**, no offenses. Browser checks cover
independent issue and statement controls, retained open source details, manual
closing, main-record meeting navigation, return/refresh, desktop proportions,
phone ordering, no overflow and no AI on reads. HTTP checks establish allowed
content before the real cached-IP crawler/spoof boundary and preserve every
qualified source through deterministic extraction, matching and publication.
Existing service/date/meeting eligibility assertions remain at the context-query
boundary; they are not assertions that campaign/action comparisons are valid.

For defect detection, the passing unrelated-vote check was subjected to an
isolated partial fault that rendered broad topic votes beneath the position.
It failed at the intended campaign-content assertion while first proving the
vote existed in the main record. Restoring the partial passed **5 tests / 53
assertions**. The fault was never copied into the real-data preview.

Real local article/forum data retained all accepted summaries in member HTML:
Bittner 34 (31 forum), Brandt 27 (25 forum), Derby 33 (31 forum). Repeated unchanged
extraction/matching jobs and reads made zero provider calls and left requests,
reservations, votes, people and office counts unchanged. The revised Bittner
390-pixel view was visually inspected, and opening Utility Rates left Hamilton
open with no sewer vote in either campaign panel. Local history gaps remain.

## Human review and limits

The preceding candidate paired topic votes beneath positions. Simulated resident
reviewers accepted the Related Council votes label, but the owner's own review
still found the utility pairing misleading. That human correction takes precedence:
the final view removes the unsupported relationship instead of further relabeling
it. The previous recusal-label review fix is no longer a runtime path because the
compact vote renderer was removed. Vote values in the main record are unchanged.

This is source organization, not completion of the intended action comparison.
A later comparison must relate a specific statement to specific decision evidence
and reuse that analysis across members. This slice does not certify every forum
interpretation, explain legal effects or establish live Google indexing. No new
paid analysis, production copy, backfill, merge or deployment was performed.
