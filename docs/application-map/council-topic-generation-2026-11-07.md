# Topic generation dependencies: November 7, 2026

Final runtime revision: `b6b475a9`; initial guards `318c93d9`, ordering fix
`ffcd0939`, historical-validity fix `b0ebc775`; based on `6f37b9e5`
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

Historical validity is separate from exact generation-cache equality. A retained
analysis checks its original meeting, agenda anchors, background, knowledge and
event references. Additional meetings, knowledge or continuity events do not
erase supported history; retained dependency sets can remain valid within a
larger current set. Topic merges can move supported analysis to the surviving
topic without rewriting the original receipt. Prompt/settings changes still
invalidate generation reuse, but do not themselves invalidate historical facts.

`Topics::GenerateSummary` serves both the ordinary meeting job and operator
reanalysis. Both callers establish deterministic continuity before capturing
topic dependencies, so reanalysis can reuse the same completed topic stage.
It reuses an identical completed topic stage before retrieval or
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
| BG-04, supported history | Add four later meetings and additional knowledge after the first analysis. All five distinct analyses reach the briefing while raw context remains capped at three meetings. A separate topic merge retains the original supported analysis and receipt. | Added context is not proof that earlier evidence became invalid. |

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

## Review follow-up

Review of `69d8fa33` identified that full cache-key comparison incorrectly removed
supported historical analyses when later meetings changed topic metadata. Two
new cases first ran **two tests, three assertions, two intended failures and no
errors/skips**, reproducing ordinary history loss and topic-merge history loss.
`b0ebc775` separates retained evidence validity from generation reuse; `3193cce5`
adds explicit knowledge-withdrawal coverage with unchanged meeting sources.
The targeted pipeline/citation run passed **37 tests, 921 assertions**; the
expanded generation file then passed **17 tests, 92 assertions**.

Receipt-format and generation-policy versions are distinct. The generation key
still includes current prompt/model/policy settings. Historical checks retain
supported meeting/agenda/background/knowledge/event dependencies even as new
context is added, and exclude explicitly withdrawn dependencies. A fault that
restores full cache-key equality detects the history regression; ignoring only
historical knowledge validation detects the withdrawn-background regression.
The changed historical-validity meaning initially made the old operator-order
assertion insufficient. It now checks the actual provider input's established
last-seen date as well as the stored evidence and call count.

The follow-up fault runs again detected identity withdrawal, stale publication,
reuse and delayed-output defects. Two added faults bring the distinct total to
sixteen: restoring full cache equality fails the five-meeting history assertion
(two assertions at failure, four restored), and ignoring historical knowledge
dependencies fails the withdrawn-background assertion (three/four). After the
test refinement, moving operator continuity after generation fails the actual
provider-context date assertion (two/four). Every successful fault experiment
was restored and rerun to green without errors/skips.

Final `bin/rails test --seed 48513` at `b6b475a9` passed **2,299 tests,
14,520 assertions, no failures/errors**, with the same existing skip.
`bin/rubocop` again passed **675 files**. These results include the regression
identified in [the initial PR review](https://github.com/AndreRobitaille/TwoRiversReporter/pull/255#discussion_r4503746341);
the original `69d8fa33` CI/runtime checks passed before that review fix and are
not verification of the final revision.
Final `bin/rails test:system` at `b6b475a9` also passed **23 journeys, 779
assertions, no failures/errors/skips**, including transcript upload through later
resident/source navigation. The original checkout remains clean at `da8d2588`.

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
Existing summary/briefing rows remain mutable projections: successful generation
still replaces their previous output. This slice retains old output when work is
rejected or excluded from new context; it does not add an immutable narrative
archive.

No paid AI, production access, data copy/sync/backfill, GitHub merge or deployment
was performed. The original checkout and preceding branches remain preserved.
