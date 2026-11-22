# Combined council profile verification — November 8, 2026

The original integration below covers #293. The final bounded acceptance at the
end of this report covers the subsequent implementation through #305 and the
owner's scope correction in #307; its remaining boundaries supersede the earlier
work-in-progress list.

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

## Final bounded implementation acceptance

Resident question: what did these members promise, what meaningful work followed,
and what happened to the issue? This acceptance checks that task, rather than
requiring a complete reconstruction of every action. The scope rule is in
[AGENTS.md](../../AGENTS.md#choose-work-by-resident-value).

Checked revision: `567b814d63e190539a26a958a154d7657d9449e9`, which has no changes
under `app`, `config`, `db` or `test` since #304's `0157f06`. #305 supplies the
source acceptance; #307 changes documentation only. The already-passing #305 CI
therefore exercises the same application and tests: 2,651 application tests /
18,927 assertions (one skip), and 46 browser tests / 1,265 assertions.

| Bounded requirement | Evidence and conclusion |
| --- | --- |
| Readable real cohort records | The [cohort checks](council-cohort-readiness-2026-11-08.md) cover term selection, existing attendance, substantive votes, bottom pagination and peer navigation. The [source acceptance](council-source-acceptance-2026-11-08.md) covers the final real recommendation comparisons and exclusions. Six subsequent phone/desktop journeys repeated the corrected campaign cards, independent disclosures, source navigation and retained grant connections on all three real pages at 390px and 1280px. |
| Specific promises versus meaningful work | The real Airbnb comparison remains a negative reference: a rental-lighting ordinance does not establish action on a lottery or owner-occupancy proposal. Retained direct grant connections remain inspectable. Tests distinguish a losing proposal/vote, a Council result and an issue outcome, without a partial-history promise verdict. |
| One shared update/correction and unchanged reuse | The current targeted run exercises a no-new-vote update, a corrected source through publication and later reads, saved recap updates, saved attributed motions, direct/negative comparison reuse, unchanged accepted votes and zero extra requests/reservations on replay. Generic issue history remains separate from personal credit. |
| Existing access paths | The same run proves allowed reporting, gated exclusions and verified-Google/spoofed-crawler handling for recorded actions and issue updates. Existing unchanged intake, campaign, recommendation and formal-record access coverage remains in CI and the linked reports. This is not evidence of actual Google indexing. |

The final targeted command, with Ruby 4.0.9, `RAILS_ENV=test`, serial workers and
an isolated PostgreSQL test database, was:

```sh
bin/rails test test/integration/council_saved_issue_history_test.rb test/integration/council_saved_motion_actions_test.rb test/integration/council_issue_updates_test.rb test/integration/campaign_issue_evidence_test.rb test/integration/council_live_action_budget_test.rb test/integration/council_recorded_actions_test.rb
```

Result: **43 tests / 457 assertions, no failures, errors or skips**. Provider
transport is deterministic; synthetic positive cases remain in the test database.
The real preview uses retained civic data, not those fixtures. The six browser
journeys use the existing Capybara/Selenium script; they do not claim a new
provider-accuracy result. No implementation or assertions changed in this final
pass, so existing representative defect-detection evidence was reused rather
than repeating fault experiments. No application code change was needed.

Local editorial corrections remain separate from automatic recovery. The six
forum-passage corrections and the selected recommendation correction have retained
before/after records and reproduction scripts in the ignored source archive, for
replay in a later authorized environment. Two conflicting unelected-candidate
statements remain unpublished. Formal-case completeness and positive real-case
accuracy remain unverified; no clean-record claim is made. These documented gaps
do not require another discovery project before delivering the useful record.

Implementation acceptance is satisfied at this scope. The open stack is not
merged or deployed. Automatic code/security reviews for #301–#305 were declined
for review-usage limits; this remains an explicit review gap, not a code finding
or a successful review. The remaining operating handoff is the historical run
proposal under #245 and selection of the recurring allowance under #238.
No paid call, broad historical run, production operation, merge or deployment
was performed by this final acceptance pass.
