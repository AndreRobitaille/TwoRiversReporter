# Topic upcoming meeting cards

Scope: RES-04, the topic page's Coming Up section. The owner's November 2
clarification requires one card per meeting, labeled with the first linked
agenda item in agenda order. This changes presentation, not topic appearances
or the factual record.

Local evidence: base revision `b15b01787ebe9d6cf7106bdf619fa0dc8edbd8ac` plus
the controller/test changes in this working tree, Rails 8.1.4, PostgreSQL test
database. Synthetic fixtures only; no AI calls are involved in these tests.

- `PARALLEL_WORKERS=1 bin/rails test test/controllers/topics_controller_test.rb`:
  42 tests, 190 assertions, no failures, errors or skips.
- The new integration test creates two agenda items in reverse agenda order,
  links both to one future meeting, and adds a separate meeting at the same
  start time. Two successive topic requests show one card for each meeting,
  selecting the first agenda item. Both record events and persisted appearance
  rows remain. Following the meeting link still displays both agenda items.
- Defect detection: after the passing baseline, temporarily restoring
  per-item deduplication produces three cards instead of two. The intended
  rendered-link assertion fails (one failure, no errors). Restoring the fix
  passes the targeted test: one test, 21 assertions, no failures/errors/skips.
- `bin/rubocop`: 633 files inspected, no offenses.

The assertions exercise authenticated HTTP rendering and later requests. No
CSS, browser interaction, authentication policy, or AI pipeline behavior changes.
Browser visual inspection, CI and production deployment are not claimed here.
