# Formal complaint and finding records — November 8, 2026

Scope: ADM-22 → BG-10 → RES-10/11, #244 under #234. The binding
[formal-conduct contract](../superpowers/specs/2026-11-07-council-accountability-design.md#formal-conduct-proceedings)
requires actual case records, separate allegations and findings, source-backed
procedural dates, privacy and explicit incomplete coverage.

## Implemented boundary

Admin intake accepts a source link, case reference, reviewing body, applicable
policy, source type, publication date, subject labels and text cleared for public
quotation. The editor explicitly verifies the underlying formal record, actual
subjects and documented Council service concerned. This supports a later appeal
about an earlier term without treating its publication date as a service date.
Private editorial notes never enter request context or public views. Policy,
ordinary criticism, unknown and unverified sources cannot supply case events.

One bounded source request serves all named subjects. A second classification
guard allows the provider to return no case when intake misclassifies policy text.
The parser requires exact contiguous passages, known source labels, dated events
and event types permitted by the source type. A complaint can supply a filing,
not a finding. These checks locate evidence and constrain output; they do not
prove the provider's semantic accuracy. Public events use fixed procedural labels
and source quotations, without generated character judgments or a conduct grade.

Known names/aliases and actual service control every member projection. Ambiguous
or unknown subjects remain unpublished. Completed analysis is retained; changed
source text removes its stale projection on the next read. Source corrections
can then supply a new result. Display-title, private-note and service-attribution
edits reuse the analysis. Earlier completed input/output remains visible to the
administrator, scoped to its own source. No votes are rewritten.

The public section, each case, and each supporting passage open independently.
Missing records give a short incomplete-coverage message, never a clean-record
badge. Allowed readers and verified Google get saved reporting; gated visitors,
spoofed crawlers and unsupported alternate formats do not. Case data is not added
to a separate summary, API or metadata representation in this slice.

## Spending and recovery

New input requires an explicit exact-request budget run with existing shared
month/day/request limits. No live formal-source allowance is introduced. The
source-save trigger and existing nightly recovery reuse completed work and may
resume eligible work within an existing allowance; there is no new schedule.
Serialized context is limited to 60,000 characters, output to 8,000 tokens, and
malformed responses to two attempts. Oversized, incomplete or uncertain work
holds; missing budget makes zero provider calls. The monthly report includes
formal request receipts alongside the other council stages.

Offline request preparation priced a 1,033-character real negative policy extract
at a conservative $0.110 per attempt, and 56,700 characters of clearly synthetic
planning text at $0.249 ($0.498 for two attempts). These are conservative request
allowances using the checked November 8 preflight rates, not measured provider
usage, a formal-case workload forecast or spending authorization. No paid calls ran.

## Executed verification

Isolated branch `codex/council-formal-cases`, base `9446314`, Ruby 4.0.9,
PostgreSQL `trr_council_formal_cases_test`; deterministic providers and synthetic
positive cases only. The real development database was not migrated or populated.

- Application tests for formal records/intake/nightly recovery plus member,
  navigation, monthly spending and prompt compatibility: **63 tests, 558 assertions**.
- After representative faults were restored, formal records/intake/nightly plus
  live-source and staff-recommendation integration: **35 tests, 402 assertions**.
  Shared source → request/receipt → retained event → both member pages, corrected
  later reads, ambiguity/alias recovery, post-term disposition, authorization,
  private fields and retry limits are asserted across the actual boundaries.
- `bin/rails test test/system/member_formal_records_journeys_test.rb`:
  **1 test, 31 assertions**. Actual admin edit/save, retained title, zero new AI,
  independent source disclosures, source link, 390px width and closed refresh
  state pass. The phone screenshot was inspected. This browser test caught a
  missing saved notice, now fixed using the existing admin convention.
- Representative bounded defects: permitting finding events from complaint text
  failed the parser assertion; including private notes in request context failed
  the private canary assertion; removing controller/view access guards failed the
  anonymous case-section assertion. Each was restored before the green rerun.
  An initial literal test filter ran zero tests and was discarded; the corrected
  regex filters each executed one test and failed for the intended assertion.
- Migration ran only on the isolated database; schema RuboCop formatting and
  the resulting three-table/foreign-key diff were inspected. Full RuboCop passes.
- CI additionally found an undefined admin table wrapper class and a weak
  source-link warning. Both now use the existing table wrapper and safe external
  URL helper. The admin view-hygiene/formal intake/record tests then passed:
  **15 tests, 181 assertions**; Brakeman reports zero warnings.

The [April 6, 2026 official Council packet, page 4](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Packet-92069de44a594aa6990824383b8252fd.pdf)
was inspected visually. Its code-of-conduct adoption item is policy, not an
actual case; the retained negative fixture must produce no case. Positive tests
are synthetic and make no allegation about a real official. No actual positive
case or provider interpretation was validated. Unsupported external case-channel
discovery remains a coverage gap. No production operation, data sync, backfill,
PR merge or deployment ran.
