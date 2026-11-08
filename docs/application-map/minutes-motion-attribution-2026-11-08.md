# Preserve explicit minutes motion attribution — November 8, 2026

BG-02; supports the existing-analysis reuse work under #234/#243. The binding
Development Plan requires verified mover/seconder names and their source excerpts
to survive meeting analysis into the topic pipeline. Roster names establish
spelling and disambiguation, not an unnamed speaker's role.

## Observed problem and change

Saved local recaps contain exact motion-role excerpts but null mover/seconder
fields. The validator recognized active phrasing such as a person moving or
seconding, but rejected the city's passive `Motion made by` / `seconded by`
phrasing. It also could not distinguish the B. LeClair and D. LeClair initials.

The existing validator now recognizes these explicit clauses, a named member
amending their own motion, and initials that uniquely identify a roster member.
Repeated roster/roll-call names count once. Clause punctuation keeps the mover
before a comma from being incorrectly accepted as the following seconder.
Existing source-quote checks still run, and ambiguous initials remain unresolved.
This adds no source-analysis stage, prompt change, scheduling or AI request.

## Real-source verification

A read-only replay used three agenda items from retained local minutes for
[September 28, 2026](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Minutes-76348c2868fa4372b307afb801be3f7a.pdf)
and [October 5, 2026](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Minutes-4e30dcfdf4c24c09833868015016035d.pdf).
Each retained role quote was confirmed in that meeting's extracted minutes text.
Expected names were checked against those clauses and the local attendance names.

Replaying correctly attributed input retained **0 of 6 roles with the old
validator and 6 of 6 with this correction**: Bittner/Brandt, Brandt/Darla LeClair,
and Darla LeClair/Bill LeClair. The older raw provider responses were no longer
retained, so this does not establish what every original response contained.
It demonstrates the validator's rejection of supported input in these actual
source forms. No saved real summary or vote was rewritten; no paid call ran.

## Implementation and workflow checks

Ruby 4.0.9 and PostgreSQL; isolated synthetic test database; patch based on
`26c0e01b01e4a7747dfc56100fe3c9e40e8f79dd`.

```sh
bin/rails test test/integration/meeting_motion_attribution_test.rb \
  test/services/ai/meeting_analysis_evidence_validator_test.rb \
  test/services/topics/recent_item_details_builder_test.rb \
  test/jobs/summarize_meeting_job_test.rb
bin/rubocop
git diff --check
```

The targeted runner executed **64 tests / 169 assertions**, with no failures,
errors or skips. RuboCop inspected 870 files without offenses. The workflow test
stubs external response transport, runs the actual meeting job and validator,
then checks persisted meeting roles, the actual topic-analysis input, shared
briefing context, and persisted topic output. The existing vote's complete
attributes and the vote/motion counts remain unchanged. Exactly the existing
three simulated requests run: meeting analysis, topic analysis and topic prose.
No real AI interpretation or new browser/UI behavior is claimed by this test.

After a passing baseline, temporarily restoring the prior validator made the
workflow's persisted-role assertion fail. Restoring this correction passed again
(1 test / 11 assertions). The unit cases also reject swapped roles, shared
surname ambiguity and shared-initial ambiguity. Existing transcript cases pass.

The correction applies to ordinary future analysis. Existing saved summaries
remain unchanged. Reusing their already-supported motion roles in personal
profile/campaign comparisons is subsequent work; this parser fix does not claim
that all attributed work or campaign matching is complete. No backfill, merge,
production operation or deployment occurred.
