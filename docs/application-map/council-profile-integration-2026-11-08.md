# Combined council profile verification — November 8, 2026

This integration brings the reviewed prepared-forum branch (#281, #282, #284)
together with the later member record, campaign matching, cost, issue-update and
recorded-action branches through #293. Parallel branch history is preserved;
no GitHub PR was merged or production system changed.

The forum branch head is `75e55e4`; the profile branch includes `34831d5`.
The combined implementation is `2cf1517`. The source conflicts were the schema
version and overlapping documentation additions. The combined schema retains the
newer issue-review version and both prepared-transcript columns. Documentation
retains both the forum contracts and the owner's later layout/cost requirements.
The background workflow now refers to a supplied source, including forums, and
retains monthly as well as daily/run spending authorization.

The auto-merged request builder and prompt data were inspected: prepared forums
retain their complete-input and larger-output limits, explicit literal answer
fields and reviewed speaker attribution. Campaign matching, action matching and
shared issue/action analysis keep their distinct request construction and existing
limits. No paid dispatch or allowance was added by integration.

## Executed checks

Ruby 4.0.9, isolated PostgreSQL `trr_council_profile_integration_test`, serial
application/browser suites with deterministic provider transport. The real preview
database was not used for fixtures, reset or reimported. No additional paid AI,
production operation, broad historical backfill or deployment ran.

- Fourteen affected application files: **91 tests, 1,092 assertions**, green.
  These exercise prepared forum intake/extraction, complete response bounds,
  source/topic matching, campaign publication, direct decision matching, cost
  preflight/live admission, shared issue/actions, term selection, search and peer
  comparisons. After incorporating the all-records action fix, its integration
  file passed again: **8 tests, 83 assertions**.
- Six browser journeys: **6 tests, 100 assertions**, green. Actual controls cover
  prepared forum upload, campaign comparison disclosures, recorded-action source
  disclosure, vote search/filtering, term navigation and peer decisions. Chromium
  157 with installed driver 155 warned about compatibility but executed normally.
- Full `bin/rubocop`: **838 files**, clean on the combined forum/profile code;
  the later two-file action eligibility fix also passed targeted lint in #293.
- `git diff --check` and local documentation targets were checked. No new
  behavioral assertions beyond #293 were introduced by conflict resolution;
  the relevant source-specific fault evidence remains in those PR reports.

Application command:

```sh
bin/rails test test/jobs/extract_campaign_source_job_test.rb test/jobs/prepared_campaign_forum_extraction_test.rb test/integration/prepared_campaign_forum_intake_test.rb test/integration/full_campaign_forum_test.rb test/integration/campaign_topic_matching_test.rb test/integration/campaign_cost_preflight_test.rb test/integration/member_campaign_record_test.rb test/integration/campaign_action_matching_test.rb test/integration/council_recorded_actions_test.rb test/integration/council_issue_updates_test.rb test/integration/council_live_action_budget_test.rb test/integration/member_vote_filters_test.rb test/integration/member_peer_votes_test.rb test/integration/member_council_period_test.rb
```

Browser command:

```sh
bin/rails test test/system/prepared_campaign_forum_journeys_test.rb test/system/campaign_action_journeys_test.rb test/system/member_recorded_actions_journeys_test.rb test/system/member_vote_filters_journeys_test.rb test/system/member_council_period_journeys_test.rb test/system/member_peer_votes_journeys_test.rb
```

## Limits

This proves the combined implementation paths under deterministic test providers.
It does not establish complete real-source coverage or provider accuracy, migrate
the real preview to the new issue tables, enable generation, or complete parent
#234. Staff recommendation comparisons, formal cases, full campaign-to-action/
outcome semantics, recurring cost/admission and cohort rollout remain tracked
work. Historical backfill still requires the owner's personal approval.
