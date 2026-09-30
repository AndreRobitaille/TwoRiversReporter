# WPPI transcript analysis repair

Meeting 268 was the September 28, 2026 City Council Work Session. Its
WPPI item belongs to topic 969 and concerns Resolution 26-141,
Amendment No. 3: an 18-year power-supply contract extension from 2055
through 2073.

The corrected SRT supplied by the operator exactly matches the stored
transcript document 904 after the application's SRT parser runs:
100,871 characters. At 1:51:36 the recording captions show a motion to
sign the contract and move forward; at 1:51:52 they show a second;
at 1:52:25 they announce that the motion carries.

The operator verified the identities and tally on September 30:

- Mark Bittner moved to sign the contract and move forward.
- Doug Brandt seconded.
- The motion passed 6–2.
- Katherine Dahlke and Adam Wachowski voted no.
- Scott Stechmesser was absent.

These are recording-review facts. The captions alone garble part of the
roll call. Do not claim the tally was established by approved minutes
unless those minutes have subsequently been obtained. The meeting was
a work session; the meeting label alone establishes no conclusion about
the legality of the action.

## Failure and repair

The historical `analyze_meeting_content` PromptRun 16095 sent exactly
100,000 characters. The contract motion begins at character offset
100,165; the second and announced outcome also follow the cutoff. The
result incorrectly said neither substantive item received a final vote.

The generated WPPI title also differed from its agenda title. Exact
normalized title matching therefore returned no WPPI item details in
either `SummaryContextBuilder` or `RecentItemDetailsBuilder`. Topic
analysis fell back to the agenda's proposed action even though a meeting
analysis existed.

The repair preserves complete primary and supplementary transcript text,
supplies stable agenda IDs to meeting analysis, and shares a
meeting-scoped matcher across topic summaries, briefings, and pruning.
Unmatched substantive business is preserved. Structured motion details
carry verified identities forward, and topic claims cite the recording
document rather than treating the agenda as evidence of a completed vote.

## Validation and release handoff

The local replay uses the existing configured analysis model and actual
meeting records. It temporarily loads the three changed prompt templates
inside a rolled-back database transaction. It first analyzes the full
captions alone, then supplies the operator's verified roll-call correction
as recording-review context. It checks preservation across meeting
analysis, per-meeting topic context, and rolling briefing context. Outputs
are saved locally at `tmp/wppi-analysis-268/validation.json`.

The final replay sent all 100,871 characters unchanged. Both topic context
and briefing context retained the 6–2 decision and all five verified
identities. The topic factual record cited transcript document 904; the
rolling briefing's September 28 entry named the City Council Work Session,
motion, second, dissenters, and absence. Its forward-looking text now asks
readers to watch the signed amendment and cost implications rather than
wait for a vote that already happened.

Checks actually run:

- `PARALLEL_WORKERS=1 bin/rails test`: 1,774 runs, 6,933 assertions,
  no failures or errors, one skip. A single worker avoids Bundler temporary-home
  cleanup collisions in this sandbox.
- Targeted meeting analysis, matcher, topic context, briefing, pruning,
  summarization, and prompt tests: 131 runs, 396 assertions, all passing.
- `bin/rubocop --cache false`: 512 files, no offenses. The flag avoids
  writing RuboCop's cache outside the workspace sandbox.
- `bin/rails prompt_templates:validate`: all 20 required templates present.
- `git diff --check`: clean.
- Actual-model replay through `Ai::OpenAiService`: full source text,
  decision, identities, citations, and work-session body preserved; all
  temporary database edits rolled back.

## Comparison controls: September 30

The old and revised pipelines were run against two additional meetings using
`Ai::OpenAiService` and the same configured `gpt-5.6-terra` model. The old code
and three prompt templates came from commit
`dbbfda6142a1ae31121a5637f4ec8ae275ae5760`. These are fresh controlled before/after
runs, rather than a comparison of an old cached answer with a new answer.
Knowledge context, participant spellings, existing motions, and topic history
were held constant. Neither control received the operator's WPPI correction.
The comparison covers meeting analysis, per-meeting topic analysis, and the
rolling briefing. Temporary summary changes were rolled back; each control
verified that its original meeting and topic summaries remained unchanged.

| Control | Before | Revised result | Impact scores, before → after |
| --- | --- | --- | --- |
| Meeting 226, July 27 Council Work Session; fluoridation topic 1012 | Discussion only; no policy decision | Still discussion only, with no invented policy vote; later September 8 decision retained in the rolling briefing | Meeting-topic 4 → 4; rolling topic 5 → 5 |
| Meeting 263, September 21 Council; noise-regulations topic 176 | Meeting analysis recognized the denial, but title matching lost it downstream; topic/briefing treated the request as pending | Recording-based 9–0 denial reaches the topic and briefing; unnamed mover remains unknown, and Bill LeClair's second is retained | Meeting-topic 3 → 3; rolling topic 4 → 4 |

### Boundary counts and source checks

