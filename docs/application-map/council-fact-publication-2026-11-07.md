# Minutes fact publication: November 7, 2026

Application revision: `589fb17c`, on extraction foundation `88556acf` (PR #248),
source-artifact PR #247 and planning PR #246. Isolated local checkout, Ruby 4.0.9,
Rails 8.1.4.1, PostgreSQL 18.6 and synthetic test database/storage. Original
checkout, local development data and production were preserved.

## Requirements and implementation boundary

Parent [#234](https://github.com/AndreRobitaille/TwoRiversReporter/issues/234),
[#236](https://github.com/AndreRobitaille/TwoRiversReporter/issues/236), the
[design's incremental processing contract](../superpowers/specs/2026-11-07-council-accountability-design.md),
and the [pilot contract](../superpowers/plans/2026-11-07-council-evidence-pilot.md)
require source-compatible facts, stale-work rejection, inspectable known votes,
reusable shared analysis and code for deterministic reconciliation. Acceptance
was established before the implementation: stage both outputs against pinned
input, retain the previous pair until both current stages complete, and publish
votes/attendance together. Never label the old roll call as evidence for a new
source's derived absences.

The initial job-boundary test failed against the prior jobs: after votes alone,
projected motions already changed from the prior action to the new opening and
closing actions. One run, one assertion, one failure, zero errors/skips. This
was a reproduced coordination defect, separate from the later fault experiments.

`MinutesExtraction` retains exact source text, source/extractor identity,
prompt/model/rule manifest, kind, attempts and parsed output. Retained artifacts
link to `MeetingDocumentTextVersion`; legacy text is explicitly marked
`legacy_text_projection`. A completed stage remains extracted evidence, not
approved or independently validated interpretation. A known vote stage is
inspectable before attendance succeeds.

`MinutesPublication` references a compatible pair plus deterministic projection
context. Meeting and document locks cover current-input checks, replacement of
both display tables, membership reconciliation and current-pointer publication.
Unchanged work preserves projection row IDs; changed inputs can still replace
legacy `Motion` IDs. Stable decision identity is the next separate boundary.

Explicit votes and absences inferred from that same roll call are distinguished
by `Vote#evidence_basis`; old records default to `legacy`. An unsupported value
is retained in failed parsed output and is not converted to an abstention.
Identity resolution remains the existing Member/Alias system. Raw attribution
is retained even when a person is merged into a canonical member.

## Cost and recovery boundary

Stage keys include source and relevant prompt/model/rule inputs. Votes include
agenda context; attendance does not rerun just because agenda context changes.
The provider receives the pinned template represented in the manifest. Meeting
date/committee changes reproject existing stages with code. Atomic claims suppress
concurrent duplicates; completed input does not call the provider again.

Global prompt/model edits alone do not make completed evidence stale or trigger
nightly historical extraction. Default jobs reuse a compatible completed stage.
An explicit `refresh: true` job can extract for changed settings; it cannot bypass
completed-input caching, attempt limits or uncertain-request guards. Date/committee
repairs also reuse compatible stages after settings change. A new test reproduced
the initial unwanted nightly eligibility (one run/assertion/failure, no errors)
before this separation was implemented. A malformed voting-roster entry was also
reproduced as incorrectly completed (one run/assertion/failure, no errors); the
validator now rejects that unsupported shape before it can become a person name.

Invalid JSON/shape/value output permits at most two attempts for that input.
Provider exceptions are conservatively `uncertain`: an already-billed request
must not be automatically repeated. An unfinished `running` claim also does not
expire into another paid request. Recovery/review of uncertain or interrupted
requests remains part of #238's durable accounting workflow. This slice does
not implement request/batch/daily dollar reservations or authorize paid runs.

Both minutes methods previously silently truncated text at 50,000 characters.
They now preserve allowed input completely and reject larger input before
transport. This character ceiling preserves the previous maximum input boundary;
it is not a token-price calculation or a spending limit. Oversized sources need
a reviewed partition. No campaign source generation was enabled.

The existing nightly repair sweep compares current inputs/stages, retries only
eligible failed extraction, and recovers missed publication/PDF triggers. It
leaves already-completed, untouched legacy rows alone instead of starting an
implicit backfill. It adds no hourly or other scheduler. Old structured motions
are omitted from summary grounding while current fact publication is pending.

## Executed workflow evidence

| Workflow / variant | Exercised boundary and result | Limits |
| --- | --- | --- |
| BG-02, both arrival orders | Retained synthetic source → real jobs with deterministic providers → independent stage rows → atomic publication → fresh model reads. Votes first and attendance first both retain the prior pair until complete; distinct opening/closing decisions survive. | Provider semantics simulated; not real extraction accuracy. |
| BG-02, real concurrency | Separate PostgreSQL connections, committed input, overlapping vote/attendance jobs and a duplicate vote job held during provider work. One provider call per stage, two extraction rows, one publication, terminal processing statuses and exact known people/votes/attendance on a subsequent uncached read. | Real threads/DB locks; deterministic provider transport, not separate host/load testing. |
| BG-02, late/revised work | New source and both new stages complete during an older vote request. Late output remains retained without replacing the new pair. New bytes awaiting matching text dispatch no AI. | Deterministic interleaving. |
| BG-02, failures | Second-motion persistence failure rolls back votes, attendance and pointer together. Both completed stages survive; retry publishes without another provider call. Unsupported values stop; two invalid attempts exhaust eligibility. Provider timeout is uncertain and is not retried. | Persistence/provider faults simulated. |
| BG-02, reuse/dependencies | Unchanged runs preserve row identities and make no calls. Agenda changes require only votes; global prompt edits require neither stage. Date correction reprojects cached stages without a call even after prompt edits. Explicit refresh extracts only the changed stage. Provider uses the manifest's pinned template after a database prompt edit. | Same application/source stage behavior, not a complete global AI cache. |
| BG-02, nightly | Votes staged with attendance missing queues only attendance; no premature summary repair. A replaced PDF with a missed parser trigger queues analysis, not AI over old text. Existing untouched legacy completion markers remain respected. | Existing nightly service executed locally; no production scheduler inspected or changed. |
| RES-10, later HTTP reads | Signed-in active member opens the real member route after initial publication, after revised votes alone, and after revised attendance. Initial/prior page shows the matching No/100% pair; final page shows the new action with Absent/0%, correct meeting link and no old action. | HTTP/template journey, not browser interaction; no new visible controls. Existing access/gating behavior remains unchanged. |
| ADM-10 / BG-02, identity | Member merge moves current votes/attendance, retains raw attribution, survives cached replay and a later agenda-triggered re-extraction through aliases. | Explicit correction conflicts and stable decision review are still separate work. |
| BG-01/RES-08, removal | Source/meeting removal leaves retained stage text/output and publication references inspectable; no replacement source is substituted. Duplicate cleanup treats retained fact history as useful content. | Source-availability presentation remains unimplemented. |
| BG-02, full provider input | Real `Ai::OpenAiService` methods with deterministic transport retain the near-limit closing action in both messages and persisted PromptRun input. Oversized calls never reach transport. | No paid request and no model accuracy measurement. |

The first parallel test's observer reused Rails' query cache from before worker
commits. SQL showed a successful publication, so that was a test-observation
error, not a demonstrated product failure. The final observer uses an uncached
read to represent a subsequent request; all publication/call/count assertions
remain. Synthetic rows are removed by their own IDs after the concurrency test.

## Runner and defect detection

Commands use the shared permanent Ruby bundle, explicit Ruby 4.0.9 PATH,
`DATABASE_URL=postgresql:///trr_council_facts_test`, and `PARALLEL_WORKERS=1`.
Final application and behavioral verification ran serially on that database.

- Isolated migration up and down/up succeeded. `bin/rubocop -A db/schema.rb`
  restored repository formatting; inspected diff contains only the two tables,
  meeting pointer, vote evidence basis, indexes/foreign keys and schema revision.
- Clean focused baseline: `bin/rails test test/jobs/minutes test/integration/minutes_publication_journey_test.rb test/services/ai/minutes_input_test.rb test/jobs/extract_votes_job_test.rb test/jobs/extract_committee_members_job_test.rb test/services/scrapers/pipeline_repair_sweep_test.rb`:
  107 runs, 378 assertions, zero failures/errors/skips. The runner discovers the
  real concurrency test as well as the HTTP and deterministic job journeys.
- Existing job component tests now supply the counterpart through its real job
  with a deterministic provider, retaining their membership authority, alias,
  agenda matching and rollback checks. They do not bypass stage/publication
  code. Cross-stage behavior has separate journey assertions.
- Fault 1: remove the unchanged-publication fingerprint guard. Run
  `test/jobs/minutes/fact_publication_test.rb -n /unchanged_stages/`: one run,
  one assertion, one failure, no errors/skips. Unchanged replay replaced Motion
  IDs. Restore the guard from the clean baseline.
- Fault 2: accept `unknown` as a supported vote value. Run the same file with
  `-n /invalid_output_is_bounded/`: one run, one assertion, one failure,
  no errors/skips. The invalid response was incorrectly cached as completed,
  producing one call instead of the expected two bounded failed attempts.
  Restore strict values from the clean baseline. Neither fault was a syntax/boot failure.
- Fault 3: omit source-version identity from the extraction source manifest.
  Run `test/integration/minutes_publication_journey_test.rb`: one run,
  17 assertions, one failure, no errors/skips. The later HTTP page incorrectly
  retained the old park action instead of the revised library action. Restore
  source identity from the clean baseline.
- Fault 4 / review follow-up: a worker can finish its output before the
  counterpart publishes, then write a late `staged` marker over `processed`.
  A scheduling-only hook reproduced this in the real pipeline, preserving all
  persistence and stamp logic. The fix keeps a published stage's terminal status.
  Removing that guard after a clean baseline makes `-n /late_completion_status/`
  fail (one run/assertion/failure, no errors/skips). Restored coverage also proves
  the existing nightly sweep queues the missing summary without either extraction.
- All faults were restored before the final `bin/rails test`: 2,226 runs,
  13,932 assertions, zero failures/errors, one existing PromptRun polymorphic-source
  test skip because no meeting fixture exists. An earlier full run exposed the
  old truncation expectation; it was replaced by complete-input and oversize
  rejection coverage for both provider methods.
- `bin/rubocop`: 653 files, no offenses. `git diff --check` passed. Local
  documentation checking covered five Markdown files, 106 links/anchors and
  balanced code fences. No local browser suite was run; the changed boundary is
  jobs/database publication and subsequent HTTP reads, with no new controls.

## Remaining scope

#236 remains open for stable decision identities and evidence locations,
correction/review history, dependent-claim withdrawal and broader identity/merge
conflicts. This slice does not certify legacy data or perform semantic source
validation. Legacy display queries still read mutable rows; a fully version-bound
read model and service-period denominators belong to the subsequent record work.
The HTTP evidence covers requests before/after publication, not a reader whose
multiple queries straddle a concurrent commit. Source availability, campaign
intake and new member-page sections remain separate. #238's dollar ledger and
controlled uncertain-request recovery must precede campaign paid generation.
No paid AI, production access, database copying/sync/backfill, merge or deployment
occurred. The goal remains parent #234, with the first working record through
#240 as its next major checkpoint.
