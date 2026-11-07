# Topic generation dependencies: November 7, 2026

Runtime revision: `ffcd0939`, initial guards `318c93d9`, based on `6f37b9e5`
([PR #254](https://github.com/AndreRobitaille/TwoRiversReporter/pull/254)).
Isolated checkout, Ruby 4.0.9, Rails 8.1.4.1, PostgreSQL 18.6, synthetic records
and deterministic providers. Execution results are recorded below.

## Requirements and scope

Parent [#234](https://github.com/AndreRobitaille/TwoRiversReporter/issues/234),
[#236](https://github.com/AndreRobitaille/TwoRiversReporter/issues/236), the
[evidence and correction contract](../superpowers/specs/2026-11-07-council-accountability-design.md#evidence-validation-and-correction-contract)
and [pilot implementation contract](../superpowers/plans/2026-11-07-council-evidence-pilot.md)
require preserved evidence, correction propagation, rejection of stale work and
reuse of unchanged analysis. Acceptance was derived from those requirements:
known-invalid prior analysis must not become new evidence; changed dependencies
must stop an in-flight result; delayed work must not replace a newer result;
identical completed topic stages must make no further provider calls.

This slice adds dependency receipts and checks to existing shared topic-summary
and full-briefing generation. It filters known-stale prior analyses from new
briefing and description input, and known-stale meeting item details from topic
context. It does not withdraw existing resident prose or complete #236.

## Behavior and cost

`Topics::GenerationEvidence` hashes the effective context and retrieval query,
eligible topic-linked knowledge candidates, prompt instructions/system role/tier,
resolved model names and committee context. The code policy version must change
when generation/retrieval/context policy changes. Neutral motion references
(event, observation, effective decision ID and retained source references) remain
in the receipt; private knowledge bodies, prompt text and review actor/reason do
not. A receipt identifies dependencies, not factual approval.

`Topics::GenerateSummary` serves both the ordinary meeting job and operator
reanalysis. Both callers establish deterministic continuity before capturing
topic dependencies, so a later continuity update does not immediately invalidate
new work. It reuses an identical completed topic stage before retrieval or
analysis, checks dependencies after retrieval and analysis, then checks again
before saving. Full briefing checks for reuse before constructing either provider,
including the embedding provider. The final check and output write hold the topic
lock; an expected output ID/timestamp prevents delayed workers from replacing a
newer completed result even when their inputs match. Rejected results do not
update impact or enqueue image generation.

Known source identity/version changes and source deletion remove old analysis
from future inputs while retaining its stored history. A replacement document
at the same URL does not substitute for the removed ID. Effective decision
identity changes invalidate dependent analysis even when document bytes agree.
Approved knowledge withdrawal and prompt changes also invalidate reuse and stop
in-flight work. Prior analyses are checked before the description headline cap.

No new paid path, schedule, automatic history rewrite or template population is
introduced. The existing whole-meeting analysis and topic-extraction stages are
outside this cache. A repeated full meeting job still calls its upstream meeting
provider; its unchanged topic stage reuses. Concurrent duplicate jobs can still
dispatch twice before one wins publication. Source-wide reservations, spending
and retry limits remain #238 work before new paid council processing is enabled.

## Behavioral verification

| Workflow / variant | Actual boundary and result | Limits |
| --- | --- | --- |
| BG-02 → BG-04, two distinct meetings | Synthetic download/text publication → real meeting job → two distinct topic analyses → full briefing. Replacing one source removes only its old analysis and item details from the next provider input; the unrelated claim remains. Stored prior analyses remain unchanged. | Provider transport is deterministic; prepared text pages, not PDF/OCR accuracy. |
| BG-04, reuse | Completed full briefing reruns with provider factories forbidden. Output attributes/timestamp remain identical. Repeated full meeting job calls only its upstream meeting analysis, with no topic retrieval/analysis/render. | Serial completed-stage reuse; not concurrent dispatch coalescing or whole-pipeline zero cost. |
| BG-04, changed during work | Source replacement during analysis prevents rendering; replacement during rendering prevents publication. Previous briefing and impact survive without image follow-up. | Controlled interleaving, not an all-writers database serialization proof. |
| BG-02 → BG-04, identity review | Real vote/attendance jobs and continuity establish an observation and topic event. Internal reviewed unassignment keeps the raw receipt but removes the dependent prior analysis from new briefing input. Current neutral reference has no decision ID and no private review metadata. | Synthetic identity correction; no semantic validation or public correction UI. |
| BG-04, operator path | Real operator reanalysis/extraction relinks the topic. A source replacement during topic rendering preserves the old summary and excludes it from the subsequent briefing input. | No real paid provider or production reanalysis. |
| BG-04, removed source | A valid headline first reaches description generation. Deleting its document and creating another at the same URL removes that headline and prior briefing analysis; the original artifact remains retained. | Existing descriptions are not automatically withdrawn. |
| BG-04, knowledge/prompt changes | Approved knowledge withdrawal stops output; private input text is absent from the receipt. Changed prompt settings defeat reuse, and another revision during analysis stops rendering/publication. | Knowledge ingestion/chunk synchronization is separate. |
| BG-04, delayed output | A nested later worker completes while the earlier result is rendering. Fresh reads retain the newer briefing and summary, including their distinct generated content and timestamps. | Deterministic overlap; no claim of multi-process dispatch deduplication. |

The tests execute the actual jobs/services and later persisted reads, replacing
only external transports/providers. They introduce no civic conclusions. No new
visible control, authorization rule or browser boundary changes in this slice.

## Execution record

Commands use the permanent shared bundle, Ruby 4.0.9 PATH,
`DATABASE_URL=postgresql:///trr_council_topic_generation_test`, and
`PARALLEL_WORKERS=1`. Tests and fault experiments run serially against that local
database. Development eager loading and `SELECT 1` passed before test setup.

The first preimplementation run reproduced stale publication and missing reuse,
but also had fixture/receipt errors; it is not a clean defect-detection baseline.
During expansion, a nested Minitest stub and the retained-version association
name were corrected in the tests. The passing baseline before deliberate faults
was **13 tests, 76 assertions, no failures/errors/skips**.

The expanded targeted command ran the new test file plus
`summarize_meeting_job_test.rb`, `generate_topic_briefing_job_test.rb`,
`meeting_reanalysis_service_test.rb`, `generate_description_job_test.rb`,
`summary_context_builder_test.rb`, `recent_item_details_builder_test.rb` and
`minutes/topic_evidence_test.rb`. Its initial **108 tests, 429 assertions** passed;
the later 115-test run had the retained-version fixture error above. The corrected
13-test file then passed before and after the delayed-output test refinement.

Fourteen isolated faults each caused exactly one intended assertion failure, no
errors/skips. Each file was restored exactly, and the same filtered test rerun
to green before the next fault. These use
`bin/rails test test/jobs/topics/generation_evidence_test.rb -i /<filter>/`.

| Bounded fault | Filter | Assertions at failure / after restoration |
| --- | --- | --- |
| Disable completed briefing reuse | `completed_briefing_reuses` | 2 / 2; forbidden provider construction |
| Disable completed topic-summary reuse | `repeated_full_meeting` | 1 / 2; extra topic retrieval/analysis/render |
| Omit the post-analysis dependency check | `source_change_during_briefing_analysis` | 6 / 8; stale analysis reaches rendering |
| Omit the final briefing dependency check | `source_change_during_rendering` | 1 / 1; old briefing/timestamp is overwritten |
| Omit the final topic-summary dependency check | `operator_reanalysis_also` | 4 / 6; operator path overwrites retained analysis |
| Ignore a prior summary's dependency mismatch | `reviewed_decision_withdrawal` | 5 / 11; invalidated interpretation reaches new briefing input |
| Omit knowledge candidates from the fingerprint | `withdrawn_knowledge` | 7 / 8; withdrawn context still reaches rendering |
| Omit prompt settings from the fingerprint | `changed_prompt_settings` | 2 / 6; changed prompt incorrectly reuses old work |
| Omit expected briefing output ID/timestamp | `delayed_briefing` | 2 / 2; delayed result replaces newer content |
| Omit expected summary output ID/timestamp | `delayed_topic_summary` | 2 / 2; delayed result replaces newer content |
| Bypass canonical citation copying | `citations/pipeline_test.rb`, `PDF-only_recap` | 12 / 22; invented/unknown references fail the exact retained-reference assertion |
| Move operator continuity after summary generation | `operator_reanalysis_establishes` | 1 / 3; new completed summary has stale dependencies |
| Omit ordinary meeting continuity before summary generation | `admin/offline_transcript_pipeline_test.rb`, `real_uploaded_transcript` | 169 / 326; otherwise identical reanalysis buys a second topic analysis |
| Drop one notified applicant from the captured email batch | `application_notification_timeline_test.rb`, `failed_delivery_rolls_back` | 6 / 10; unordered identity comparison still detects the missing applicant |

The first full suite at `318c93d9` ran **2,295 tests, 14,042 assertions, three
failures, seven errors and one existing skip**. The failures exposed a real stage
ordering problem: operator reanalysis updated continuity after summarization,
immediately invalidating its new receipt. Both ordinary processing and operator
reanalysis now establish deterministic continuity first. The offline transcript
journey preserves both distinct analyses and their closing evidence, while
expecting one topic analysis per topic instead of the former duplicate call.
It also asserts that each completed summary still has current dependencies.

Seven citation-pipeline cases invoked removed private job helpers. They now run
the actual shared summary service with deterministic provider responses, keeping
all exact citation, canary, persisted-data and API checks. A separate notification
test assumed an order between identical creation timestamps. Its assertions now
compare the same exact recipient identities without imposing a delivery order;
the application specification requires a complete batch, not tied-row ordering.
Notification runtime behavior and external delivery are unchanged.

After the ordering and citation fixes, the expanded targeted suite added
`admin/offline_transcript_pipeline_test.rb`, `citations/pipeline_test.rb` and
`application_notification_timeline_test.rb`: **130 tests, 1,249 assertions, no
failures/errors/skips**. After adding the fresh-operator regression, the new tests
plus transcript and notification journeys passed **19 tests, 680 assertions**.
The fourteen fault/restoration pairs then passed.

At `ffcd0939`, `bin/rails test --seed 48513` (the original failing seed) passed
**2,296 tests, 14,507 assertions, no failures/errors**, with one existing PromptRun
fixture skip. `bin/rubocop` passed **675 files** with no offenses. Three changed
Markdown files passed **106 local link/anchor checks** and balanced fences;
`git diff --check` passed. Full `bin/rails test:system` passed **23 browser
journeys, 779 assertions, no failures/errors/skips**, using local Chrome
157.0.8103.38 and its matching driver. The transcript journey includes actual
upload, queued processing, status, persisted evidence and later resident/source
navigation. Its provider assertions run once per topic because the second
analysis is now reused; the exact retained citation and later page checks remain.

## Remaining boundaries

Stored public briefing/description prose, meeting recaps, metadata, search and
images still need dependency-aware withdrawal. Legacy analysis without a receipt
retains existing behavior unless its source catalog proves a known change;
absence of a receipt is unknown provenance, not approval. No backfill invents a
receipt for historical output. Generic source writers do not all hold the topic
lock, so a source mutation after the final dependency check remains a separate
atomic invalidation boundary. Knowledge source body edits are fingerprinted, but
asynchronous source-to-chunk freshness is not solved here. Interim briefing and
description publication guards remain separate from this full-briefing scope.

No paid AI, production access, data copy/sync/backfill, GitHub merge or deployment
was performed. The original checkout and preceding branches remain preserved.
