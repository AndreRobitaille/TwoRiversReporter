# Campaign article intake: November 8, 2026

Application revision: `a27d68094b928ba2adbbbc830714c850dd1c90e2`, based on PR #266's
spending-control branch. This is the first intake slice of
[#239](https://github.com/AndreRobitaille/TwoRiversReporter/issues/239), not a
completed campaign extractor or member-page enrichment loop.

## Contract and delivered boundary

The [campaign-source design](../superpowers/specs/2026-11-07-council-accountability-design.md#campaign-collection-and-forum-attribution)
requires one supplied source for all supported participants, with question
context, provenance, coverage and correction history. The parent issue requires
unchanged-input reuse and no paid processing before explicit spending limits.
The [admin design](../superpowers/specs/2026-07-26-admin-ui-revamp-design.md)
requires a discoverable workflow using the existing admin components and access
rules. These requirements define ADM-21's acceptance; raw source retention is
not approval of its claims or a promise of extraction accuracy.

Members → Campaign sources → Add article accepts a publisher link, title,
publisher, election date, optional publication date, complete/excerpt coverage,
context notes and permitted article text. It preserves all supplied questions,
candidate labels, continuation paragraphs, qualifications and unanswered-question
markers together. Dates and coverage are operator-supplied source metadata.
Unknown publication dates remain unknown. No individual statement entry is needed.

`CampaignSource` retains its current input and immutable `CampaignSourceVersion`
snapshots. The version identifies source metadata plus normalized text; a separate
content hash supports later source-analysis reuse. Only outer whitespace and
line endings are normalized. Repeated saves reuse an identical version and leave
the source timestamp alone when nothing changes. An explicit edit retains the
earlier version and makes the corrected input current. Submitting an already
saved URL opens that source instead of overwriting an explicit correction.
Snapshots reload the persisted article under the save transaction's row lock,
so overlapping partial edits retain the actual saved combination of fields.

Source text is private to existing passkey-eligible admins. Historical versions
use the same access boundary, and supplied markup is rendered as text. Submitted
form parameters are filtered from request logs. There is no public source route,
API expansion, raw-article mirror, remote article fetch or access-restriction
bypass. Saving queues no work, creates no people/office records and calls no AI.
The existing KnowledgeSource path was not reused because it automatically queues
ingestion and treats the body as general retrieval context.

Shared extraction, statement classification, candidate resolution, topic links,
paid request admission and profile publication remain subsequent slices. Prepared
forum handoff remains outside this article form; no transcript preparation or
speaker-labeling tool was added. Existing spend controls are preserved, not
enabled by this intake workflow.

## Verification

Environment: Ruby 4.0.9, Rails 8.1.4.1, isolated local PostgreSQL database
`trr_campaign_source_intake_test`, shared external gem store, `RAILS_ENV=test`,
`PARALLEL_WORKERS=1`. Application and browser tests ran serially. The questionnaire
is wholly synthetic and includes three named candidates, a conditional position,
a continuation paragraph and an unanswered question. No HTR article text or
other real copyrighted article was committed or loaded by this check.

- `bin/rails db:schema:load db:migrate`: created the two source tables in the
  isolated database. `bin/rubocop -A db/schema.rb` restored schema formatting;
  the inspected diff contains only those tables, indexes, foreign keys and version.
- `bin/rails test test/models/campaign_source_test.rb test/integration/campaign_source_intake_test.rb test/controllers/admin/members_controller_test.rb test/controllers/admin/base_controller_test.rb test/routing/application_dispatch_test.rb`:
  **18 tests, 142 assertions, zero failures/errors/skips**. Real HTTP save/edit/read
  requests preserve exact supplied text and context, original/corrected versions,
  coverage and submitter identity. Repeated intake cannot undo the correction.
  Invalid input preserves the form and current saved version. An allowed admin
  read precedes ordinary-account and logged-out denial checks, including historical
  and JSON requests. No provider or job boundary is bypassed: intake enqueues no
  job and the provider-constructor sentinel fails if AI is attempted.
- `CHROME_BIN=/usr/bin/chromium bin/rails test test/system/campaign_source_intake_journeys_test.rb`:
  **1 journey, 29 assertions, zero failures/errors/skips**. It follows the visible
  Members link, creates the source through the form, checks the persisted election
  date, edits coverage/text, refreshes, and opens the retained original. At 390px
  the inspected screenshot has no horizontal overflow. Sign-in email delivery is
  captured locally by the existing browser harness; no real email is sent. Native
  passkey ceremony is not exercised by this source-intake journey.
- CI's full application suite found undefined admin classes (`flash--warning` and
  the source-text test selector). The page now uses the existing neutral flash
  component and a data attribute for the test selector. The focused command above
  plus `test/views/admin_view_hygiene_test.rb` passed **21 tests, 148 assertions**;
  the phone journey also passed again with **29 assertions**. No checks were relaxed.
- `bin/rubocop --cache false`: **731 files, no offenses**. `git diff --check`
  and documentation links/anchors pass. `bin/rails routes -g campaign_sources`
  lists seven dispatch rows, and the route test confirms their actions exist.

## Defect detection and limits

During development, the correction-survival assertion failed when Add article
updated an existing URL from an older payload: it selected a different version
after the explicit correction (1 test, 30 assertions, 1 failure, no errors/skips).
The controller now returns the saved record for duplicate submissions; edits
remain the explicit correction path. The restored HTTP command above passed.

The PR review identified a second defect: two independently loaded source objects
could save different fields, leaving the final database row without a matching
snapshot. A deterministic stale-instance reproduction failed on the absent version
(1 test, 1 assertion, 1 failure, no errors/skips). The callback now reloads under
the source row lock before retaining the persisted fields. The restored check
reads both current and intermediate versions through HTTP, proving the combined
title/body display and the preserved earlier body. This verifies the reported
interleaving without claiming simultaneous-browser stress testing.

A separate process-local fault removed `require_admin` only from the new
controller. The test first read the text as an admin, then failed when the ordinary
account received HTTP 200 instead of a redirect (1 test, 4 assertions, 1 failure,
no errors/skips). The unmodified 17-test command then passed. No running preview
or application source file was changed by this fault. The final 18-test command,
mobile journey and RuboCop were rerun after the overlapping-edit correction.

These are bounded implementation/conditional-defect checks, not evidence of
production failure frequency. Paid extraction, automatic publication, source
accuracy, full participant/statement extraction coverage and forum attribution
are not yet verified or implemented by this slice. No production operation,
shared development-data change, backfill, merge or deployment occurred.
