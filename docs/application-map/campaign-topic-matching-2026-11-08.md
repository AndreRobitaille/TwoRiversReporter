# Shared campaign issue matching: November 8, 2026

This is a bounded BG-08/ADM-21 extension under #239/#240 and parent #234,
stacked on the campaign cost-preflight work. It supplies topic associations for
accepted campaign statements; it does not complete the public priority/action/
outcome comparison or claim that a particular vote kept a promise.

## Contract and implementation

The [campaign evidence contract](../superpowers/specs/2026-11-07-council-accountability-design.md#campaign-collection-and-forum-attribution)
requires shared processing and preserved source context. The
[first-slice acceptance](../superpowers/specs/2026-11-07-council-accountability-design.md#github-tracking-and-release-sequence)
requires distinct statements, actions and outcomes, unchanged-input reuse and
explicit gaps. The owner's subsequent direction prioritizes real local data
and correctable watchdog reporting over speculative infrastructure.

After statement publication, `MatchCampaignTopicsJob` prepares one matching
stage for the source version. It supplies saved statements for all participants
and the approved reusable topic catalog, without extracting the article again.
The response must contain every input sequence exactly once, with a matched,
unmatched or unresolved result. Unknown IDs and incomplete responses are held.
Code checks completeness, IDs, accepted member identity and spending admission;
semantic matching remains a model task, not something these checks prove.

The stage reuses the existing two-attempt limit, exact-request allowance,
reservation and receipt. Missing allowance pauses before provider construction.
A statement-extraction allowance cannot authorize a different matching request.
Unchanged reruns and metadata-only corrections with identical prepared input
reuse saved results. Empty candidate catalogs complete without AI. The existing
nightly process recovers missing/pending work and republishes completed results;
held stages do not automatically retry. No schedule is added.

Accepted member statements receive topic associations. Unresolved identities
retain their matching results without creating people or publishing links.
Member/topic merges preserve published associations; blocking a topic removes
it from the projection. Original returned IDs remain in immutable matching data.
The private source page displays each reason and a separate offline cost
estimate. Public campaign cards retain their existing behavior.

The initial catalog is pinned. Adding unrelated topics does not trigger paid
rewrites. Deliberate rematching against newly available topic evidence and
specific action/outcome comparisons remain subsequent work.

## Real-data acceptance

An isolated local database used the existing civic-only snapshot and retained
March 27, 2024 HTR article extraction: 11 statements, seven accepted statements
for Bittner/Brandt/Derby, and four unresolved identities. All 230 approved reusable
topics were supplied. No additional production copy or historical backfill ran.

An independently checked response replaced only OpenAI transport. All 11
sequences survived. Six reference rows related to housing, Hamilton or short-term
rentals; four published associations covered the three current members, while
the two matching rows for unknown people remained unpublished. One source-wide
request served every candidate. Repeating the job and nightly recovery made no
new request, queued no work and preserved association timestamps. All 2,157
existing votes, including the cohort's 628 votes, and original statement records
were unchanged. Public pages retained their real 3/2/2 campaign cards.

The reference deliberately distinguishes these claims:

- The owner confirmed that Bittner's 17-acre riverfront reference means Hamilton.
  That clarification supplies the identity check; the article does not name the
  property. The later [September 21 minutes](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Minutes-f79e6ec229024a6e8164140ca117f10f.pdf)
  describe roughly 12 acres and explicitly distinguish a guiding vision from a
  development plan or expenditure approval.
- Derby's Airbnb concern relates to the short-term-rental topic. Its
  [April 20 RV/camper room-tax vote](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Minutes-8b3551cf06b040c9a7496d60a1448ba1.pdf)
  does not by itself establish follow-through on Airbnb regulation.
- Supporting the city-manager form of government does not establish support for
  a particular manager; that association remains unresolved in the reference.

These checks exercise real civic input, persistence and HTTP/browser reads with
deterministic responses. They do not measure paid-provider accuracy. The Hamilton
clarification is part of the checked reference, not evidence that an automated
provider would infer it from the article alone. The full article, private source
copy and local operator session are not committed.

## Execution evidence and remaining limits

Initial application revision: `ec283d87`, based on `af99755e` (PR #277); the
subsequent review correction is recorded below. Local execution
uses Ruby 4.0.9, PostgreSQL and separate regression/real-data
databases. No fixture loader runs against the real-data acceptance database.
Only the operator identity and provider/budget transport are synthetic there.

- Focused integration/job/prompt/topic-merge tests initially passed: 32 tests,
  337 assertions, no failures, errors or skips.
- Real-data runner passed the input/output/count/identity/repeat and HTTP checks
  above, with one deterministic matching response and zero paid calls.
- Chromium at 390 by 844 displayed all 11 rows without horizontal overflow;
  the Hamilton control opened the real topic and its retained decisions.
  Back navigation and refresh retained all 11 matching rows.
  Browser authentication used an isolated local operator session; it was not a
  new verification of email delivery or sign-in.

- `PARALLEL_WORKERS=1 bin/rails test`: 2,481 tests, 16,952 assertions, zero
  failures/errors and one existing `PromptRunTest` skip for a missing meeting
  fixture. This ran before the final merged-topic admin-link adjustment.
- After that adjustment, `bin/rails test test/integration/campaign_topic_matching_test.rb test/services/topics/merge_service_test.rb test/views/admin_view_hygiene_test.rb`:
  17 tests, 104 assertions, zero failures/errors/skips. The merge test checks
  the surviving admin destination and subsequent blocking, as well as saved links.
- `CHROME_BIN=/usr/bin/chromium bin/rails test test/system/campaign_extraction_journeys_test.rb test/system/member_campaign_journeys_test.rb`:
  four browser tests, 119 assertions, zero failures/errors/skips.
- `bin/rubocop`: 762 files, no offenses. The migration ran only locally;
  `bin/rubocop -A db/schema.rb` ran and the schema diff contains the intended
  stage discriminator/context, replacement uniqueness index and join table.
- Representative defect: the shared publication test passed with one test/18
  assertions. A process-local parser fault retained only the first returned
  match; the expected association count failed (expected three, actual one).
  Removing the fault restored one test/18 assertions to green. No application
  source mutation remains. This proves detection of lost cross-member matches,
  not semantic matching accuracy.

Documentation links/anchors and `git diff --check` passed. Exact-head hosted CI
and automatic review status are recorded on the PR. No deployment, merge, paid
generation, production backfill or automatic public promise rating is included.

### Review correction: merge before publication

Automatic review on `2764e8c4` identified a gap when a topic is merged before
associations exist, including a participant whose identity is repaired later.
Reproduction expected two links to the surviving topic but found zero. Publication
now resolves deleted topic IDs through the existing numeric topic redirect,
checks that the destination remains reusable, and keeps the original ID in the
association. No new redirect or correction infrastructure was introduced.

The regression covers two successive merges followed by publication and later
identity repair through nightly recovery. All three water-topic associations
reach the survivor without another provider call. The final focused command
adds `test/jobs/reconcile_campaign_sources_job_test.rb` to the integration,
topic-merge and view-hygiene command above: 21 tests, 150 assertions, no failures,
errors or skips. RuboCop passed again. The initial hosted CI and runtime-image
checks passed on `2764e8c4`; the PR records final-revision checks separately.
