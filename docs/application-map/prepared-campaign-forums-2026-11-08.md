# Prepared campaign forum intake: November 8, 2026

This bounded ADM-21/BG-08 extension under #239 and parent #234 accepts the
externally prepared, speaker-labeled forum files supplied by the owner. It keeps
all candidates, including people who did not win, without creating Council
memberships or treating a forum as an official meeting.

## Contract and implementation

The [forum handoff contract](../superpowers/specs/2026-11-07-council-accountability-design.md#campaign-collection-and-forum-attribution)
keeps transcription and speaker labeling outside the website. The owner personally
watched both recordings, verified the supplied labels, and identified the unlabeled
spans as moderator filler. That verification is accepted; no further labeling is
required from the owner. Caption wording/timing flags remain distinct from speaker
identity verification.

Members → Campaign sources → Import forum accepts a `forum-speaker-desk` version 1
JSON export, organizer, forum/election dates and reviewer confirmation. The adapter
checks the embedded caption hash, reproduces the export's word count, and applies
its ordered word ranges. It removes rolling-caption repetitions rather than
repeating the same utterance. The original JSON bytes, source hash, every retained
word, speaker labels, caption times and character locations are stored privately
in the source version. The signed-in importer and version timestamp record who
accepted the handoff and when. No transcription editor or provider is added.

An explicit reviewer choice identifies otherwise unlabeled words as moderator
filler. Without that choice, those words remain unattributed. Both paths preserve
the words. Replacing a transcript retains the previous source and attribution;
duplicate initial uploads cannot undo a correction. Generic article edits cannot
detach a forum from its original file. Existing article version keys remain valid
when the new transcript field is empty.

The existing shared campaign job handles sufficiently small prepared sources,
using its existing spending and retry admission. Returned supporting quotes must
fall within that participant's verified speaker span; another candidate's words,
unattributed text or reviewer-identified moderator filler cannot become their
accepted statement. All candidates' results are retained. An unresolved civic
identity can later resolve through existing publication without another AI call or
an inferred office. Export-metadata changes with identical analysis input reuse the
completed response. Reads/imports do not call AI.

## Real source verification

Two original exports were imported into an isolated copy of the already-synced
civic data, alongside the retained HTR source. The local archive also keeps the
HTR article material for all candidates. No new production copy or backfill ran.

| Supplied source | Words retained | Prepared characters | Original bytes |
| --- | ---: | ---: | ---: |
| [March 7 League of Women Voters forum](https://www.youtube.com/watch?v=L7V9c2_RGWE) | 12,869 | 68,863 | 654,039 |
| [March 12 Two Rivers Business Association forum](https://www.youtube.com/watch?v=L9Tlws24jm4) | 10,422 | 57,069 | 534,231 |

Both preserve Bittner, Brandt, Derby, Andrew Quackenbush and Jeff Dahlke, along with
the moderator and any labeled audience speaker. Original hashes, full word counts
and every prepared-text character range were checked. Replacing each source twice
with unchanged input kept one version. The existing civic identities, offices,
2,157 votes, HTR statements and request records remained unchanged.

Both full forums exceed the existing 50,000-character analysis limit. They remain
saved in full with processing held as oversized; no text was truncated and no
forum statements were generated from these real files. Bounded shared processing
of longer transcripts is subsequent work. These checks do not establish provider
accuracy or complete the forum-analysis feature.

Real HTTP reads retained the complete prepared text and original exports for both
forums. Phone browser verification uploaded the actual League file through the
replacement form and returned to the same saved version, retaining Andrew and
Jeff. Desktop inspection covered the Business Association source. A UTF-8 upload
failure exposed by these actual files was fixed, and the regression export now
contains non-ASCII punctuation. The original files/full transcripts remain private
and are not committed to Git.

## Execution and demonstrated defect detection

Initial application revision: `4cf56f2`, based on PR #279 (`eb81fee0`). Local
execution uses Ruby 4.0.9, PostgreSQL and Chromium. Ordinary/browser tests run
serially per database; real-source acceptance uses a separate database without
fixture loading. Authentication for the manual real-data browser check uses a
local test operator session; the automated browser journey exercises the existing
email sign-in harness. Native passkey ceremony is unchanged and not revalidated.

The migration adds one JSONB snapshot field to each source table. After local
migration, `bin/rubocop -A db/schema.rb` ran and the schema diff was inspected:
only those fields and the schema version changed. Shared gem configuration and
development boot with a read-only database query passed.

- `bin/rails test test/integration/prepared_campaign_forum_intake_test.rb test/jobs/prepared_campaign_forum_extraction_test.rb test/integration/campaign_source_intake_test.rb test/jobs/extract_campaign_source_job_test.rb test/integration/campaign_extraction_test.rb test/jobs/campaign_statement_publication_test.rb test/jobs/reconcile_campaign_sources_job_test.rb test/views/admin_view_hygiene_test.rb`:
  final result is recorded in the PR, including the export-metadata reuse and
  ordinary-reader assertions.
- `bin/rails test`: 2,489 tests, 17,089 assertions, no failures/errors, one existing
  fixture-dependent PromptRun skip. The later focused rerun additionally verifies
  that exporting identical content with a changed saved-at timestamp reuses the
  completed analysis; exact-head hosted CI is recorded in the PR.
- `CHROME_BIN=/usr/bin/chromium bin/rails test test/system/prepared_campaign_forum_journeys_test.rb test/system/campaign_source_intake_journeys_test.rb`:
  two journeys, 58 assertions, no failures/errors/skips. The forum journey checks
  upload, retained source, replacement, later read, historical file disclosure and
  390px fit. Original article intake remains covered separately.
- `bin/rubocop`: 770 files, no offenses. `git diff --check` and the parser's
  `ruby -c` check pass.
- Real-file service/HTTP/browser checks above make zero paid calls. Existing
  analysis transport is replaced only by deterministic responses in regression
  tests; the real full forums stop before provider construction.

A clean baseline and restored rerun each passed two tests/29 assertions. A
process-local fault removing the speaker-span check caused the intended assertion
to fail: an incorrect attribution was accepted instead of held. A second fault
removed the admin guard; after an allowed admin read, an ordinary account with a
passkey received private source content (200 instead of the expected redirect).
Both faults remained isolated and were removed. These demonstrate detection of
those conditional defects, not their frequency in production.

Implementation tests, real-source preservation, browser behavior and fault checks
are separate evidence. Full transcript extraction, paid accuracy evaluation,
semantic campaign/action comparisons, production import and deployment remain
outside this slice. No paid AI, production operation, merge or deployment ran.
