# Shared campaign extraction: November 8, 2026

Application revision: `437d64a73ff28c9389a2c80c8bfabc528b373b38`. Based on the article intake in
PR #273; this advances [#239](https://github.com/AndreRobitaille/TwoRiversReporter/issues/239)
and reuses #238's spending controls. It is not the completed public campaign record.

## Requirements and delivered boundary

The [campaign contract](../superpowers/specs/2026-11-07-council-accountability-design.md#campaign-collection-and-forum-attribution)
requires one source-wide extraction with all supported participants, questions,
statements, qualifications, timeframes and source locations. The
[cost contract](../superpowers/specs/2026-11-07-council-accountability-design.md#ai-cost-contract)
requires shared reuse, explicit allowances, bounded retries and no AI on reads.
ADM-21 and new workflow BG-08 follow these requirements; a text match alone does
not prove attribution to a known person or semantic accuracy.

`ExtractCampaignSourceJob` selects the current retained article version and calls
`Campaigns::ExtractSource`. One request through `Ai::OpenAiService` processes the
entire supplied text for every participant. The populated campaign prompt states
explicit array cardinality and preserves continuation paragraphs and unanswered
questions. Inputs over 50,000 characters stop for partitioning; they are not
silently truncated. Output is capped at 8,000 tokens and must finish normally.

`CampaignExtraction` retains the exact request parameters and all parsed output.
`CampaignRequest` retains each actual dispatch, provider response, usage and
reservation. The request recorder is shared with minutes; existing minutes keys
remain unchanged and campaign request keys have their own namespace. Before any
transport, the existing run/day/request/token/concurrency allowance is reserved
against the exact prepared request. Missing or exhausted allowance pauses without
consuming a paid attempt. Invalid JSON/shape permits at most two attempts;
uncertain transport and incomplete provider completion do not automatically
redispatch. An uncertain reservation remains occupied.

Repeat deliveries reuse the completed stage even after global prompt changes.
Title/publication metadata corrections whose actual analysis parameters match a
completed result reuse its data with a retained origin reference and zero calls.
Changed source text gets a distinct stage. Arithmetic and exact passage locations
use code: three participants/five answers/five statements are separately counted
in the fixture. An unresolved name/passage marks its own statements; other
located statements remain present. Unknown names create no people or offices.
Location checks are not identity resolution or publication approval.

The existing private article page displays all participants and statements,
conditions, timeframes, supporting quotes and reported gaps for the selected
version. Correcting the source stops displaying the old analysis as current;
its historical source page still shows it. Page reads do not analyze anything.
The source intake still starts no jobs; no schedule, production admission or
paid-generation control was enabled. An authorized operator would have to supply
a prepared allowance explicitly to the job. No full-article public route exists.

## Verification

Ruby 4.0.9, Rails 8.1.4.1, PostgreSQL database
`trr_shared_campaign_extraction_test`, `RAILS_ENV=test`, `PARALLEL_WORKERS=1`.
The shared external bundle was configured and checked. Development eager loading
and a local read-only `SELECT 1` passed. No shared development data was changed.
Provider transport alone is replaced with deterministic synthetic responses;
real job, AI-service parameter construction, spending admission, request receipts,
parser, database and HTTP/browser paths execute. No real article was loaded.

- Migration/schema checks: created two tables and their indexes/foreign keys in
  the isolated database. The migration was rerun locally after making each
  campaign receipt require its reservation. `bin/rubocop -A db/schema.rb` ran;
  inspected schema changes are limited to those tables and relationships.
- Focused command: `bin/rails test test/jobs/extract_campaign_source_job_test.rb test/integration/campaign_extraction_test.rb test/integration/campaign_source_intake_test.rb test/views/admin_view_hygiene_test.rb`:
  **14 tests, 195 assertions, no failures/errors/skips**. Distinct participant and
  answer identities, counts, complete input text, continuation, condition,
  timeframe, source-character ranges, persisted response/usage and shared budget
  reservation are asserted. Correction/repeated job/current and historical HTTP
  reads preserve the five statements. Allowed admin reads precede ordinary and
  logged-out denial, including JSON and retained-version requests.
- Browser: `CHROME_BIN=/usr/bin/chromium bin/rails test test/system/campaign_extraction_journeys_test.rb test/system/campaign_source_intake_journeys_test.rb`.
  Exercises visible navigation, every participant, five displayed statements,
  opening supporting evidence, source editing/history and later reads at 390px.
  Email transport is captured locally by the existing harness; native passkey
  ceremony is not exercised here. Final result: **2 journeys, 57 assertions,
  no failures/errors/skips**. The final phone screenshot was inspected; the
  stacked heading/action is readable and the page has no horizontal overflow.
- `bin/rubocop --cache false`: **742 files, no offenses** before the final header
  flow adjustment; the final affected Ruby test file also passed its lint check.
- `bin/rails test`: **2,454 tests, 16,597 assertions, no failures/errors, 1 skip**.
  This covers the existing minutes/spending recorder paths as well as the new
  campaign paths, after both process-local faults were removed. The skip is the
  existing fixture-dependent PromptRun polymorphic-source check.
- `bin/rails prompt_templates:populate prompt_templates:validate`: all **21**
  populated prompts validate in the isolated test database. No development or
  production prompt template was changed.
- Documentation: **285 relative links/anchors** across the five affected map
  documents and `git diff --check` pass.

## Defect detection and remaining work

A process-local parser fault dropped Morgan after receiving the complete provider
response. The job assertion failed on the participant identities (1 test,
9 assertions, 1 intended failure, no errors/skips). A separate process-local fault
removed the admin guard. After verified admin current/historical reads, the HTTP
assertion failed because an ordinary account received 200 instead of a redirect
(1 test, 22 assertions, 1 intended failure, no errors/skips). Neither fault edited
application source or affected the running member preview.

Initial development checks exposed a has-one creation/readonly-field interaction
and a Ruby conditional-assignment error, both fixed before passing results.
The first browser check expected title-case text where existing CSS renders
headings uppercase; case-insensitive identity checks preserve the requirement.
Visual inspection also prompted a simple stacked article heading/action layout
so the edit button does not crowd the subtitle on a phone.

Real-provider extraction accuracy/completeness is unverified. Actual token/pricing
preflight and a bounded paid pilot still need separate authorization. Candidate
resolution, public campaign positions, action/outcome matching, prepared forums,
explicit reanalysis of an unchanged source, and automatic source/nightly dispatch
remain subsequent slices. This private extraction is not a human-reviewed claim
or a resident-facing follow-through conclusion. No paid AI, production operation,
backfill, merge or deployment occurred.
