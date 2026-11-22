# Saved minutes motions on member profiles — November 8, 2026

## Contract and implementation

BG-02 → BG-09 → RES-10/11, advancing #243/#240 under #234. The owner requires
reuse of accepted meeting analysis, compact sourced actions and shared cached
campaign comparisons. This slice reads the existing published minutes recap's
attributed motion and exact supporting passage. It introduces no extraction
table, prompt, general source-analysis request or schedule.

The existing item matcher, minutes quote/identity validator, approved topics,
member identity and documented service periods select substantive movers and
own-motion amendments. Ordinary seconds and procedural motions are excluded
from this action projection; existing vote-display rules are unchanged.
Supplemental personal evidence takes precedence for the same agenda item.
A short “Made a motion on” label uses the saved agenda title; the exact passage
and official minutes remain under Source. This reports involvement, not policy
authorship, passage or promise fulfillment.

New minutes publication queues the existing shared evidence-comparison job;
existing nightly processing recovers missed work. The existing comparison
records, batching, positive/negative cache, receipts and spending limits apply.
New comparisons need an explicit minutes source/date policy or bounded run;
this does not re-enable duplicate minutes extraction. Recap prose and timestamps
are excluded from pair identity. A prepared comparison whose attribution was
removed holds without dispatch. Reads use current candidate evidence, so removed
attributions do not keep a published campaign connection.

## Implementation and workflow verification

Base revision `87f336b865d73af187a866166896133c359f88ca`; Ruby 4.0.9,
local PostgreSQL with an isolated synthetic test database. Provider transport
alone is deterministic; no real-provider accuracy is claimed by these tests.

```sh
bin/rails test test/integration/council_saved_motion_actions_test.rb \
  test/integration/meeting_motion_attribution_test.rb \
  test/integration/campaign_issue_evidence_test.rb \
  test/integration/council_recorded_actions_test.rb \
  test/integration/council_saved_issue_history_test.rb \
  test/integration/council_live_sources_test.rb \
  test/jobs/summarize_meeting_job_test.rb \
  test/jobs/reconcile_campaign_sources_job_test.rb
bin/rubocop
git diff --check
```

The runner executed **77 tests / 505 assertions**, with zero failures, errors
or skips. RuboCop inspected **872 files**, no offenses. The actual minutes job
publishes retained attribution and queues matching without altering accepted
votes. The saved-action workflow checks source → two members → one shared
comparison batch → persisted matches → later pages. A synthetic owner-occupancy
proposal can match its specific promise; a rental-payment portal does not.
Both results are reused after prose-only edits, with no new requests or
reservations. A proposal without a second remains measurable effort.

After a passing baseline, bounded faults that put recap timestamps into the
cache identity or allow removed evidence to dispatch each failed the intended
assertion. An isolated access-guard override exposed a card to a gated visitor
after allowed-content proof, failing that assertion. Faults were restored;
the final suite above is green. This is representative defect detection, not
evidence that source corrections are frequent.

## Real local data and browser checks

A disposable copy of the existing local civic database supplied the actual
minutes, agenda items, topics and votes. The normal development database and
main campaign preview were preserved. Three agenda items in two minutes sources
received six individually checked mover/seconder corrections to saved recap
fields, addressing #302's demonstrated validator loss. Exact passages and
existing source URLs were verified before those local-only corrections; other
summary content and accepted votes were unchanged. This was a bounded factual
correction, not historical extraction or a paid backfill.

The projection shows Bittner's September 28, 2026 WPPI contract-extension motion
and Brandt's October 5, 2026 forestry-grant motion. Derby has no supported action
in this checked sample. Missing actions are not evidence of no work. No synthetic
campaign matches were inserted into these profiles, and provider/request counts
were unchanged.

Existing Capybara/Selenium Chromium tooling exercised all three real pages at
390px and 1280px: correct action counts/subjects, sources initially closed,
exact quotation and official minutes link after opening, independent issue
disclosures, topic navigation and browser return, and no horizontal overflow.
Screenshots were inspected. Selenium reported a read-only metadata-cache warning;
all six journeys completed. The existing voter-review agent assessed the supplied
wording and recommended “on” to identify the motion's subject; this was a simulated
reader check, not factual validation or an independent browser inspection.

## Cost and limits

Reading saved motions adds **zero AI calls**. Only new specific statement/action
pairs enter the already budgeted shared matcher. This slice enables no allowance
and does not establish a monthly invoice estimate; actual recurring pair volume
remains part of #238. Existing saved generic issue summaries still do not become
automatic promise matches. Names absent from old recap fields are not inferred
by this adapter. No broad backfill, production operation, merge or deployment ran.
