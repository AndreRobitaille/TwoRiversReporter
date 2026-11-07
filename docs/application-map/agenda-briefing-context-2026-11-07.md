# Agenda previews and withdrawn context: November 7, 2026

Based on `f1ad9087` ([PR #257](https://github.com/AndreRobitaille/TwoRiversReporter/pull/257)).
Verification uses Ruby 4.0.9, Rails 8.1.4.1 and PostgreSQL 18.6 in an isolated
synthetic local database. No paid provider or production operation is involved.

## Requirements and bounded acceptance

Parent [#234](https://github.com/AndreRobitaille/TwoRiversReporter/issues/234),
foundation [#236](https://github.com/AndreRobitaille/TwoRiversReporter/issues/236),
and the [correction contract](../superpowers/specs/2026-11-07-council-accountability-design.md#evidence-validation-and-correction-contract)
require known-invalid claims to stop propagating into dependent reporting.
The [QA procedure](maintenance-and-qa.md) requires allowed-state proof, persistence
and later reads, not just provider-input assertions.

Acceptance for this slice: a withdrawn briefing cannot supply a new agenda
preview; a consumed briefing changed or withdrawn during generation cannot
publish that response; unaffected context and independent knowledge remain
usable. Existing matching thresholds, aliases, six-topic limit and 1,200-character
editorial excerpts remain. Generated background stays separate from official
source citations. Discarding a stale response does not dispatch replacement AI
or downstream preview jobs.

## Implementation

`Topics::AgendaBriefingContext` captures only approved, sufficiently high-impact
topics with a published briefing. It preserves token/alias matching and ranking,
using topic ID to make equal-rank selection deterministic. One eager-loaded
query supplies the captured topic, aliases and briefing fields.

The snapshot retains the identities and exact rendered sections consumed by
the agenda provider. After the response returns, `SummarizeMeetingJob` locks
those topics in ID order and rechecks publication, eligibility, matching and
consumed fields without the query cache, in the summary-save transaction.
The generation, merge and withdrawal writers use these same topic locks. No
lock is held while the provider runs. A removed/replaced briefing fails the
check even if another row could supply similar prose.

A changed snapshot discards the response and leaves any previous summary
unchanged. Image and topic-briefing followups run only for a saved preview.
Timestamp-only changes, changes beyond the consumed excerpt and newly available
optional topics do not invalidate unchanged consumed context. The snapshot is
internal; it does not promote generated interpretation into an official record.

## Behavioral verification

| Workflows / variant | Exercised boundary and assertions | Limits |
| --- | --- | --- |
| BG-02 / BG-04 / RES-06 / RES-13, next generation after correction | Synthetic retained minutes → vote/attendance publication → continuity → two generated briefings → agenda preview → identity correction → new preview → later open HTML and authenticated API. Prove both contexts and the original visible headline first; then one distinct supported context, unchanged independent knowledge, agenda-only official catalog, one persisted preview and no withdrawn headline in later responses. | Deterministic provider responses; not extraction accuracy or a factual conclusion about an official. |
| BG-02, source change during provider response | Actual download changes the minutes source during agenda analysis. Its dependent briefing is withdrawn; old input was demonstrably consumed but returned prose cannot overwrite an earlier independent preview or enqueue image/briefing followups. Repeat HTML/API reads of the retained preview. | Existing previews that depended on a later-invalidated briefing are separate work. |
| BG-02, published interpretation changes | Update a consumed headline during analysis. No first preview is created; later HTML/API have no returned claim. | No new visible controls or browser interaction. |
| BG-02, concurrent correction | Separate PostgreSQL connections hold an uncommitted identity withdrawal while agenda analysis reads the prior committed context. Observe publication waiting on the topic lock; commit correction and verify no summary was saved. | This interleaving only, not all writers or all generated projections. |
| BG-02, retained matching and bounds | Assert exact six identities/order, alias matching and clipped excerpt. Changes to editorial text, upcoming text, approval, impact, name, alias eligibility or row removal reject the saved snapshot. | Component tests supplement the complete job/HTTP path. |
| BG-02, unchanged consumed context | Timestamp-only updates still publish; changes beyond the excerpt and newly available optional topics preserve the snapshot. Empty topic context permits an agenda-only publication. | General meeting-generation idempotence remains separate. |

Tests: [job and resident transition](../../test/integration/agenda_briefing_context_test.rb),
[matching and snapshot checks](../../test/services/topics/agenda_briefing_context_test.rb),
and the existing [meeting-summary jobs](../../test/jobs/summarize_meeting_job_test.rb).
Provider and retrieval transport are simulated; persistence, correction,
withdrawal, publication locking, routing, access and serialization are real.

## Execution and defect detection

Local `RAILS_ENV=test`, isolated PostgreSQL database, `PARALLEL_WORKERS=1`:

- `bin/rails test`: 2,334 runs, 15,001 assertions, zero failures/errors,
  one existing PromptRun fixture skip. This run preceded adding an explicit
  persisted-summary count to the integration helper; runtime code is unchanged.
- Final targeted command: `bin/rails test test/integration/agenda_briefing_context_test.rb test/services/topics/agenda_briefing_context_test.rb test/jobs/summarize_meeting_job_test.rb`: 46 runs, 242 assertions, zero failures/errors/skips.
- `bin/rubocop`: 688 files, no offenses.
- Three Markdown files: 116 local links/anchors, balanced fences; `git diff --check`.

Six isolated experiments each had a passing baseline, one bounded fault, an
intended assertion failure with zero errors/skips, restoration and a green rerun:

| Fault | Demonstrated detection |
| --- | --- |
| Read the raw briefing association | Withdrawn context incorrectly increases the next input's distinct topic count. |
| Omit final context comparison | Source-invalidated output overwrites the earlier persisted preview. |
| Omit topic publication locks | The parallel correction no longer blocks publication. |
| Allow seven contexts | The exact six-topic identity list fails. |
| Remove excerpt truncation | The required clipped excerpt fails. |
| Include unconsumed timestamps in the snapshot | A valid metadata-only update incorrectly prevents summary persistence. |

The last experiment initially raised a missing-row lookup error. The test now
asserts persistence before reading the row; the rerun demonstrated an assertion
failure and successful restoration. The initial error is not counted as defect
detection. Existing matching tests remain, with new identity/cap assertions
separate from canary text checks. No browser control changed; real HTTP checks
cover the affected saved-state/read boundary. CI's existing browser suite remains
the broader compatibility check.

## Scope still open

This fixes input selection and in-flight agenda publication. It does not retain
durable cross-projection dependency receipts or withdraw a previously saved
MeetingSummary after a later briefing correction. Such a correction can still
leave earlier previews/recaps, search projections or images requiring repair.
The existing agenda-summary stage also lacks general unchanged-input provider
reuse; this patch adds no call, retry, polling loop or schedule. Campaign intake
and new paid dispatch remain subject to [#238](https://github.com/AndreRobitaille/TwoRiversReporter/issues/238).

Changes to agenda source/knowledge/participants while their provider runs, fact
publication without a document change, unrecorded legacy dependencies, direct SQL
and arbitrary writers bypassing topic locks remain outside this receipt. No new
factual validation, cost enforcement, production backfill or rollout is claimed.
