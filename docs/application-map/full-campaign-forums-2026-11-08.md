# Whole prepared forum requests: November 8, 2026

This bounded BG-08/ADM-21 extension under #239 and parent #234 makes the two
owner-supplied prepared forums eligible for whole-source request preparation.
The [handoff contract](../superpowers/specs/2026-11-07-council-accountability-design.md#campaign-collection-and-forum-attribution)
requires all candidates, question context, qualifications and closing statements
to survive shared analysis. The earlier [intake slice](prepared-campaign-forums-2026-11-08.md)
retains the sources and verified labels; its 50,000-character analysis limit
held both actual files before any request could be prepared.

## Bounded implementation

The existing campaign request builder accepts a complete prepared forum up to
100,000 source characters. Above 50,000 characters, it explicitly requests at most
32,000 completion tokens, allowing room for the existing output contract's full
answer passages and separate evidence-bearing statements. Articles and shorter
forums retain their existing 50,000-character / 8,000-output-token boundary.
No segmentation service, extra per-candidate calls or new schedule is added.

The shared prompt now identifies forum question/intro context, opening and closing
answers, verified speakers and moderator filler. It still requests every distinct
supported statement with conditions, timeframe and exact source passages. Prompt
instructions are not proof of completeness or accuracy with a real provider.

The exact rendered parameters, including the larger output cap, remain bound to
the existing request estimate and spending reservation. An allowance permitting
only 8,000 output tokens cannot dispatch the larger request. Missing authorization
pauses without consuming an attempt; the two-attempt limit remains unchanged.
Non-stop responses remain incomplete even if their JSON parses. Oversized inputs,
incomplete/uncertain work and already prepared stages are not automatically reset
or re-priced. Previously held stages remain inspectable; this change applies when
preparing a new stage, not as a production recovery/backfill operation.

## Actual source checks

Both original files were imported into a separate local database using the
already-synced civic data and retained HTR baseline. No production copy ran.
Original bytes, caption hashes, all words, speaker spans and all five candidate
names remain intact. Each fully rendered request contains its entire prepared
body, including the end. Both requests declare the 32,000-token output ceiling.

| Source | Retained words | Prepared characters | State without authorization |
| --- | ---: | ---: | --- |
| March 7 League of Women Voters forum | 12,869 | 68,863 | Budget paused, zero attempts |
| March 12 Two Rivers Business Association forum | 10,422 | 57,069 | Budget paused, zero attempts |

Repeating each import/job twice retains one source version, creates no request or
reservation and makes no provider call. The existing members, offices, 2,157 votes
and 11 retained HTR statements remain unchanged. Admin HTTP reads retain both
complete transcripts, original JSON, Andrew and Jeff, and the revised offline
cost estimate. No real forum statement or conclusion was generated.

The existing offline estimator now includes the larger output ceiling. It still
uses a conservative byte-based planning allowance and inherited checked pricing;
it does not measure input tokens, authorize paid work or prove provider costs.

## Execution and limits

Based on PR #281 (`58daa63`); the PR records final exact-head CI and runtime
results. Local execution uses Ruby 4.0.9 and PostgreSQL, with a separate real-data
database and deterministic provider transport for application regression tests.
Shared gem configuration and development boot with a read-only query passed.

- `bin/rails test test/integration/full_campaign_forum_test.rb test/jobs/prepared_campaign_forum_extraction_test.rb test/jobs/extract_campaign_source_job_test.rb test/integration/campaign_cost_preflight_test.rb`
  exercises full input through transport, persisted results, a later admin read,
  five candidates / ten distinct answers, the closing qualification, request reuse,
  input ceilings, insufficient output allowance and incomplete-response retention.
- The full application suite, RuboCop and exact-head hosted checks are recorded in
  the PR. No new browser controls or authorization rules are introduced.
- Actual-file service and HTTP checks above make zero paid calls. The prior intake
  slice separately tested the real browser upload path. This slice does not claim
  another real browser upload or a native passkey ceremony.

The isolated truncation experiment and restored test result are recorded in the
PR. Its fault removes the end of the provider input while leaving the saved source
intact; the complete-input assertion must fail. This demonstrates detection at
that boundary, not real-model semantic coverage.

Provider accuracy, actual token usage and complete forum extraction remain a
separately authorized bounded evaluation. Production prompt changes must follow
the existing deploy-before-populate ordering. No paid AI, production operation,
merge, deployment or production template update ran.
