# Campaign issue sidebar — November 8, 2026

Scope: RES-10 and its RES-11 access boundary. The owner's selected issue-based
mockup in [the development plan](../DEVELOPMENT_PLAN.md) replaces the statement
list as the initial view when approved topic links exist. This is a bounded
reading improvement, not a promise-fulfillment assessment or new legal analysis.

## Reader contract

- Three issue rows appear per election; the first is open. Other issues and
  full statement/source records start closed. Native disclosures require no
  JavaScript or additional requests.
- The open issue separates a saved position, up to two recent related Council
  votes, and those motions' Council result. Qualifications and deadlines remain
  beside the position. A passed motion does not mean a project is complete.
- The label Related Council votes describes shared topic context. In the real
  utility example, adding water customers and adopting a sewer-charge ordinance
  are related context, not evidence of implementing the campaign proposal.
- A generic adoption includes the saved agenda subject; a postponement retains
  its actual motion. Long expanded titles are marked excerpts. The full subject,
  motion, tally, date and source meeting remain in Statements and decisions.
- Distinct source statements are retained. Only navigation rows with identical
  statement and vote identities combine. Repeated mentions do not raise an
  issue's priority: issues with votes appear first, then existing topic impact.
- One saved position leads each issue, preferring written sources, fewer topic
  associations and chronological source order. Retrospective claims stay in the
  full archive. This is not a semantic merge of different positions.
- Readers without approved topic links retain the statement-list fallback.
  Permitted residents and verified crawlers receive saved evidence in the HTML;
  a spoofed crawler remains gated. There are no new AI calls, jobs or schedules.

## Local checks

Environment: `codex/member-issue-sidebar`, base `961bee18969cb05540a7f48d86a6fd6d720534dd`
with this patch applied; Ruby 4.0.9, PostgreSQL, Chromium. Separate automated test
database, deterministic provider responses. Commands actually run:

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
bin/rubocop
```

Results: **38 application tests / 420 assertions** and **5 browser journeys /
155 assertions**, no failures, errors or skips; **780 Ruby files**, no offenses.
The first browser attempt used a mismatched installed Chrome/driver and ran zero
assertions; selecting the existing Chromium binary resolved the environment
error without changing the application or assertions.

The browser journey verifies desktop column proportions, phone ordering, first
issue expansion, two visible actions, closed evidence, disclosure of every
decision, exact motion wording, meeting navigation, back/refresh and no overflow.
HTTP tests exercise actual deterministic extraction/matching/publication for
repeated qualified statements and prove all distinct sources survive grouping.
Allowed content is established before verified-crawler/spoof checks. Repeated
reads raise immediately if they try to construct an AI provider.

## Defect detection

With the passing postponement test, an isolated helper fault replaced the actual
motion with its agenda title. The intended visible-action assertion failed; the
restored file passed. This protects against labeling a successful postponement
as approval of the proposal.

The utility subject test failed against the old generic-adoption display. An
additional rendered-text assertion exposed double-escaped quote entities in
title excerpts; using plain-string truncation fixed it while leaving ordinary
ERB escaping intact. The full focused suite passed after restoration/correction.

Automatic review of `d0debdb` found that a recorded recusal was mislabeled as
missing in the compact action. An HTTP regression first failed with Vote not
recorded, then passed after adding the explicit Recused label. The expanded
record already retained the recusal. The full focused application suite and
RuboCop passed again after this one-line display correction.

## Real-data verification and limits

The combined local preview uses the existing civic-data copy and saved forum
pilot outputs. All current accepted summaries survive into member HTML:
Bittner 34 (31 forum), Brandt 27 (25 forum), Derby 33 (31 forum). Repeated unchanged
extraction/matching jobs and all three HTTP reads left requests, reservations,
votes, people and office records unchanged and made zero provider calls.
Phone browser views of all three profiles retained their issue navigation and
statement counts without horizontal overflow. The current Bittner phone
capture was visually inspected. Existing local history gaps remain.

Three simulated resident reviewers independently checked the live phone sidebar,
then only the corrected utility relationship and shortened Hamilton wording.
They distinguished related utility context from fulfillment, and motion results
from project completion. They considered the shorter Hamilton excerpts adequate
for this display slice and independently noticed the quotation-entity defect,
which was subsequently fixed and verified. These are simulated opinions, not
human usability testing or source certification. The owner review remains open.

No additional paid analysis, production data copy, backfill, merge or deployment
was performed for this UI slice. It does not independently certify every forum
interpretation, explain the legal effects of resolutions, or establish live
Google indexing/AI answer inclusion. Full legal/planning explanations would need
supported shared evidence; this view does not invent them from titles.
