# Automatic campaign updates: November 8, 2026

Application revision: `02a65d53`, based on PR #275. This advances #239 under
#234; campaign/action/outcome comparisons and paid admission remain separate.

## Contract and observed problem

The [operating cadence](../superpowers/specs/2026-11-07-council-accountability-design.md#proposed-operating-cadence)
requires new evidence to trigger shared processing and missed work to recover
within existing nightly processing. Unchanged inputs must not cause new AI calls.
The owner requires real civic data for development acceptance and proportionate
watchdog-site behavior, not speculative correction infrastructure.

On the preceding revision, correcting the real HTR source publisher saved a new
version but queued no job. All seven current campaign cards disappeared until
someone explicitly ran processing. This is a reproduced maintenance gap.

## Delivered boundary

ADM-21 now queues the existing extraction job after a committed source save when
the current version has no extraction. Cached matching analysis republishes all
supported members. New analysis still pauses without an explicit allowance;
source intake does not authorize spending. Resident reads perform no work.

BG-01 queues `ReconcileCampaignSourcesJob` before fetching the city listing.
BG-08 recovery republishes completed results and queues missing/pending intake.
It leaves paused, running, uncertain, incomplete, oversized and failed stages
alone. No recurring schedule changes, new retry policy or paid admission were
introduced. An unchanged completed replay preserves statement IDs/timestamps.

## Real-data acceptance

The separate local acceptance database used existing civic records and the
checked HTR extraction from [the preceding slice](member-campaign-records-2026-11-08.md#real-data-acceptance).
The full article and local reference artifacts remain outside Git. No website
accounts or credentials were copied; the shared preview database was unchanged.

The old revision reproduced the missing trigger after correcting publisher
attribution to Manitowoc Herald Times Reporter: Bittner/Brandt/Derby went from
3/2/2 current cards to 0/0/0, with no job queued. The new nightly recovery restored
3/2/2 with the corrected attribution. A source URL correction using the owner's
supplied URL parameter then queued processing and reused the same analysis.
An unchanged save and nightly replay queued nothing and preserved publication
identities/timestamps. All 628 existing cohort votes remained unchanged.

Adding the next actual article question and candidate answers queued processing
but paused at `missing_budget`, with zero attempts, provider requests or new
statements. The preceding version remained retained; voting records stayed
visible while the new source version awaited analysis. Nightly recovery did not
retry that paused stage. AI service construction was forbidden throughout.

This exercised real source text, existing identities, jobs, persisted state and
later HTTP profile reads. It is an offline reference replay, not a provider
accuracy evaluation. Available vote history starts in July 2025; no complete-term
coverage claim or production backfill was made.

## Repeatable verification

Ruby 4.0.9, PostgreSQL, one worker, a separate ordinary test database. Deterministic
regression fixtures are distinct from the real-data acceptance above.

- Focused intake, update-trigger, recovery and extraction-job tests: 15 tests,
  214 assertions, no failures/errors/skips before the final fault assertion.
- Update-trigger baseline: 2 tests, 39 assertions, no failures/errors/skips.
- Chromium `bin/rails test test/system/member_campaign_journeys_test.rb`:
  2 journeys, 64 assertions, no failures/errors/skips. An admin uses Edit and
  Save article, then sees corrected publisher links on a later member read and
  refresh. The existing mobile source-navigation/logout journey also passes.
- `bin/rubocop --cache false`: 752 files, no offenses. `git diff --check` passes.

A process-only fault disabled the source-save callback after the clean baseline.
The metadata-update test failed its intended missing-processing assertion
(1 test, 6 assertions, 1 failure, no errors). Product files were never mutated.
The subsequent full-suite run uses normal callbacks.

The browser uses real Rails form/authentication/job boundaries with captured
email transport and deterministic provider responses. The queue worker is drained
by the test helper. Nightly discovery uses a simulated city HTTP response and
asserts recovery is queued before that fetch. Live scheduler/worker execution,
real email/provider delivery and native passkeys were not verified here.
No paid AI, production operation, merge or deployment occurred.
