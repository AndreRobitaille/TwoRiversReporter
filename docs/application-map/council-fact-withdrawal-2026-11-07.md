# Fact publication and stored briefings: November 7, 2026

Based on `900d9cb4` ([PR #258](https://github.com/AndreRobitaille/TwoRiversReporter/pull/258)).
Local verification uses Ruby 4.0.9, Rails 8.1.4.1 and PostgreSQL 18.6 with an
isolated synthetic database. Providers and downloads are deterministic fixtures.

## Requirements and acceptance

Parent [#234](https://github.com/AndreRobitaille/TwoRiversReporter/issues/234),
foundation [#236](https://github.com/AndreRobitaille/TwoRiversReporter/issues/236),
and the [evidence/correction contract](../superpowers/specs/2026-11-07-council-accountability-design.md#evidence-validation-and-correction-contract)
require retained before/after evidence, propagation of corrections, rejection of
stale work and unchanged-input reuse. The [QA procedure](maintenance-and-qa.md)
requires proof across publication and later reads, plus representative faults.

This slice addresses a gap after document-source withdrawal: explicitly revised
extraction or deterministic reprojection can publish new facts without changing
the document. A stored briefing with a now-invalid motion receipt must be
withdrawn in that publication transaction, before continuity or new prose runs.
Its illustration must stop being current, while retained source, observations,
decision identity, original generated content and unaffected reporting survive.
An audit failure must roll back publication; retry must reuse completed stages.
Unchanged publication and still-valid motion context must not be withdrawn.

## Implementation

`Minutes::Publish` captures previous publication and motion IDs, publishes the
paired projection, then calls `Topics::WithdrawFactBriefings` before committing.
The service follows immutable observation references and known legacy event
receipts. Previous motion IDs preserve the ability to identify a legacy event
after its mutable motion row has been replaced; no missing historical identity
is guessed.

Affected topics, event owners and agenda-linked possible first-publication owners
are locked in ID order. Receipt and owner queries are repeated without query
cache after waiting, so a first briefing, new continuity event or completed topic
merge cannot move a known receipt outside the check. Each affected published
briefing is compared with current motion evidence. Still-valid receipts remain
published even when a compatible attendance refresh creates another publication.

Withdrawn rows retain their generated payload and last-generation date. The
existing audit log records an automated method, before/after publication IDs,
stage IDs, projection context, a changed-motion-evidence reason and the retained evidence manifest. This is not
human review or approval of an extracted fact. Pending/current/failed images
derived from the briefing become superseded; attachments remain retained.

The meeting transaction uses `FOR NO KEY UPDATE`, preserving writer serialization
while allowing a first briefing's foreign-key check to finish under its topic
lock. Without this lock mode, publication and first generation can deadlock.
Existing late-output guards reject a provider response whose facts changed.
Only the existing post-publication continuity job is queued. No paid dispatch,
automatic prose rewrite, retry loop, new schedule or schema migration is added.

## Behavioral verification

| Workflows / starting state | Exercised boundary and assertions | Limits |
| --- | --- | --- |
| BG-02 / BG-04 / RES-04 / RES-10 / RES-13 | Retained minutes/text → paired extraction → continuity → stored briefings/image → explicit revised extraction of the same source → publication → later member HTML, conditional topic HTML and authenticated API. Prove the initial vote, story and image first; then corrected vote, absent stale analysis/image, retained meeting link, updated-since topic identity and unchanged unrelated briefing. Assert one artifact/text version, two vote stages/publications, one attendance stage, stable decision identity and immutable original observation/prose. | Synthetic initial provider deliberately misreads the unchanged passage's yes vote; subsequent provider corrects it. This tests correction propagation, not source interpretation accuracy. |
| BG-02, unchanged/compatible refresh | Repeat both extraction jobs with providers forbidden; no queued work or briefing mutation. Explicit compatible attendance refresh keeps the same valid motion receipt and reporting. | Does not establish eligibility or all attendance-derived narrative dependencies. |
| BG-02 / ADM-20, failed audit | Force audit persistence failure after new stage completion. Assert old fact/attendance row identities, publication and briefing unchanged. Retry with providers forbidden publishes completed stages, withdraws once and records before/after history. | Real transaction failure; external storage failure after commit is separate. |
| BG-02, date correction | Reproject a changed meeting date from cached stages with providers forbidden. Withdraw old dated motion context while preserving known votes and extraction identities. | The trigger is fact publication, not every meeting metadata edit. |
| BG-02 / BG-04, known legacy receipt | Generate from a live legacy motion event, replace its projection and verify the retained event receipt is withdrawn. | Unrecorded or already-unresolvable legacy provenance is not invented. |
| BG-04, late response | Change facts during deterministic briefing analysis after proving the old completion exists. The late output cannot replace the retained withdrawn completion or appear on later reads. | Existing generation guards, newly exercised with fact publication. |
| BG-02 / BG-04, first publication | Separate PostgreSQL connections pause first briefing insertion, start a fact refresh, observe the topic-lock wait, then release the insert. Both transactions finish without a meeting foreign-key deadlock; the newly inserted briefing is withdrawn and the member vote advances. | This concrete interleaving, not a proof of every writer/merge combination. |

The [new integration tests](../../test/integration/council_fact_withdrawal_test.rb)
exercise real jobs, publication, persistence, HTTP routing and serialization.
The existing [fact publication tests](../../test/jobs/minutes/fact_publication_test.rb)
remain part of targeted regression coverage. No browser control or layout changed;
the risky new boundary is the database transaction and subsequent HTTP reads.

## Execution and defect detection

Local tests use `RAILS_ENV=test`, an isolated PostgreSQL database and
`PARALLEL_WORKERS=1`. The final targeted command was
`bin/rails test test/integration/council_fact_withdrawal_test.rb test/jobs/minutes/fact_publication_test.rb test/jobs/minutes/parallel_publication_test.rb`:
28 runs, 260 assertions, zero failures/errors/skips. `bin/rubocop` inspected
690 files without offenses. The integration suite includes the admin audit-log
request and verifies the Automated actor and affected topic after publication.

Eight isolated faults each had a green baseline, an intended assertion failure
with zero errors/skips, restoration and a green rerun:

| Fault | Demonstrated detection |
| --- | --- |
| Skip withdrawal | The corrected fact publishes while the stale briefing remains current. |
| Withdraw after the publication transaction commits | Failed audit leaves a new publication committed instead of rolling it back. |
| Omit topic locks | Fact publication fails to wait for first briefing insertion. |
| Restore an exclusive meeting lock | PostgreSQL reports a deadlock and Active Job queues an extraction retry; the explicit no-retry assertion fails. |
| Withdraw every matching receipt without checking current evidence | A compatible attendance refresh unnecessarily withdraws valid motion context. |
| Ignore legacy event receipts | The live legacy reference survives replacement of its motion projection. |
| Leave the image ready | The superseded-illustration assertion fails. |
| Construct an AI provider during publication | The completed-stage retry's provider prohibition fails. No real provider is called. |

Initial fixture development exposed a nested Minitest stub and an unused field
chosen to trigger generation. The fixtures now use one provider wrapper per
concurrent operation and an actual changed query alias. Those setup errors are
not counted as product-defect detection. The meeting-lock experiment was rerun
after adding the explicit retry assertion; baseline and restoration passed.

## Remaining scope

This handles known motion receipts in stored topic briefings. It does not add
missing dependencies to a legacy briefing, invalidate vote/attendance claims
embedded only in an old MeetingSummary, or withdraw previously saved agenda
previews/recaps. Broader generated projections, new dependency types, direct SQL
and arbitrary writers bypassing the publication service remain separate work.
Supported source citations alone do not prove an extracted interpretation correct.

The existing spending-limit requirement in
[#238](https://github.com/AndreRobitaille/TwoRiversReporter/issues/238) still gates
new paid generation. No real-provider run, broad import, production operation,
merge, deployment or campaign-source conclusion is part of this verification.
