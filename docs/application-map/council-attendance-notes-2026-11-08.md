# Documented participation notes — November 8, 2026

Scope: #237 under #234; RES-10/11 and the existing minutes fact-publication
workflow. The [Council design](../superpowers/specs/2026-11-07-council-accountability-design.md#attendance)
requires documented arrivals, departures and remote participation to survive.
A meeting attendance status does not establish a ballot on each motion.

## Concrete source and change

The [March 17, 2026 Council minutes](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Minutes-0d17b38e1afb4adfa825e8ffd1071731.pdf)
list Bonnie Shimulunas as absent at roll call with an arrival at 6:26 PM
(page 1); the clerk repeats the arrival on page 3. The local accepted attendance
already says present. Its missing arrival detail is the reason for this patch.

The existing attendance response can now include short participation excerpts.
Publication retains distinct, locatable excerpts for already recorded attendees;
unlocated/malformed notes remain in the retained response without blocking the
valid roll call. Whitespace is normalized, not paraphrased. No person, status or
ballot is created from a note. The existing prompt explicitly treats documented
late/partial/remote participation as attendance, not whole-meeting absence.

The service-scoped member list displays the note beneath its meeting link,
inside the existing closed disclosure. Counts and vote logic are unchanged.
For duplicate meeting aliases, notes come from the displayed source meeting;
this patch does not reconcile separate conflicting source notes. The legacy API
and profiles without evidenced service periods are not expanded here.

One JSON column and an optional field in the existing request suffice. The
4,000-token output ceiling, spending admission and nightly schedule are unchanged.
Old completed responses remain reusable without notes; deploying/populating the
new prompt does not reprocess historical minutes or perform another AI pass.

## Verification

Environment: Ruby 4.0.9, isolated PostgreSQL test database, Chromium, patch on
`f9f4886`. Provider transport is deterministic; no real-provider accuracy claim
or paid call is made.

Commands run:

```sh
bin/rails db:migrate
bin/rubocop -A db/schema.rb
bin/rails test test/integration/member_council_attendance_test.rb \
  test/jobs/extract_committee_members_job_test.rb \
  test/jobs/minutes/fact_publication_test.rb \
  test/services/ai/extract_committee_members_test.rb
bin/rails test test/system/member_council_attendance_journeys_test.rb
bin/rails prompt_templates:populate prompt_templates:validate
bin/rubocop
git diff --check
```

- The application group passes 58 tests/287 assertions. The new full job →
  matching-source publication → stored note → later HTTP read case preserves
  the named yes vote, leaves the earlier unrecorded ballot empty and makes no
  additional calls or replacements on two unchanged replays. Existing tests
  cover completed pre-note responses and prompt-change reuse.
- The phone journey passes one test/14 assertions: open attendance, read the
  note, navigate to the meeting, return/reload and retain the note and correct
  counts without horizontal overflow. Its data is explicitly synthetic.
- Removing the note-publication call after the passing baseline makes the
  persisted-note assertion fail with an empty array (one failure, zero errors).
  Restoring it passes the focused test with 20 assertions. The fault harness's
  first output-format check failed after observing that intended failure; its
  `ensure` equivalent restored the code, and the green rerun was run separately.
- The fresh isolated database initially lacked prompt templates. Local populate
  followed by validation passes; this was not a production population operation.
  RuboCop passes; the schema diff contains only the migration version and column.

## Real-source replay and limits

In a disposable copy of existing local civic data, an explicit rollback replay
fed the actual March 17 minutes and accepted local attendance/votes through the
normal jobs, adding only the visually checked arrival excerpt to the deterministic
attendance response. The note survives publication and unchanged replay with zero
new provider calls. All six motions and their previously recorded ballots survive.

Forcing this legacy meeting through publication also adds six attendance-derived
absence markers for the two wholly absent members. That is existing projection
behavior, not an effect of the note; no earlier ballot is invented for Shimulunas.
The replay rolled back all data changes. It is not a proposed historical repair
or evidence that old minutes should be re-extracted to obtain this optional detail.

The local pilot lacks a sourced service period for Shimulunas. None was invented:
the actual-source check proves the stored detail, while the synthetic browser
journey proves its service-scoped rendering. A full real Shimulunas profile
journey remains outside this initial three-member pilot. Original local databases
and previews were preserved. No broad backfill, production operation, merge or
deployment ran.
