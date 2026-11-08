# Campaign forum pilot: November 8, 2026

This BG-08/ADM-21 evaluation uses the owner's two complete, speaker-verified 2024
forum exports and an isolated copy of existing local civic data. The binding
[campaign handoff and cost contract](../superpowers/specs/2026-11-07-council-accountability-design.md#campaign-collection-and-forum-attribution)
requires shared extraction, preserved context, explicit spending limits and no
additional calls for unchanged inputs. It does not equate a located quotation
with a verified interpretation or complete coverage.

## Observed defect and bounded fix

The first real response used `original_question` and `full_answer_passage` where
the parser expects `question` and `passage`. The prompt described those concepts
without declaring their literal field names. The parser accepted the outer
arrays and marked the stage completed, while every statement was unresolved.
No statements from that evaluation reached member pages.

The shared prompt now names the answer keys explicitly and tells the model to
use the reviewed speaker labels, including adjacent text for a unique name
reference. Misspelled spoken-name captions do not replace reviewed labels.
Missing or blank question/passage fields now fail response validation, retain
the original receipt and publish nothing. The existing attempt and spending
limits still apply. There are no candidate names, election-specific branches,
new schedules, or per-member model calls in the implementation.

This changes validation for newly processed responses. It does not rewrite
completed historical extractions or reset an uncertain/incomplete stage. The
initial evaluation remains retained; the corrected prompt was evaluated in a
fresh local copy with the earlier reservation deducted from the combined cap.

## Validation and limits

The deterministic job test reproduces the actual response-key mismatch through
the provider boundary, then checks failed status, intact receipt, no published
statements and one consumed attempt. Existing complete-forum, speaker-attribution,
spending, reuse and later member-read checks remain in the focused suite.

- Ruby 4.0.9, PostgreSQL; application tests use a separate synthetic test database.
- `bin/rails test test/jobs/extract_campaign_source_job_test.rb test/integration/full_campaign_forum_test.rb test/jobs/prepared_campaign_forum_extraction_test.rb test/integration/campaign_cost_preflight_test.rb test/integration/member_campaign_record_test.rb test/integration/campaign_topic_matching_test.rb`: 34 tests, 412 assertions, no failures/errors/skips.
- `bin/rubocop`: 771 files on the PR branch (788 on the integrated local preview), no offenses.
- Representative defect detection: removing the new answer-field guard causes
  the intended failed-versus-completed assertion to fail (one test, one failure).
  Restoring it returns the focused suite to green. Syntax/boot failure was not
  counted as detection.

Real-provider evaluation is separate from deterministic implementation testing.
Exact prepared requests and token/rate assumptions were recorded before dispatch;
reservations include conservative input/framing and cache-write allowances.
Provider usage remains distinct from reserved allowance. No provider-side retry
middleware is configured, and no automatic recovery call was made.

The corrected first forum returned five candidates and preserved their opening
and closing answers. Its 45 answers contain 76 statement candidates, of which 41
pass exact source checks. Most of the 35 held statements join separated excerpts
with ellipses. Source-turn comparison also identifies omitted material; it does
not establish semantic completeness. Captions retain wording errors even when
speaker attribution is verified. These are concrete limits for subsequent
exception handling and source review, not reasons to discard the supplied files.

Complete sources, raw responses and unmatched candidates remain in the private
local archive. Locating a passage does not certify a historical claim, grade a
promise, or justify showing every extracted statement in the resident interface.
The source collection can be comprehensive while the page's presentation remains
selective. No production changes, merge or deployment were performed.

The second forum returned five candidates, 40 answers and 100 statement candidates;
90 pass exact source checks. Its raw output also attempts to reinterpret a
reviewed speaker label for one leisure answer. Reviewed labels remain authoritative;
no statements from that empty answer were published. Coverage is therefore not
certified merely because all five names appear in a response.

The complete second matching context is approximately 113,000 characters, beyond
the previous 100,000-character limit. The new limit is 150,000, without increasing
the 8,000-output-token ceiling or granting spending authority. A boundary test
checks complete input at the limit and refusal one character beyond it. Existing
oversized-context checks continue to prove retention without a provider call.

Both shared matching calls completed. Later HTTP reads contained the expected
stored statements for all three elected members; repeated extraction/matching
jobs and page reads made zero additional provider calls. Existing votes, people
and offices were unchanged. Support for the city-manager form of government did
not acquire a link to a particular manager's employment record in this sample.
These checks establish pipeline flow and bounded reuse, not editorial approval
of every summary or topic association. The active UI-review preview was not
changed, and no new browser control was introduced by this patch.

The larger-context defect experiment truncates provider input after the size
check; the complete-context assertion fails. Restoring the original input returns
the focused boundary test to green. Full source material and provider receipts
are retained privately, not committed as public test fixtures.
