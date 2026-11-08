# Campaign statements and related issue records: November 8, 2026

This bounded RES-10/11 extension under #240 and parent #234 connects accepted
campaign statements to existing issue records. It is related-topic context, not
an assessment that a vote fulfilled a position or that a project was completed.

## Contract and behavior

The [member-page contract](../superpowers/specs/2026-11-07-council-accountability-design.md#proposed-member-page)
and [delivery adjustment](../superpowers/specs/2026-11-07-council-accountability-design.md#delivery-priority-and-proportionality)
require a useful sourced record, distinct statements/actions/outcomes, existing
analysis reuse and actual service eligibility. The owner requested real civic
data for development and ordinary correction mechanisms rather than speculative
infrastructure. Existing public/gated rules continue to apply.

A campaign card with accepted approved-topic matches now shows those issue links
and the member's existing related Council votes. Code uses the existing sourced
service window and eligible Council meeting inventory, excludes votes before the
statement date, and applies the same procedural filter as Featured votes. An
approved unanimous procedural motion stays out; a contested one remains. Multiple
matched topics do not duplicate a decision within a card.

The agenda title identifies the decision, with the original motion wording in a
native disclosure. Member vote and Council result/tally are separate. The first
three records are visible; an ordinary disclosure reveals the rest. Each record
links to its meeting and sources. Missing known-window records are described as
missing from the available record; an unknown service window does not produce a
claim of no activity. Unmatched statements retain their campaign text.

Each read uses the saved facts and accepted topic associations. A later accepted
vote or a topic merge/block is reflected on the next request. Reading or repeating
the request creates no AI work. There is no new table, job, schedule or generation
stage. This uses the [shared matching stage](campaign-topic-matching-2026-11-08.md)
and [Council eligibility projection](council-attendance-2026-11-08.md).

## Real-data acceptance

An isolated local copy used the already-synced civic database and the saved HTR
reference: 11 extracted statements, seven accepted cards for the three cohort
members, 2,157 saved votes and 628 cohort votes. No new production copy or backfill
ran. Provider transport for the preceding shared matching stage was deterministic;
this projection made no provider call. Only the local operator/budget transport
was synthetic; no fixture loader ran against this acceptance database.

- Bittner retained three campaign cards. Housing links to one recorded vote;
  Hamilton links to rezoning, the redevelopment vision and the blight designation.
- Brandt retained two cards, including the existing housing-related vote.
- Derby retained two cards. The short-term-rental topic supplies three votes,
  including fee changes and the RV/camper room-tax ordinance. These do not by
  themselves establish follow-through on Airbnb regulation.
- The owner confirmed Bittner's 17-acre reference means Hamilton. That is owner
  clarification in the checked reference, not a claim that the article names it
  or an automated model independently inferred it.
- Temporarily withholding one actual saved vote on the isolated copy, restoring
  its exact attributes, then repeating HTTP reads produced three, four and four
  Bittner related records. Stored votes/statements and analysis counts were
  unchanged afterward. This tests arrival at the accepted-record boundary, not
  a fresh minutes-extraction job.

Real browser inspection found generic motion wording made two Hamilton decisions
indistinguishable. Rendering their existing agenda titles corrected that observed
problem. Phone and desktop checks exercised real profile cards, motion disclosure,
meeting navigation and the September 21 official minutes link. The initially
minimal civic copy lacked meeting-document rows; 18 actual document metadata rows
for the six relevant meetings were copied from the existing local development
database to restore those source links. No remote database operation occurred.

## Execution and defect detection

Application revision: `05d9dad3`, based on integration revision `27982db7`.
The base composes application/test changes from unmerged PRs #271, #272, #278 and
#279; the new feature diff is independent of those already reviewed changes.
Local environment: Ruby 4.0.9, PostgreSQL, Chromium, separate regression and
real-data acceptance databases. Ordinary and browser suites ran serially.

Commands used `DATABASE_URL` for the isolated regression database and
`PARALLEL_WORKERS=1`:

- `bin/rails test test/integration/member_campaign_activity_test.rb test/integration/member_campaign_record_test.rb test/integration/member_recorded_votes_test.rb test/integration/member_council_attendance_test.rb test/integration/member_service_periods_test.rb test/integration/campaign_topic_matching_test.rb`:
  34 tests, 522 assertions, no failures/errors/skips.
- `bin/rails test test/models/member_test.rb test/models/council_service_period_test.rb test/jobs/campaign_statement_publication_test.rb test/jobs/reconcile_campaign_sources_job_test.rb test/services/topics/merge_service_test.rb`:
  61 tests, 204 assertions, no failures/errors/skips.
- `CHROME_BIN=/usr/bin/chromium bin/rails test test/system/member_campaign_activity_journeys_test.rb test/system/member_campaign_journeys_test.rb test/system/member_recorded_votes_journeys_test.rb test/system/member_service_period_journeys_test.rb test/system/member_council_attendance_journeys_test.rb`:
  seven journeys, 147 assertions, no failures/errors/skips. The new journey
  expands a fourth record, opens its meeting, returns/reloads and checks phone fit.
- After the agenda-title refinement, the new integration file reran: four tests,
  46 assertions; its browser file reran: one journey, 13 assertions, both green.
  The browser asserts the distinct title and opens the original motion wording.
- `bin/rubocop`: 778 files, no offenses. `git diff --check` passed.

Process-local faults ran only in the isolated regression environment. A clean
baseline and restored rerun each passed two tests/24 assertions. Replacing the
eligible meeting inventory with all Council meetings failed the intended row
count (one expected, five actual). Removing the visitor gate failed after proving
allowed access first (campaign section absent expected, one actual). Each bounded
fault caused its intended behavioral assertion to fail; no fault was committed.

Implementation coverage, real civic-data observations and those two demonstrated
defect checks are separate evidence. Synthetic regression fixtures cover losing
member votes, failed motions, service boundaries, canceled/future/listening/other
body meetings, topic correction, access and overflow. The real related-vote sample
contains affirmative member votes, so it does not independently verify every
regression variant. Broad provider accuracy, semantic action alignment, completed
project outcomes, full-term coverage and production behavior remain unverified.
