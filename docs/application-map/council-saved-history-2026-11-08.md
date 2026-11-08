# Reuse saved meeting analysis — November 8, 2026

## Contract and scope

RES-10/11 and BG-09. The owner reaffirmed the existing minutes-first workflow
and asked that profiles reuse accepted analysis instead of introducing a second
general meeting-analysis pipeline. This change reads published `minutes_recap`
agenda summaries through the existing item matcher, approved topic links and
citation resolver. It creates no extraction record, vote or AI request.

The shared issue history remains separate from personal credit and specific
campaign-promise matches. Existing supplemental minutes evidence takes precedence
for the same meeting/agenda item. Generic saved summaries do not enter the
specific-promise comparison pipeline. That preserves the supported comparisons
already retained without turning a topical connection into a promise verdict.

Older published recaps predate the citation catalog. They retain their meeting
page link; a legacy string such as `Page 3` is not upgraded to a verified PDF
citation. Newer recaps retain resolved source links. Existing publication,
preferred-summary, cancellation, service-period and generated-content access
rules apply. No new withdrawal or vote-extraction machinery is introduced.

Recurring profile source admission and budget selection now exclude minutes,
including when an older live policy lists them. The app's ordinary meeting/topic
workflow still analyzes new minutes. Specifically selected packet recommendations
and separately bounded manual missing-fact work remain possible under explicit
allowances. Existing comparisons against retained minutes evidence remain usable.

## Implementation and defect checks

Environment: Ruby 4.0.9, local PostgreSQL, isolated synthetic test database; patch
based on `297bc0b7d5e12110cae6bf192fe8318b2648f29a`. No production operations.
Deterministic providers replace transport, and page-read tests fail on an AI call.

Commands:

```sh
bin/rails test test/integration/council_saved_issue_history_test.rb \
  test/integration/council_live_sources_test.rb \
  test/integration/campaign_issue_evidence_test.rb \
  test/integration/council_issue_updates_test.rb \
  test/integration/council_minutes_authority_test.rb
bin/rubocop
git diff --check
```

The targeted runner executed 37 tests, 346 assertions, zero failures/errors/skips.
RuboCop inspected 869 files with no offenses. Assertions cover two members
sharing the same saved update, later-request changes, legacy citations, service
eligibility, generated-content access, no fabricated quote or campaign match,
supplemental deduplication, and no additional extraction/vote/reservation records.

Representative faults followed a clean passing baseline:

- Returning no saved history failed the member-page presence assertion.
- Removing the recurring-budget minutes exclusion failed the expected
  `outside_live_source_scope` assertion; the stage obtained an allowance.
- Overriding the visitor guard in an isolated test process failed the assertion
  that generated issue history is absent for a gated anonymous visitor.

Each fault was removed and its affected tests passed again. The first two checks
restored to 14 tests/131 assertions; the access check restored separately. The
final 37-test run also includes the subsequently added legacy-format case.
These experiments demonstrate detection, not production incident frequency.

## Real saved-data and browser checks

An isolated copy of the existing local development database supplied the actual
meeting summaries, topics, agenda items and votes. The three previously verified
cohort service dates and their retained source were reused locally. The original
development database and the existing campaign preview were preserved. No test
fixtures were inserted into these real profiles; no provider call or historical
extraction ran.

The publication/item/topic pipeline contained 211 published minutes recaps in
the service window, 207 preferred non-canceled recaps, 954 saved item details,
585 details matched by the existing item matcher, and 418 matches with an
approved linked topic. Of those, 41 have modern resolved minutes citations and
377 use legacy references. All 418 reach the shared history across 132 meetings
and 202 topics. Unmatched/unlinked details remain absent; this does not establish
complete historical coverage. The initial Council-only audit separately found
48 recaps and 234 item details; it is not the all-committee denominator above.

The member projections contain 313 updates for Mark Bittner, 320 for Doug Brandt
and 321 for Shannon Derby, from 116 meetings each. These include relevant issue
reports by other bodies, labeled with their meeting, not additional Council
votes or claims that the member attended those meetings. There are zero new
`CouncilIssueReview` and `CouncilIssueRequest` rows in this copy.

The local browser journey exercised all three actual pages at 390px and 1280px:
three updates initially visible, older updates disclosed on demand, source
disclosures independent, official minutes and meeting navigation available,
no summary rendered as a direct quotation, and no horizontal overflow. It used
the existing Capybara/Selenium browser tooling after the earlier CLI interaction
problem. Source-link targets were inspected; this check did not independently
re-verify every historical summary against its document.

## Cost correction and remaining scope

Reading saved history adds **$0 in AI requests**. Removing both the assumed five
packet analyses and the five duplicate minutes analyses from the earlier sample
leaves ten campaign/vote and ten campaign/issue comparison batches. Their sampled
reservation ceilings total $3.686930 for one attempt or $7.373860 with two attempts
everywhere: approximately **$3.70 or $7.40 per month** under those assumptions.

This is a request-size workload scenario, not an observed monthly invoice or a
whole-site bill. Existing meeting/topic AI, campaign intake, selected supplemental
sources, formal records and historical backfill are separate. The previous
proposed $15 monthly ceiling remains disabled; pricing renewal and explicit
allowances are still required before recurring paid processing. Generic saved
summary-to-promise interpretation is not implemented by this read-only reuse.

The parent and broader evidence issues remain open. No backfill, merge,
deployment or production synchronization occurred.
