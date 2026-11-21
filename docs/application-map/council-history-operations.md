# Council history and recurring comparisons

[Issue 245](https://github.com/AndreRobitaille/TwoRiversReporter/issues/245) defines the historical window and pilot. [Issue 238](https://github.com/AndreRobitaille/TwoRiversReporter/issues/238) covers new evidence. Use the [shared release procedure](../SHARED_HOST_DEPLOYMENT.md) and [production playbook](../../.claude/skills/deploying/SKILL.md) for remote commands. Run the tasks below inside the deployed image. Preserve inventories, detailed costs and operator checkpoints privately.

## Reviewed material and activation

Populate changed prompts from the deployed revision. Supply the destination administrator in `ACTOR_ID`. Transfer the reviewed exports using the release session and verify their digests. Set `CAMPAIGN_FILE`, `COMPARISON_FILE` and `REVIEWED_FACTS` to the corresponding private files. Run `bin/rails council_profiles:import_reviewed`. The oath source is the May 6, 2024 Council packet, page 5. Campaign passages must match the supplied source, while comparisons require matching statements and meeting evidence. Re-run the import when additional source records become available.

`bin/rails council_profiles:enable_nightly` activates the standing calendar-month comparison allowance. Reconciliation runs from the existing 11 p.m. discovery job. It copies the approved policy into the next month when necessary. `bin/rails council_profiles:disable_nightly` revokes renewal. Use `bin/rails council_profiles:spend_report` to inspect reservations including retries and unknown attempts.

## Historical run

1. Run `bin/rails backfill:preview` with `FROM=2024-04-16 THROUGH=2025-07-06`. It reads the official index and the destination records. An optional `BODY` filters the listing title. The estimate reports its sample sizes and the stages whose workload still depends on new evidence.
2. After the production desktop profile checks, use `PHASE=pilot BODY=council` with the same dates and `bin/rails backfill:scoped`. This selects the October 28 and May 5 minutes. Set `PILOT_REUSE_URL` to the official minutes URL of one additional meeting in the reviewed facts when needed. Check the motions, votes, and resident pages against the actual minutes. Replay with the same arguments and compare `CouncilHistoryRequest.count` and receipts before continuing.
3. Use `PHASE=full` on small date ranges, first with `BODY=council`, then with `SKIP_COUNCIL=1` for the remaining bodies. The task resumes from saved minutes extractions, summaries, triage and comparison decisions. Console results identify the meeting and unresolved stages. Successful token receipts use the checked model rates. An unknown request retains its full reservation. Both phases share the one-time historical limit across dates and restarts. After the batches, run `bin/rails backfill:finish_briefings` for the historical dates. It considers each missing full topic briefing once and preserves the newer archive.
4. Preview the later period beginning July 7, 2025. For a demonstrated gap with saved minutes, supply one `MEETING_ID` and a comma-separated `STAGES` selection to `bin/rails backfill:repair_saved`. Valid stages are `facts`, `topics`, `summaries` and `comparisons`. Inspect the result on a subsequent request. Preserve conflicting source versions for review.
5. Run `bin/rails backfill:publish_coverage` and inspect the Council member pages. The disclosure shows the official calendar period and meeting-specific source gaps. Subsequent nightly reconciliation rechecks recent city listings and the archived meeting records.

## Behavioral verification

RES-10/11 cover the voter journey. BG-01/02/08/09 cover discovery, shared meeting processing and campaign comparisons. `council_history_batch_test` exercises the PDF-backed minutes stages with simulated transport, persisted votes, scope and replay. `council_history_execution_test` checks pre-dispatch admission, uncertain attempts and both historical ceilings. `council_live_action_budget_test` checks recurring admission, renewal, revocation, new work and unchanged evidence. `member_council_attendance_test` checks the published source-gap disclosure on a subsequent resident request. Actual production receipts, dates and checks belong to the operator's run record.

The mobile vote-filter journey checks the returned pagination link for the selected topic and decision type before reading the matching count. The 26 test votes match both before and after the request. It also verifies that Back returns to the same filtered page after opening the official meeting.
