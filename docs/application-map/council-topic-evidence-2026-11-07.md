# Retained topic motion evidence: November 7, 2026

Runtime revision: `8d5625e6`, based on `c2f9a7a4`
([PR #252](https://github.com/AndreRobitaille/TwoRiversReporter/pull/252)).
Additional downstream-withdrawal assertions: `04eb6e66` (test-only change).
Isolated checkout, Ruby 4.0.9, Rails 8.1.4.1, PostgreSQL 18.6 and synthetic data.

## Requirements and scope

Parent [#234](https://github.com/AndreRobitaille/TwoRiversReporter/issues/234),
[#236](https://github.com/AndreRobitaille/TwoRiversReporter/issues/236), the
[correction contract](../superpowers/specs/2026-11-07-council-accountability-design.md#evidence-validation-and-correction-contract)
and [pilot](../superpowers/plans/2026-11-07-council-evidence-pilot.md) require stable
evidence links, preservation through replay/corrections and no silent substitution
after source changes. The [Topic Lifecycle contract](../DEVELOPMENT_PLAN.md#topic-lifecycle)
requires evidence for a resolution signal. A formal decision is not proof of
project completion; a member's action, Council outcome and issue outcome remain
separate. Acceptance was derived from these requirements before implementation.

This slice migrates the **motion-outcome event reference and its future summary
inputs**. Existing topic lifecycle classification rules are unchanged. It adds
no public/admin control, profile section, factual approval or generation trigger.

## Implemented behavior

`TopicStatusEvent#decision_observation` pins the immutable extracted observation
with a foreign key. Its exact text version, passage checks and raw attribution
remain available after display Motion replacement. `council_decision` follows the
effective identity assignment; a reviewed withdrawal removes that effective link
while leaving the event's original evidence and audit references intact.

Continuity records each decision separately, including multiple motions with the
same date, topic and result. Reprojection reuses the event by observation and
repairs its canonical meeting date. A new observation creates a new historical
event. Its original `source_ref.motion_id` remains historical metadata; the
retained observation supplies the durable link. Once pinned, ordinary model
writes cannot retarget the evidence or replace that source reference.

The producer holds a topic lock through reads and writes so concurrent jobs
cannot create duplicate events. Topic merges lock both topics in ID order and
reload them before moving associations; an in-flight event commits before its
history is transferred. An exact live legacy motion/outcome reference
can acquire an observation during ordinary continuity processing. A missing
legacy motion stays unpinned; no fuzzy recovery or historical backfill runs.

`with_current_evidence` checks the current published vote stage, live display
motion, current topic/agenda link, outcome and canonical meeting date. It filters
motion events before the existing context limits in `SummaryContextBuilder` and
`GenerateTopicBriefingJob`. Topic merges preserve both event histories; the
current query includes each motion once. Other event types keep their existing
behavior. These checks establish reference consistency, not semantic accuracy;
the observation remains `extracted` even when its passage is located.

Both summary contexts carry the event ID and a neutral motion reference:
observation ID, opaque effective decision ID, source key, text-version ID,
source provenance and extracted status. These keep distinct decisions traceable
through the provider boundary without copying private review actors or reasons.
They are internal provenance identifiers, not public source citations. Existing
citation resolution and its unavailable/changed-source behavior remain unchanged.

Ordinary document removal leaves the exact retained artifact and source URL
available without pretending the live document still exists. Removing a topic's
agenda link removes its motion event from current context while retaining the
historical event. The migration adds a nullable reference and indexes; it does
not rewrite legacy records. Rollback refuses to discard any pinned event links.

## Behavioral verification

| Workflow / variant | Boundary and assertions | Limits |
| --- | --- | --- |
| BG-02 → BG-04, distinct decisions | Real synthetic source download/text publication → deterministic vote/attendance providers → current Motion rows → continuity events. Two same-date passed motions retain two distinct observation and decision identities with both original excerpts. | Synthetic provider answers; no real extraction accuracy claim. |
| BG-02 → BG-04, replay/date correction | Changing the canonical meeting date excludes the old date from current context. Code-only reprojection replaces Motion rows, reuses the same event/observation/decision and repairs the event date; providers are forbidden. | Full service-period and appearance-date reconciliation is separate. |
| BG-04, changed source | A revised two-motion extraction changes one outcome to failed. Both current motions remain, three historical resolution events survive, and only the one current passed-motion event reaches per-meeting and rolling briefing context. The actual briefing job receives deterministic analysis/render responses and persists a later-readable record. | The existing classification of a resolution signal is unchanged. |
| ADM-10 / BG-04, identity correction | Both summary payloads first contain the allowed identity. Actual authorized correction withdraws it; fresh event and both later payloads have no effective decision, while the original source observation, identity basis and correction receipt remain. | Identity correspondence only; not vote-value approval. |
| BG-04, downstream reference/privacy boundary | A real identity review precedes per-meeting context construction and the deterministic briefing job. Both inputs retain all distinct event/observation/decision IDs, the exact shared source/text version and extracted provenance; reviewer email and private reason are absent. | The reference object does not supply a new public citation or approval. |
| ADM-06/07 / BG-04, topic merge | Actual topic merge moves all four events from two histories, preserves their IDs and yields two distinct current decisions. Reconciliation adds no duplicates. | Existing merge authorization/UI is unchanged; no new HTTP surface. |
| BG-04, legacy/unlinked evidence | Exact live legacy reference is adopted; orphaned reference remains unpinned and absent from both summary inputs. Removing and restoring a topic link removes and restores its current evidence. | Missing historical Motion rows cannot be reconstructed from a date or description. |
| RES-08 / BG-01, source retention | Actual document deletion preserves both exact source excerpts, attached retained artifact and original URL; the live document pointer is nil. | Direct deletion of a meeting with topic appearances hits an existing agenda-item foreign key. That variant is not claimed verified or changed here. |
| BG-04, concurrency | Two real PostgreSQL connections overlap before event creation. A second continuity call waits and both finish with one event. An overlapping topic merge waits before transfer, succeeds and retains the event on the survivor. | Controlled thread scheduling, not distributed load testing. |

No browser control or rendered field changes. Existing topic/member HTTP and
browser regressions remain compatibility coverage; this slice's risky boundary
is source publication → retained event → later context/provider/persisted read.

## Execution record

Commands use the permanent shared bundle, explicit Ruby 4.0.9 PATH,
`DATABASE_URL=postgresql:///trr_council_topic_evidence_test` and `PARALLEL_WORKERS=1`.
Database work and tests run serially. Only source transport, providers and
knowledge retrieval are simulated; publication, identity review, topic merge,
continuity, database locking and briefing persistence are real application code.
Text publication receives prepared synthetic pages; this slice does not repeat
the earlier text-version slice's native PDF/OCR parser verification.

- Initial tests against PR #252: two tests, two assertions, two intended failures,
  no errors/skips. Distinct decisions collapsed into one event, and an event had
  no retained observation independent of its display Motion.
- A later boundary test found missing event identities in both summary payloads:
  one test, two assertions, one intended failure and no errors/skips. The neutral
  reference object now carries the actual retained identities/provenance.
- Focused baseline: `bin/rails test test/jobs/minutes/topic_evidence_test.rb test/services/topics/parallel_continuity_test.rb test/services/topics/continuity_service_test.rb test/services/topics/summary_context_builder_test.rb test/jobs/topics/generate_topic_briefing_job_test.rb test/services/topics/merge_service_test.rb`:
  **57 tests, 262 assertions, zero failures/errors/skips** at `04eb6e66`.
- The expanded checks exposed inherited ordering in the grouped current-event
  subquery; it now removes caller order/limits and selects only the grouped ID.
  Tests also stopped assuming insertion order for events with equal timestamps;
  they compare exact identities and source contents independently of row order.
- A full run exposed a query-cached lock-status observation in the concurrency
  harness, causing one timeout. Lock-status polling now explicitly bypasses the
  query cache. This was a harness failure, not evidence of a product deadlock.
- A separate overlapping-merge regression reproduced a real failure: the merge
  missed an uncommitted event and then failed its topic/event foreign key. The
  two concurrency tests reached four assertions and one intended failure, with
  no errors/skips. Ordered topic locks now preserve the event before transfer.
- Migration up and a legacy-only down/up passed. A synthetic preexisting event
  retained every original attribute, remained unpinned and was reused by ordinary
  continuity. The fixture was removed afterward. A pinned-event test proves the
  rollback guard. `bin/rubocop -A db/schema.rb` ran after migration; the inspected
  diff contains only the nullable reference, indexes, foreign key and revision.
- `bin/rubocop`: 670 files, no offenses.

After the clean focused baseline, each bounded fault below reached its intended
assertion failure and was restored exactly. Each run executed one test with one
failure and zero errors/skips. Filters use `bin/rails test <file> -i <filter>`.

| Fault | Test/filter | Assertions and observed failure |
| --- | --- | --- |
| Collapse events sharing a timestamp | `topic_evidence_test.rb`, `/distinct_decisions/` | One assertion; two required events collapse to one. |
| Omit the retained observation pointer | `topic_evidence_test.rb`, `/reprojection_preserves/` | One assertion; the published event has no durable source observation. |
| Remove current-evidence filtering from per-meeting context | `topic_evidence_test.rb`, `/source_revision_retains/` | Ten assertions; superseded event notes enter the new summary input. Allowed prior content is established first. |
| Remove current-evidence filtering from rolling briefing context | `topic_evidence_test.rb`, `/source_revision_retains/` | Twelve assertions; superseded event notes reach the actual deterministic briefing provider. |
| Ignore the canonical event date | `topic_evidence_test.rb`, `/reprojection_preserves/` | Three assertions; the stale date remains current before repair. |
| Remove the topic lock | `parallel_continuity_test.rb`, `/concurrent_continuity/` | One assertion; overlapping connections commit two events for one motion. |
| Allow a pinned event to switch observations | `topic_evidence_test.rb`, `/retained_event_evidence_cannot/` | One assertion; retargeting succeeds instead of preserving the original evidence. |
| Replace the retained source key in downstream provenance | `topic_evidence_test.rb`, `/summary_boundaries/` | Five assertions; the provider-bound reference no longer identifies the actual retained source. |
| Remove ordered topic locks from merge | `parallel_continuity_test.rb`, `/topic_merge_waits/` | One assertion; an overlapping merge returns a foreign-key failure instead of transferring the committed event. |
| Put the original extracted identity into context instead of its effective assignment | `topic_evidence_test.rb`, `/identity_corrections_change/` | Eleven assertions; a withdrawn identity remains in the later summary payload. Both allowed payloads are proved first. |

The first nine faults ran at `8d5625e6`; the final fault ran after the passing
13-assertion downstream-withdrawal test and was followed by the restored
57-test/262-assertion command above. Runtime files are identical at both revisions.

Restored full `bin/rails test` at `8d5625e6`: **2,276 tests, 14,335 assertions,
zero failures/errors**, one existing PromptRun fixture skip. The later test-only
change adds six assertions; no runtime behavior changed after that full run.
Four changed Markdown documents passed 109 local link/anchor checks and balanced
fence checks; `git diff --check` passed.

## Remaining boundaries

Already stored topic prose, metadata, cached summaries and dependent recurrence
signals do not yet have comprehensive dependency manifests or withdrawal here.
This slice filters future **motion-event context** only. A delayed existing
summary-generation job still needs the broader source/dependency publication
guard. No paid generation was run to refresh historical prose. Operator review
controls, factual corrections, motion/amendment relationships, profile claims
and #238's spending ledger remain follow-on work; #236 is not complete.

No paid AI, production access, database copying/sync/backfill, merge or deployment
was performed. Original checkout work and preceding PRs are preserved.
