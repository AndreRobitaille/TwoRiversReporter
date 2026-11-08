# Specific campaign statements and recorded decisions — November 8, 2026

Scope: RES-10, RES-11 and BG-08 under #234/#236/#240, following the owner's
request to test specific promise/action matching on Airbnb. Binding direction is
in [the development plan](../DEVELOPMENT_PLAN.md) and
[the council design](../superpowers/specs/2026-11-07-council-accountability-design.md).

## Acceptance and limits

Topic overlap retrieves candidates only. The shared analysis must establish a
connection to the specific statement using the actual motion and official minutes,
not an agenda recommendation. It returns every requested pair, including negative
and uncertain results. Direct matches require a supporting contiguous minutes
passage; code validates completeness, identity and quotation location. Semantic
correctness still requires source review, not merely a passing quotation check.

Display the exact matched statement with its conditions, the dated motion,
recorded member vote, separate Council result, explanation and minutes passage.
A yes vote on a failed motion is still a yes vote. Relevance is not a promise
grade, proof of motive, completed issue, or finding that the member caused the
outcome. Empty/held results do not mean no action. Broad priorities, advocacy,
opportunity assessments, coverage-aware inaction and contradiction highlights
remain unfinished. The existing main voting record remains available.
The owner clarified the retrospective standard: over a full three-year term,
a specific promise with neither fulfillment nor measurable work is a broken
promise. Documented advocacy, proposals and a losing yes vote count as work.
This selected-meeting check cannot yet establish that full-term absence.

The service reuses eligibility from Council service/known-meeting records and
statement dates. Unresolved or superseded campaign statements and unavailable
minutes cannot produce a current public comparison. The server renders permitted
comparisons in HTML, preserving the existing audience boundary and independent
native disclosures. No extra client-side generation or schedule is introduced.

## Shared processing and cost

`Campaigns::MatchActions.prepare` serializes preparation on the meeting. Up to
20 missing semantic pairs share one full minutes input across members/sources.
Both direct and rejected results are cached. New pairs do not repeat completed
pairs; identical semantic statements and metadata-only campaign corrections reuse
their result. Rebuilding motion/vote projection IDs also reuses the semantic
result, while the public page reads the current member vote. Retained requests
and original results remain unchanged. Actual source/motion/statement changes select a new key. Oversized
input is held intact rather than truncated. Prompt/model settings alone do not
trigger periodic reanalysis of completed evidence.

New minutes publication or completed topic matching queues
`MatchCampaignActionsJob`; existing nightly campaign recovery checks missed work.
No public request runs a provider. The existing day/run/request/concurrency
reservations and exact request digest are required before transport. Two attempts
is the stage ceiling; uncertain or incomplete transport does not automatically
redispatch. Nightly delivery without an allowance cannot spend. This slice adds
no production allowance or general backfill control.

## Deterministic behavioral verification

Environment: branch `codex/campaign-decision-matching`, base `049b0ce`, Ruby
4.0.9, PostgreSQL in an isolated regression database, Chromium. Provider
transport alone is replaced; real extraction publication, topic publication,
spend admission, receipts, matching, HTTP projection and browser navigation run.

Commands actually run:

```sh
bin/rails db:create db:migrate
bin/rubocop -A --cache false db/schema.rb
bin/rails test test/integration/campaign_action_matching_test.rb
bin/rails test
CHROME_BIN=/usr/bin/chromium bin/rails test test/system/campaign_action_journeys_test.rb
CHROME_BIN=/usr/bin/chromium bin/rails test:system
bin/rubocop --cache false
```

Eight matching HTTP/pipeline journeys pass. They cover two members
in one shared request, every pair retained, correct negative exclusions, a losing
yes vote, exact quote and meeting link, unchanged nightly replay/reads, new-pair
only dispatch, missing allowance, malformed/invented evidence, retry ceiling,
current-source/status changes, metadata reuse, rebuilt motion identities,
contrary-policy decisions, multi-issue placement and allowed-then-gated reads.
The combined matching and campaign-activity run passes 12 tests / 125 assertions.
The new phone browser journey passes with 15 assertions: open the relevant issue,
inspect statement/vote/result/quote, follow the meeting, return, refresh and retain
layout without generating. CI exposed a navigation race in the test: opening the
disclosure before Turbo finished the fragment visit could lose the open state
or retain a stale element. The test now waits for that visit to finish and uses
fresh scoped selectors. It does not add a sleep or alter the public controls.

At the initial PR head, the full application suite passed: 2,517 tests / 17,431 assertions, no failures or
errors, one existing skip. The full browser suite passes: 37 journeys / 1,108
assertions, no failures, errors or skips. RuboCop passes with no offenses.
Initial broader targeted run caught old no-job assumptions; those expectations
now allow the new non-spending comparison job while preserving no-provider checks.

Representative defect detection, in the isolated regression checkout:

- Clean baseline passed. Removing the direct-result filter made the shared
  comparison HTTP test fail: six public comparisons instead of one (no errors).
- Bypassing `gated_for_visitor?` made the allowed-then-anonymous test fail: the
  campaign section remained present (no errors).
- Including transient motion IDs in the cache key made the rebuilt-projection
  comparison disappear and failed its intended assertion (no errors).
- Removing issue-specific placement duplicated a real type of multi-topic
  decision beneath an unrelated heading; the targeted assertion failed (no errors).
- Mutations were restored before the passing regression runs.

These prove the relevant regressions are detected. Deterministic provider
responses do not prove model interpretation accuracy.

## Real Airbnb source check

