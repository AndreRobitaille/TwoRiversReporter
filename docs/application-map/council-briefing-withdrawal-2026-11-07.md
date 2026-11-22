# Council identity corrections and published briefings: November 7, 2026

Based on `a04aaeb4` ([PR #255](https://github.com/AndreRobitaille/TwoRiversReporter/pull/255)).
Runtime revision: `2df6b19f` (initial withdrawal `7d6c3dbb`, recovery/navigation
`c4457177`). Ruby 4.0.9, Rails 8.1.4.1, PostgreSQL 18.6;
isolated synthetic test database and Chrome 157 with matching driver.

## Requirements and bounded acceptance

Parent [#234](https://github.com/AndreRobitaille/TwoRiversReporter/issues/234),
[#236](https://github.com/AndreRobitaille/TwoRiversReporter/issues/236), and the
[evidence/correction contract](../superpowers/specs/2026-11-07-council-accountability-design.md#evidence-validation-and-correction-contract)
require known-invalid dependent claims to be withdrawn before replacement prose
is available, while retained records and unrelated valid analysis remain usable.
The [public access contract](../superpowers/specs/2026-07-24-tiered-public-access-design.md)
and [API contract](../read-only-api.md) apply to every resident representation.

This slice handles a successful `CouncilDecisions::ResolveIdentity` review that
changes an identity recorded in a full topic briefing's dependency receipt. It
covers unassignment, reassignment and propagated assignment conflicts through the
same comparison. An identity receipt is not factual validation or a conduct finding.

Acceptance, derived before implementation: the correction and withdrawal commit
together; all resident briefing representations disappear without provider calls;
search cannot reveal withheld briefing text through result identity; changed API
content remains discoverable; retained evidence and unrelated briefings survive;
same-identity review and request replay are harmless; delayed generation cannot
restore stale prose or illustrations; fresh checked generation can restore a
briefing without reviving superseded illustrations.

## Implementation and cost

`Topics::WithdrawCorrectedBriefings` finds receipts referencing affected
observations, locks their topics and event owners, compares neutral event
references, and sets the briefing withdrawal timestamp and correction reference.
Event owners are locked even before their first briefing exists. Candidate owners
are rechecked after locking with the query cache disabled, so a completed topic
merge cannot leave a deleted owner cached or move the dependency out of the lock set. The correction's meeting lock uses `FOR NO KEY UPDATE`:
reviews and minutes publication still serialize, while a generator holding the
topic can complete its foreign-key check on the unchanged meeting key.

Stored prose, generation JSON, source versions, observations, votes and original
review history remain intact. `published_topic_briefing` and `TopicBriefing.published`
are the resident projection; the ordinary association remains available to
operators and generation. HTML, cards, committee headlines, metadata, Turbo search,
API serialization and API search use that projection. The topic record explains
withdrawal and lists actual meeting appearances instead of claiming no meeting
activity exists. API freshness includes the
withdrawal timestamp through the changed briefing row, while `has_analysis` and
`last_analysis_updated_at` describe the currently published briefing.

Existing linked illustrations become superseded without deleting their files.
Image jobs skip withdrawn briefings even when forced; delayed image publication
checks the current briefing and content fingerprint under the topic lock. The full
briefing job clears withdrawal after its evidence checks. If a later correction
restores the exact original inputs, it revalidates the retained completion under
the topic lock and restores it without generation, retrieval or image-job dispatch.
The original full-generation timestamp is retained and exposed by the API.
Partial updates skip withdrawn records and compare the prior output under the
topic lock before saving, preventing delayed interim notes from contaminating a
newly restored full briefing.

No new paid dispatch, provider, schedule, backfill or regeneration job is added.
Correction and resident reads use database queries and code only. No whole-context
hashing or knowledge retrieval runs per resident request. Existing unchanged full
briefing reuse still returns before either provider is constructed.

## Behavioral verification

| Workflows and starting state | Boundary and asserted outcome | Limits |
| --- | --- | --- |
| BG-04 / RES-01–04 / RES-11 / RES-13, open mode | Synthetic document download → retained text → votes/attendance publication → continuity → real briefing generation → identity review → later HTML/API reads. First prove visible headline/story/image, exact search identity and timeline count; then remove them from pages, metadata, search, API and timeline while preserving agenda navigation and source artifact. | Provider and download transport are deterministic fixtures. |
| RES-11, gated member/anonymous and verified crawler | Prove full reporting to an allowed actor, apply review, repeat requests and HEAD. No withdrawn text, private actor/reason, or API briefing; no-store retained. | Crawler feed cache is synthetic, ordinary verification middleware runs. |
| RES-13, update feed | Query after a timestamp preceding review; the corrected topic remains discoverable with no published analysis. Unrelated topic is unchanged. | API is a current-content feed, not a historical correction log. |
| BG-04, rollback/replay/selectivity | A failure after dependent writes rolls back review and withdrawal; same-identity review changes no briefing; replay commits no new audit and changes no timestamp. | No production review is performed. |
| BG-04, delayed jobs and recovery | Correct during rendering; old prose stays withdrawn. Correct during image transport; late bytes never attach/publish. A fresh full briefing restores publication; an older interim response cannot overwrite it; unchanged rerun has no provider calls. | No real image or language-model calls. |
| BG-04, concurrent first publication | Separate PostgreSQL connections hold the first briefing insert at its callback, begin correction, observe a database lock wait, release generation, then read the new row as withdrawn. | Does not claim global paid-dispatch coalescing or all writer interleavings. |
| BG-04, concurrent topic merge | Pause a merge under both topic locks, start review with the query cache enabled, then complete the merge. The review follows the retained briefing to the survivor and withdraws it; unrelated briefing stays published. | Separate PostgreSQL connections; other invalidation writers remain out of scope. |
| RES-02 / RES-04 / RES-05, browser | Follow the topic card, see analysis and metadata, correct, reload, follow the remaining meeting link, check the official-source link is present, search, and open the unrelated topic. | Correction is invoked internally; no new review UI is introduced. |

An existing Turbo search request crashed because its template read only the browse
collection. The template now reads the actual search collection and preserves the
query in continuation URLs; allowed and withdrawn search identities are checked.

## Execution and defect detection

All fourteen bounded faults started from a passing target test, caused an assertion
failure (zero errors/skips), were restored, and passed again. These were isolated
local mutations; none is retained in the patch:

| Fault | Meaningful assertion that failed |
| --- | --- |
| Omit review-triggered withdrawal | Persisted withdrawal timestamp exists after review. |
| Expose the raw association to residents | Corrected story is absent on the later topic response. |
| Match withdrawn web headline | Search returns zero cards for the withdrawn claim. |
| Match withdrawn API narrative | API search returns no topic identity for withdrawn story text. |
| Omit withdrawal from API freshness | Updated-since feed includes the corrected topic. |
| Withdraw a still-current receipt | Same-identity review leaves briefing attributes unchanged. |
| Leave the withdrawal flag after full generation | A fresh checked briefing becomes published again. |
| Permit delayed image publication | Delayed image remains superseded without an attachment. |
| Accept a stale interim result | Restored full story remains the corrected story. |
| Ignore event owners before first publication | Review waits for the in-flight topic publication lock. |
| Use the ordinary empty record state | The page explains withdrawal instead of claiming no meeting activity. |
| Regenerate restored identical inputs | The test forbids constructing either generation or retrieval providers. |
| Report republication as new generation | API generation date remains the actual original full-generation date. |
| Cache lock-owner queries during review | Review completes on the merged topic rather than looping over a deleted owner. |

The concurrency test also exposed a real first-insert/review deadlock during
implementation. The lock was corrected and the actual two-connection case reran
to green, alongside the existing concurrent-review test. This observed defect is
separate from the fourteen intentional fault injections. A second real concurrent
merge case exposed a cached-owner loop; uncached dependency reads resolved it and
the completed review withdrew the retained briefing on the surviving topic.

`bin/rails test test/system/council_briefing_withdrawal_journey_test.rb` discovered
and passed the new browser journey: 1 run, 16 assertions, no failures/errors/skips.
An earlier assertion was corrected for the existing uppercase heading styling.
The helper test doubles were updated to supply the published association while
retaining their headline, blank-fallback and access-gating assertions.
`bin/rubocop` inspected 682 files without offenses. `db:migrate` ran only against
the isolated test database, followed by `bin/rubocop -A db/schema.rb` and inspection
of the schema diff. Three changed Markdown files passed 109 local link/anchor
checks and balanced fences.

Local full application suite at `c4457177`:
`bin/rails test --seed 48513` — 2,311 runs, 14,763 assertions, no failures/errors,
one existing `PromptRunTest` skip (`No meeting fixture available`). After the
query-cache fix, the three withdrawal test files discovered and passed 13 tests
with 251 assertions; the added cached-merge test passed separately with 8
assertions, including after fault restoration. The final PR CI executes the whole
application suite again against the final head, including that added case.

Commands used `PARALLEL_WORKERS=1` and an isolated synthetic PostgreSQL database.
The application and browser suites ran serially against it. Runtime/provider
mutations were restored before subsequent suites. Development boot and the
permanent shared bundle path were verified; no dependency changes were needed.

At `2df6b19f`, `bin/rails test:system` discovered and passed all 24 browser
journeys: 795 assertions, no failures/errors/skips. The final `bin/rubocop` run
again inspected 682 files without offenses; `git diff --check` passed.
Exact-head CI and runtime-build links are maintained in the PR description;
a CI image build is not publication or deployment.

## Remaining scope

- Document replacement, source deletion, knowledge withdrawal, topic-link changes,
  meeting cancellation and other invalidation writers do not yet trigger stored
  briefing withdrawal. PR #255's generation-time checks still apply.
- Legacy briefings without dependency receipts remain unknown provenance; no
  dependency or approval is invented. Existing descriptions, meeting summaries,
  lifecycle labels and other generated projections need their own dependencies.
- A request already in flight, previously downloaded HTML, an old signed image URL,
  or an external crawler cache is not remotely revoked. New resident responses
  omit withdrawn briefing content and linked illustration URLs.
- Successful regeneration still replaces the mutable briefing projection. This
  slice does not introduce an immutable generated-analysis archive or a public
  correction log. The identity correction and original source evidence remain.
- Other identity-merge/publication interleavings, full profile UI, campaign
  evidence ingestion and #238 spending/retry enforcement remain separate work.
