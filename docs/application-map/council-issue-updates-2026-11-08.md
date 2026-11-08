# Shared official issue updates — November 8, 2026

Scope: new BG-09 → RES-10/11, advancing #243 and #240 under #234. This is a
bounded official-minutes milestone slice, not completion of either issue.

## Acceptance and implementation boundary

The [council design](../superpowers/specs/2026-11-07-council-accountability-design.md#important-issues-advocacy-and-follow-through)
requires separate member actions, campaign relationships and issue outcomes.
The owner's subsequent direction requires compact panels, shared analysis,
unchanged-input reuse, enforceable cost limits and no broad historical backfill.

`ExtractCouncilIssueUpdatesJob` selects one existing official minutes document.
`CouncilProfiles::IssueInput` supplies its complete text, reporting date and
existing approved agenda/topic identities once. A retained `CouncilIssueReview`
and request receipt serve every relevant member. Topic creation/merging, member
credit and promise grading are outside the extractor. Proposals, authorizations,
secured funding, implementation, completion, rejection, deferral and explicit
uncertainty remain distinct. The source's reporting date is not invented as the
event date. Material conditions belong in the short summary.

Source/current-topic checks and exact contiguous passages are validated in code.
They establish location and identity, **not independent semantic validation of a
model's interpretation**. The prompt supplies the interpretation contract. Real
provider accuracy has not been evaluated in this slice. Source text is retained
with each result; legacy unversioned text does not acquire invented artifact
provenance. The cited link resolves through the existing source catalog.

Explicit source selection registers only that document for recovery in the
existing nightly processing. It does not scan or enroll historical meetings.
A source, date, body or agenda/topic-input change prepares new evidence;
unchanged completed input and prompt/model edits alone reuse the saved result.
Pending/failed work has at most two attempts; incomplete/uncertain output holds.
Oversized input is retained and held, never truncated. Missing allowance pauses
before transport and preserves attempts. Each request uses existing monthly,
daily and run reservations. The live-action policy does not admit this stage.
The spending report includes issue-update receipts separately.

The main member record shows up to three short issue updates, with additional
updates and supporting passages in independent disclosures. Selection uses
approved campaign topics or eligible recorded Council decisions in the selected
service period. The source may be another official body; its name stays visible.
This is issue context, not evidence that the outcome fulfilled a campaign
statement or was caused by the member. All-records mode does not silently borrow
a term. Closed source text is in permitted HTML for readers and verified Google;
anonymous gated and spoofed crawler responses omit it.

## Execution evidence

Environment: isolated checkout `codex/council-issue-updates`, base `c6ca564`, Ruby
4.0.9, PostgreSQL `trr_council_issue_updates_test`. No real development data was
used as test fixtures or reset. Provider transport was deterministic; request
preparation, reservations, receipts, validation, persistence and later HTTP
reads were real. No paid AI, production operation, backfill, merge or deployment.

- `bin/rails test test/integration/council_issue_updates_test.rb
  test/integration/campaign_action_matching_test.rb
  test/jobs/council_profiles/monthly_spend_test.rb
  test/integration/campaign_cost_preflight_test.rb`: **32 tests, 333 assertions**,
  no failures/errors/skips.
  One source → two distinct milestones → both members with different votes,
  without new votes; unchanged/nightly reuse; source correction; stale in-flight
  result; topic/term/cancellation gates; missing budget; retry/incomplete/oversized
  holds; private and verified-Google access. Counts and distinctive passages were
  checked at source, retained result, receipt and rendered boundaries.
- `bin/rails test test/system/member_issue_updates_journeys_test.rb
  test/system/member_peer_votes_journeys_test.rb`: **2 tests, 25 assertions**,
  no failures/errors/skips. Independent source disclosures, hidden supporting text,
  readable event/report dates, correct source URLs and no horizontal overflow.
  Chromium 157 / installed driver 155 emitted a compatibility warning but ran.
- Representative faults: accepting an invented quote changed expected `failed`
  to `completed`; bypassing visitor gating exposed the issue section. Each fault
  failed its intended assertion, was restored, and reran green. No syntax/boot
  failure was counted as defect detection.
- Migration on the isolated database; `bin/rubocop -A db/schema.rb`; inspected
  schema diff contains only the two new tables, indexes/FKs and schema version.
  Full `bin/rubocop`: **821 files, clean**. Documentation links and `git diff
  --check` passed.
- An initial `test:system TEST=...` command did not discover the test. Passing a
  filename to `test:system` then ran the broader suite and was interrupted; it is
  not claimed as passing. The focused runner is `bin/rails test
  test/system/member_issue_updates_journeys_test.rb`. Its initial missing job
  helper was fixed before the passing journey.

## Real source check and cost boundary

The [January 14 Recreation Board minutes](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Minutes-67ea762e9d124a7ca41d5ea5f8aa0702.pdf)
(page 1, inspected visually) distinguish the concession proposal's budget from
additional funding still needed to proceed at that scope. The official funding passage is
retained as a selected text fixture with its URL/date; deterministic extraction preserves
the conditional funding and reporting-body distinction. This is a source and
pipeline check, not a live model-quality measurement or a claim about the
project's current state.

Offline construction using the complete 21-page text fits the input limit. No
provider was called and no development profile was populated with a simulated
result. At the checked November 8 rates, the conservative request estimate is
approximately $0.132, or $0.264 for both permitted attempts, shared across all
relevant profiles. This is an input-byte/output-limit estimate, not measured
usage, an invoice guarantee, a monthly forecast or authorization. Real monthly
volume and the remaining feature stages must still be measured separately.

## Remaining work

No project-page/budget/report adapter registry, attributed advocacy extraction,
explicit staff recommendation comparison, automatic admission for this stage,
complete source coverage, or campaign-to-outcome semantic matching is claimed.
Selected-source recovery is implemented; automatic discovery of future project
sources remains open. Missing evidence never proves no work or completion.

The user's other profile-review session could not be reached through the app's
local transport; no new voter-persona review is claimed. The source-based
compact presentation still needs that review on populated real records.

## CI follow-up

The first full CI run found five existing recovery assertions failing because an
empty issue-source recovery job was queued even when no source had been selected.
Recovery now checks for selected sources before enqueueing. This avoids idle work
and preserves the established no-work contract. The recovery, campaign-topic and
new issue integration files passed together: **23 tests, 246 assertions**.