The existing local civic-data copy retained the actual HTR statement and reviewed
March 7 forum statement. This check did not invent candidate statements or edit
accepted votes to manufacture a successful match. Empty local minutes text was
filled from three official PDFs. Two earlier Council decisions were added locally
from their official minutes; the full term is still not backfilled.

The five source meetings were:

- [April 21, 2025 minutes](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Minutes-d1ea69819ec54f9a864b011dabf94e58.pdf), item 25-072: R-1 permitted-use amendment.
- [May 5, 2025 minutes](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Minutes-0a069b395b7b4040b2b46a2a7190f8f0.pdf), item 25-085: rental licensing ordinance with lighting amendments. Brandt is omitted from this motion's vote list; no vote or absence was invented.
- [November 17, 2025 minutes](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Minutes-16156f699fa84c408490828251b4143b.pdf), item 25-228: tabling a fee ordinance.
- [December 15, 2025 minutes](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Minutes-40b831875c314d598c4a80447bfd701b.pdf), item 25-228: fee ordinance adoption.
- [April 20, 2026 minutes](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Minutes-8b3551cf06b040c9a7496d60a1448ba1.pdf), item 26-071: RV/camper room tax.

Nine comparisons, five shared requests, all complete: none established a direct
match to Brandt's named lottery/owner-occupancy mechanisms or Derby's unspecified
proactive solution. Reasons were checked against the actual motions. This bounded
result does not establish that they did nothing, broke a promise or opposed
regulation. The [October 28, 2024 work-session minutes](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Minutes-aafbed31cb9749cc86ef5ad95ff3cd5c.pdf)
also document discussion without a Council action, illustrating why vote matching
alone cannot assess advocacy or the complete term.

The authorized pilot used a hard spending/request cap; its allowance was revoked
afterward. Exact requests, responses, usage and source artifacts remain in the
private local source archive, not public fixtures. Repeating those prepared jobs
and real HTTP reads with the provider constructor forced to raise made zero
additional requests. All 94 accepted article/forum statements remained present
across the three cohort pages. Older real decisions remained reachable through
numbered vote pages. Live Chromium at phone width confirmed the actual Airbnb
statement, independent open sections, no horizontal overflow and no rejected
pair rendered.

## Real positive comparison

The review also requested a positive control. Brandt's accepted March 12 forum
statement supports business tools including tax increment financing. The
[April 6, 2026 minutes](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Minutes-92069de44a594aa6990824383b8252fd.pdf),
page 4, record grants of up to $17,536 to Cool City Motel from TID 11 and up to
$10,000 to Lighthouse Inn from TID 12. Brandt voted yes on both; both passed 9–0.
The scanned page was OCRed locally and checked visually. One shared request
returned two direct comparisons with exact supporting passages. These are now
visible in the local preview under tax increment districts, with the matched
statement, member vote, Council result and source. The check caught and corrected
duplicate placement under Revolving Loan Fund; topic placement now uses the
decision's actual issue links, including topic rows combined by shared statements.

Across both checks: 11 comparisons in six requests, with an estimated $0.094536
of provider usage against the $1 combined ceiling. Both one-use allowances were
revoked. Replaying all selected work and HTTP reads with the provider constructor
forced to raise made zero additional requests; all 94 accepted statements and
2,174 local votes remained intact. Phone inspection confirmed two positive
comparisons in the appropriate issue, independent disclosures and no overflow.
Implementation tests use deterministic provider responses; the preview findings
come from the real sources. A contrary-policy scenario is tested synthetically,
not presented as a real finding about these candidates.

## Resident readability correction

The owner accepted the connections but rejected the amount of default text.
RES-10 now shows one matched position instead of a generic position followed by
the matched position, and at most two compact decision rows. Member vote and
Council result remain separate. One closed Supporting details disclosure retains
the explanations, original agenda titles, actual motions, exact minutes passages
and meeting links. Additional matched positions stay available in a closed
disclosure; the full campaign source section is unchanged.

The three existing resident-persona reviewers in the separate profile-review
session inspected the real phone preview. All could identify the businesses,
Brandt's yes votes, date and Council approvals after the first simplification.
Their remaining title suggestion was applied: application boilerplate, docket
numbers and addresses move to supporting details; requested assistance and named
applicants remain visible. This is deterministic display formatting, not a new
AI summary. The final TID panel has 60 visible words including headings and controls.
This feedback is a readability check, not independent source validation.

Verification after this correction: 18 targeted matching/layout HTTP tests / 185
assertions, two browser journeys / 42 assertions, and RuboCop pass. Making the
supporting disclosure open by default fails the intended browser assertion that
the explanation is initially hidden; restoring it passes (one journey / 17
assertions). Real phone and desktop inspection confirms the complete evidence
opens, other issue sections stay open independently, and the phone layout does
not overflow. Replaying the real-data verification still retains all 94 campaign
statements, 2,174 votes and six provider receipts with zero added requests.

The owner then reported the stray `per calendar year` line under the Airbnb
position. It was a separately stored timeframe already expressed in the summary.
Both issue panels and source cards now omit repeated qualification text while
retaining distinct conditions/deadlines with Condition or Timing labels. Display
normalization treats each/per/every calendar year alike; source fields are not
rewritten. The actual Brandt card was checked in the phone browser: the complete
position remains and the extra timeframe line is gone. Nineteen helper/HTTP tests
pass with 249 assertions, and targeted RuboCop passes. Removing deduplication
fails the intended helper assertion; restoring it passes all three assertions.

No production operation, database sync, production backfill, merge or deployment.
