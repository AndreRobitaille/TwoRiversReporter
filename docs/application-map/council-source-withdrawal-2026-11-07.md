# Document changes and stored briefings: November 7, 2026

Based on `fc440125` ([PR #256](https://github.com/AndreRobitaille/TwoRiversReporter/pull/256)).
Runtime revision: `5eefb13d`; subsequent transcript-test revision: `227f56a2`. Ruby 4.0.9,
Rails 8.1.4.1 and PostgreSQL 18.6; an isolated synthetic local database.

## Requirements and bounded acceptance

Parent [#234](https://github.com/AndreRobitaille/TwoRiversReporter/issues/234),
[#236](https://github.com/AndreRobitaille/TwoRiversReporter/issues/236), and the
[evidence/correction contract](../superpowers/specs/2026-11-07-council-accountability-design.md#evidence-validation-and-correction-contract)
require known-invalid dependent claims to be withdrawn before replacement prose
is ready. Retained evidence remains inspectable. A failed fetch does not erase
valid reporting, and a new document at the same URL is not the old evidence.
The [public access contract](../superpowers/specs/2026-07-24-tiered-public-access-design.md)
and [API contract](../read-only-api.md) apply to resident responses.

Acceptance was derived before implementation: committed document changes withdraw
only dependent stored briefings and illustrations; the source change, audit and
withdrawal are atomic; unchanged inputs, temporary transaction edits and failed
fetches keep valid analysis; missing documents cannot be silently substituted;
old motion facts cannot restore prose after their pinned source changed; first
publication and delayed outputs cannot evade withdrawal. No paid calls, automatic
regeneration dispatch or schedule is added.

## Implementation

`MeetingDocument` checks dependencies before transaction commit. This observes the
final document, page and attachment state, rather than an intermediate SHA update
or a temporarily empty page set. It covers ordinary model saves, destroys and
touches, including attachment replacement/purge and the existing download,
PDF/OCR text publication and transcript replacement paths.

`Topics::WithdrawSourceBriefings` finds retained source catalogs and motion
observations pinned to the changed document. A briefing may have an empty catalog
and still depend on minutes through a motion receipt. The service locks affected
topics, possible first-publication owners and event owners, then rechecks owners
without the query cache so topic merges cannot move a receipt outside the lock set.
It compares source snapshots and current motion receipts, withdraws unsupported
briefings and supersedes their illustrations in the source transaction.

The existing `AuditEvent` log records an automated method/version, original
document ID, changed/unavailable reason, retained catalog and motion receipt, and
final source snapshot (null for a deleted document). The actor is null and explicitly identified as automated in the admin audit log,
not a claimed human reviewer. The topic label remains readable. Motion receipts resolve to retained observations and
extraction source manifests. The original evidence and stored generated JSON are
preserved. Repeated checks of already withdrawn rows do not duplicate the audit.
The audit persists after an identical-input restoration or later full generation.

`GenerationEvidence` also checks the source pinned by each motion before accepting
a generation receipt or reusing supported historical summaries. One snapshot per
document is shared across its dependent motions within the check. Merely finding
another unprocessed minutes URL does not invalidate a still-available pinned
source. This check does not promote extracted claims to validated facts.

An identical uploaded SRT with the same URL, provenance and parsed text reuses
its current document ID, preserving dependent receipts. A failed replacement
rolls back the old document deletion and leaves its briefing supported.

Transcript writers retain their meeting serialization with `FOR NO KEY UPDATE`,
allowing a concurrent first briefing to finish its meeting foreign-key check
while holding the topic lock. Existing full-generation and image publication
checks reject late outputs. Restoring exactly the original document inputs allows
reuse of the retained full briefing without AI, embeddings or image jobs; it does
not silently republish the moment the document is restored.

The resident withdrawal message now covers source changes and identity corrections.
The existing published-briefing projection controls HTML, search, metadata and API
visibility. API updates still identify the affected topic; recorded meeting links
remain available. No document hashing, dependency traversal or AI is added to page
requests.

## Behavioral verification

| Workflows / starting state | Actual boundary and assertions | Limits |
| --- | --- | --- |
| BG-02 / BG-04 / RES-04 / RES-13 | Deterministic download → retained artifact/text → vote/attendance publication → continuity → generated briefing → changed bytes → later HTML and authenticated API reads. Prove visible story/image first, then absent analysis/image, retained meeting links, updated-since identity and unchanged unrelated briefing. Verify retained vote, artifact versions and automated before/after audit. | Synthetic transport/provider responses; no factual conclusion about an official. |
| BG-02, unchanged/failure/recovery | Identical 200, 304 and failed fetch preserve the briefing. Restore earlier bytes, explicitly run full generation and reuse the exact old completion without provider construction or queued image work. A newly discovered unavailable URL leaves the pinned source supported. | Existing general meeting-generation idempotence is not claimed. |
| BG-02, text projection | Identical complete text publication is inert; revised OCR publishes a new text version and withdraws dependent prose while retaining prior extracted votes. | Page preparation is synthetic, not a new extraction-accuracy evaluation. |
| BG-02, removal/attachment | Delete a document, create another at the same URL and repeat the resident request: the original catalog is unresolved, old prose stays withdrawn and retained artifact remains. Metadata-only refresh keeps analysis; purging the current attachment withdraws it without purging the archived version. | Ordinary model/attachment APIs only. |
| BG-02 / BG-04, atomicity | Temporary edits restored inside one transaction and rolled-back changes leave analysis published. Failed audit persistence rolls back source version/publication and withdrawal together. | Isolated database failure injection. |
| ADM-20, audit attribution | Sign in as an active admin after actual source withdrawal and read the audit log: the affected topic is named and the actor is Automated. | No new audit/review UI or public audit endpoint. |
| BG-04, delayed output | Change a source during deterministic rendering; later prose cannot replace the retained withdrawn completion. | Real generation job, simulated provider. |
| BG-02 / BG-03 / BG-04, first publication | Separate PostgreSQL connections pause the first briefing insert, start changed download or actual uploaded-transcript replacement, observe the lock wait, release the insert, and read the newly stored briefing as withdrawn. | No global proof of all writer interleavings or paid-request coalescing. |
| RES-02 / RES-04 / RES-05, existing browser journey | Recheck the changed withdrawal message, topic-to-meeting navigation, official-link presence, search and unrelated topic through the existing identity-correction browser journey. | Source-triggered transitions are checked through HTTP; no external source navigation or new review UI. |

## Execution and defect detection

At `6b8ca071`, twelve isolated mutations each began with a passing target,
produced an assertion failure with zero errors/skips, were restored, and passed
again. No fault remains in the patch.

| Fault | Detected outcome |
| --- | --- |
| Omit source callback | Changed bytes leave the dependent briefing published. |
| Check after each save rather than final commit | A temporary URL edit wrongly withdraws unchanged committed evidence. |
| Ignore motion dependencies | Empty-catalog briefing misses a changed minutes source. |
| Accept stale motion receipt for generation | Retained stale prose is restored after withdrawal. |
| Invalidate unchanged snapshots | Metadata-only refresh wrongly withdraws supported analysis. |
| Ignore source-catalog dependencies | Deletion leaves the catalog-dependent briefing published. |
| Withdraw after commit | Failed audit persistence cannot roll back the source update. |
| Omit possible first-publication owners | The source writer does not wait for the first briefing insert. |
| Keep old illustration ready | The withdrawn briefing's image remains visible. |
| Replace identical uploaded transcript | A repeated SRT import creates another document instead of reusing it. |
| Accept late rendered prose | Stale output overwrites the retained withdrawn briefing. |
| Render known-stale analysis | A source change after analysis still reaches rendering. |

At `5eefb13d`, reverting the admin actor label to the deleted-account fallback
failed the actual admin response assertion; restoration passed. At `227f56a2`,
forcing identical SRT replacement failed the complete transcript workflow's
zero-repeat-topic-call assertion; restoration passed. **Fourteen fault checks**
are demonstrated across this slice.

The existing transcript workflow tests now require stable document/history IDs,
zero repeated topic-summary and briefing calls on unchanged rerun, and zero
repeated topic-summary calls when retrying after a classification failure. Their
identity, Unicode tail, citation, source catalog and rollback assertions remain.
The existing upstream meeting-analysis and topic-classification calls still run
on an explicit workflow rerun; this change does not claim whole-pipeline zero
calls. The two updated complete workflow tests passed: 2 runs, 506 assertions.
The source-withdrawal and admin audit tests passed: 24 runs, 149 assertions.

At `227f56a2`, `RAILS_ENV=test DATABASE_URL=<isolated_test_database>
PARALLEL_WORKERS=1 bin/rails test` passed: **2,325 runs, 14,861 assertions,
zero failures/errors, one existing PromptRun skip** (`No meeting fixture available`).
`bin/rubocop` passed all 685 Ruby files. The full suite includes both new files and
the updated existing generation/transcript assertions.

The browser command `bin/rails test
test/system/council_briefing_withdrawal_journey_test.rb
test/system/transcript_pipeline_journeys_test.rb` passed at `227f56a2`:
**2 journeys, 212 assertions, zero failures/errors/skips**, using Chrome
157.0.8103.38 and its matching driver. This includes the real admin upload form,
queued deterministic workflow, both resident topics and retained source links,
as well as the changed withdrawal copy/navigation. Ordinary and browser tests
ran serially against the isolated database.

Targeted commands also run with the same explicit test database and one worker:

- `bin/rails test test/jobs/topics/generation_evidence_test.rb test/integration/council_source_withdrawal_test.rb test/services/topics/parallel_source_withdrawal_test.rb` — 30 runs / 226 assertions at the initial source-withdrawal revision.
- `bin/rails test test/integration/council_source_withdrawal_test.rb test/controllers/admin/audit_events_test.rb` — 24 runs / 149 assertions after audit labeling.
- `bin/rails test test/jobs/admin/offline_transcript_pipeline_test.rb` — 2 runs / 506 assertions after requiring stable transcript identity and cache reuse.

The new [HTTP/source tests](../../test/integration/council_source_withdrawal_test.rb)
and [parallel source/transcript tests](../../test/services/topics/parallel_source_withdrawal_test.rb)
are discovered by the ordinary runner. Each fault used its named target via
`bin/rails test <file> --name /<test_name>/` for baseline, mutation and restoration.
No implementation test replaces the HTTP, actual PostgreSQL lock-wait or browser
observations above.

## Remaining scope

This slice withdraws **topic briefings with known document dependencies**. Legacy
provenance without a catalog or motion receipt remains unknown. Dependencies
are tracked at document/catalog and motion-receipt granularity, not per sentence. Existing topic
descriptions, meeting summaries, other factual/current projections, knowledge
changes, topic unlinking and cancellation have separate invalidation contracts.
Publishing different facts from unchanged source text is not a document mutation;
that publication boundary needs its own dependent-projection handling.

Bulk SQL, direct extraction-row edits and attachment `detach` bypass the model
commit callback; there are no such current document editing paths added here.
Object-store failures after an attachment transaction commits and general
transcript artifact versioning are not covered by these rollback checks.
Moving documents between meetings and every multi-document/concurrent merge
interleaving are not demonstrated by this record. The generated briefing itself
remains a mutable projection; the audit retains evidence receipts, not an immutable
archive of every generated narrative. Already downloaded HTML or signed image
URLs cannot be remotely revoked.

No production operation, paid evaluation, backfill, merge, deployment or new
schedule ran. Spending/reservation/retry enforcement under #238 remains ahead of
new paid campaign processing. The actual source accuracy and campaign-material
gaps from the bounded pilot remain unchanged.