- Meeting 226: source sent increased from 19,463 to 50,168 characters because
  the full 45,705-character supplementary recording replaced the 15,000-character
  excerpt. Both variants have one substantive item and zero policy decisions.
  Its one topic item remains matched, and three recent topic items reach the
  rolling briefing. The July discussion does not displace the later September 8
  vote, 7–2, to end fluoridation October 31.
- Meeting 263: both variants receive the same 96,658-character recording.
  Matching of generated entries to scoped agenda IDs improves from 2 of 9
  entries to 10 of 10. The current noise-topic match changes from zero to one;
  recent briefing items change from two to three, recovering September's denial.
- The September analysis preserves the Hamilton vision and blight resolutions
  as preliminary redevelopment steps, with no approved land purchase or
  construction commitment. Clear roll-call counts remain available, including
  Hamilton's 8–1 vote and the 9–0 noise-waiver denial. The anonymous Hamilton
  no voter stays unknown. Consent and license-appeal voice votes keep null
  numeric tallies.
- September's completed-decision count changes from nine to eight because the
  recording stops during the closed-session roll call. The revised structured
  outcome and tally are null; its summary explicitly identifies the incomplete
  recording. The tenth item is a substantive city-manager report, with no
  fabricated decision.
- July's discussion citations now include both minutes document 799 and
  transcript document 785. This matters for details such as the $12,000 annual
  cost, which appears in the recording beyond the text of the minutes.
  September's denial cites transcript document 896, rather than its agenda.

### Corrections prompted by the controls

The first revised outputs guessed an anonymous Hamilton no voter's identity,
assigned unnamed movers, and occasionally converted a voice vote into a numeric
tally. Prose instructions alone did not prevent those errors. Meeting analysis
now returns source excerpts for motion identities and tallies; a validator
checks them against the supplied record before those fields move downstream.
It distinguishes a named acknowledgment from an addressed mover ("I'll second
Mark" does not identify the seconder), rejects unsupported vote counts, and
retains clear individual responses despite minor caption spelling or punctuation
variation. The original model response remains in PromptRun for audit; returned
analysis contains the validated fields.

The July replay also exposed future status events in a historical meeting's
context. Per-meeting continuity now ends at that meeting's timestamp. A regression
test retains earlier and same-meeting events, excludes later events, and was
confirmed to fail when the date guard was temporarily removed. Rolling briefings
continue to include later meetings.

Item summaries now use factual language with attributed arguments; editorial
interpretation remains in headlines and highlights. Combined minutes/recording
analysis carries both document citations. Topic and briefing prompts distinguish
a denied request from a passed motion to deny, avoiding "motion failed" when
the council unanimously voted to deny the request.

An intermediate noise briefing correctly listed The Spruce Lodge's July 20
approval in its factual record but attributed that dated approval to Heroes
Venture in an editorial pattern. Briefing instructions now require each
pattern's entity, meeting date, event date, and vote to remain tied to the
corresponding factual event. The final replay keeps the venues distinct and
does not repeat that misattribution.

### Limits and saved evidence

Both variants still omit Sari Saubert's Zoning Board of Appeals appointment,
agenda item 3753, despite its presence in the canonical agenda and recording.
This is a remaining coverage issue, rather than an increase in filtered content
introduced by the WPPI repair. The closed-session summary's opening wording
("voted to enter") remains imprecise even though its final sentence and
structured fields correctly report an unknown completed outcome. These controls
support the observed decision-preservation and scoring behavior; they do not
establish complete coverage or flawless wording across all recordings.

Local artifacts retain source snapshots, effective prompts, raw model output,
validated analysis, downstream contexts, and before/after results:

- `tmp/wppi-analysis-controls/comparison-226.json`
- `tmp/wppi-analysis-controls/comparison-263.json`
- `tmp/wppi-analysis-controls/source-226.json`
- `tmp/wppi-analysis-controls/source-263.json`
- `tmp/wppi-analysis-controls/acceptance-checks.json` (16 source/pipeline checks)
- `tmp/wppi-analysis-268/validation.json`

The final WPPI recheck preserved all 100,871 source characters, the 6–2 approval,
all five operator-verified identities, and the City Council Work Session setting
in the topic and rolling briefing. Captions without the operator correction
still establish approval while leaving the garbled tally and identities unknown.
All replay changes remained local and were rolled back.

Production was not changed. The read-only inspection identified running
image `dbbfda6142a1ae31121a5637f4ec8ae275ae5760`; the subsequent inspection
was interrupted and its SSH tunnel closed. Temporary tunnel configuration
was removed and local port 22222 was verified closed.

After release authorization, follow the mandatory production tunnel
playbook. Deploy the code before selectively synchronizing
`analyze_meeting_content`, `analyze_topic_summary`, and
`analyze_topic_briefing`; use the fingerprint-guarded
`prompt_templates:sync_selected` task. Regenerate the meeting recap with
the verified recording-review context above, then refresh its topic
summaries and the WPPI briefing. Verify the closing approval, 6–2 tally,
named dissenters and absence, and work-session setting at every boundary
and on the resident pages. Preserve original documents and do not create
official-minute motion records from captions.
