# Registered live source processing — November 8, 2026

Scope: BG-02/08/09 → RES-10, #238/#240/#243 under #234. The binding
[AI cost contract](../superpowers/specs/2026-11-07-council-accountability-design.md#ai-cost-contract)
requires new-evidence updates, shared analysis, unchanged-input reuse and existing
nightly recovery. The owner's full-term backfill approval remains separate.

## Implemented behavior

An optional `issue_sources` scope within the existing monthly `live_actions`
policy explicitly identifies `committee_ids`, supported `document_types`
(`minutes_pdf`, `minutes_html`, `packet_pdf`) and `starting_on`. It inherits the
same month/day/request/count/concurrency/model/input/output limits. Old action-only
policies do not authorize this source work. No migration or default allowance is
introduced. Authorizations stay immutable except revocation; a new month needs
explicit renewal and current pricing, rather than silently replenishing a budget.

The initial source window cannot predate its authorization. Renewal can retain
already authorized source types/bodies and dates; it cannot borrow an older
campaign window or add historical source types/bodies. This protects the held
backfill boundary. No live policy was installed in development or production.

Existing meeting discovery/document adapters still collect the evidence. The
source job selects available text only for registered committees/types within
the window, alongside previously selected documents. Existing `IssueInput`
validation requires usable current official text, an occurred non-cancelled
meeting and approved agenda topics. Newly eligible source work is queued after
topic extraction/triage and minutes publication. Existing nightly recovery covers
missed triggers, deferred topic approval and corrected selected documents. There
is no new schedule or paid call on page views.

`LiveBudget` now provides the shared admission path for campaign decisions and
official-source stages. Source scope is checked during admission and again at
reservation. Request parameters, budget reservations and receipts retain their
existing exact-input contract. Source work shares all relevant limits with
campaign comparisons, including occupied slots from uncertain provider outcomes.
Daily holds can resume later within the same authorization; a monthly ceiling
cannot reset when the next day arrives. Missing/expired/revoked policies hold work
without spending or changing established votes. Existing completed analyses are
not reopened by this code or prompt/schema changes.

One source result supplies milestones, advocacy and recommendations for all
relevant members. No bespoke member processing or writing is added. The prior
offline cost scenarios remain applicable: this slice adds scheduling/admission,
not an extra model stage or a larger request. Actual workload and real model
quality still need a bounded evaluation before activation.

## Executed verification

Isolated branch `codex/council-live-sources`, base `6d973f4`, Ruby 4.0.9 and
PostgreSQL `trr_council_live_sources_test`. Tests use deterministic providers and
synthetic records; no simulated output enters real profiles.

- `bin/rails test test/integration/council_live_sources_test.rb
  test/integration/council_live_action_budget_test.rb
  test/jobs/reconcile_campaign_sources_job_test.rb
  test/jobs/council_profiles/parallel_live_action_budget_test.rb`:
  **17 tests, 182 assertions**, green before the subsequent source-trigger test.
  This includes actual competing PostgreSQL dispatch sharing the last monthly
  allowance, existing action compatibility, channel/type/date exclusions,
  immutable authorization, renewal bounds, revocation, attempt limits and
  unchanged source/page reuse.
- `bin/rails test test/integration/council_live_sources_test.rb
  test/jobs/extract_topics_job_test.rb
  test/integration/council_issue_updates_test.rb
  test/integration/council_staff_recommendations_test.rb`:
  **59 tests, 411 assertions**, green. The added journey removes the topic link,
  exercises actual topic-result parsing and link publication with a deterministic
  upstream provider, verifies source enqueue, then executes provider transport →
  reservation → saved evidence → member HTTP read. Source request, result count,
  identities and displayed section are asserted. Upstream retrieval/provider
  responses are simulated; topic governance and downstream jobs still execute.
- Representative faults: allowing an action-only policy to admit source work
  failed the intended scope assertion; removing the topic-result trigger failed
  the intended enqueue assertion. Both were restored. The source suite plus
  existing minutes-publication integration and fact-publication tests then passed:
  **30 tests, 217 assertions**.

Full `bin/rubocop` passes across 844 files; 175 local documentation link targets
exist and `git diff --check` is clean.

No new browser control or rendered markup is introduced. The staff-comparison
browser journey and screenshot evidence remain in the preceding slice; source
publication and later access here are verified through jobs and HTTP. Real
provider accuracy, production worker execution, external project/case channels
without an existing meeting adapter, broader historical coverage and live monthly
activation remain unverified. No paid generation, production operation, data sync,
backfill, PR merge or deployment ran.
