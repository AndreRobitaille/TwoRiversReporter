# Council source quotations across page footers — November 8, 2026

Scope: BG-09 → RES-10/11, #238/#243/#245 under #234. Source quotations must
remain traceable to retained official text; unchanged usable responses should
not require another paid request. This addresses a failure observed in the
bounded real-source pilot, not a hypothetical correction framework.

## Observed problem and bounded correction

The April 6, 2026 Council minutes contain a sentence split across pages 6 and 7.
The extracted text includes the page footer between “expected to” and “improve”.
The provider omitted that footer in its quotation. The strict parser therefore
held the complete response, despite the passage otherwise matching the source.

`CouncilProfiles::SourceQuote` first accepts exact whitespace-normalized matches.
For a mismatch it may restore a page-number footer only when the retained page
hashes, full page sequence, joined text and raw standalone footer establish the
boundary. It returns the original contiguous source passage, including the
restored footer. Numbers within the text, missing pages and changed page text
do not get that exception. No fuzzy quotation matching or rewritten source
text is introduced; source/request identity and completed analyses remain stable.

Before another dispatch, failed issue extraction can revalidate its latest
complete received response. A successful recheck publishes through the same
parser, queues ordinary dependent matching and preserves the receipt, reservation
and attempt count. An uncertain or truncated transport is not accepted this way.
Unusable responses still require existing budget and attempt controls for any
further provider call. No new scheduler or automatic spending allowance is added.

## Executed evidence

Isolated branch `codex/council-source-quote-footers`, base `39d4dcb`, Ruby 4.0.9,
PostgreSQL synthetic test database; deterministic external responses.

- Source-footer and existing issue-update checks passed 16 tests/155 assertions.
- The restored final selection, adding advocacy, staff comparisons and campaign
  issue matching, passed 42 tests/403 assertions with no skips.
- Representative faults removed the raw-footer boundary check and bypassed
  cached-response recovery. The former incorrectly accepted an inline number;
  the latter left the valid saved result budget-paused. Each intended assertion
  failed, then the fault was restored and the full selection passed.
- Full RuboCop passed across 866 files before the final explicit Digest require.
  The require and final documentation were checked subsequently.

The separate real-source pilot used the owner's existing local data and bounded
AI authorization, not synthetic profile content. The May 5, 2025 minutes produced
one rental-lighting amendment and one separate ordinance update. Shared comparison
of the actual campaign statements rejected the unsupported lottery/residency
connection. The April 6 response was held for the footer mismatch; this correction
recovered its ten updates and ten attributed actions from the original receipt
with **zero additional provider calls**, unchanged attempts and unchanged votes.
These counts demonstrate retention, not independent semantic accuracy of every
generated claim. No explicit staff recommendation was extracted from that sample.

The first pilot transport was rejected for missing local credential setup. Its
receipt and conservative reservation were retained; a bounded manual retry used
the existing local credential. All pilot runs were revoked after completion.
Recurring processing remains disabled, and no full-term backfill, production
operation, merge or deployment ran. Full source completeness, positive formal
case validation, wider model accuracy and final rollout remain open.

Official sources: [May 5, 2025 minutes, page 5](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Minutes-0a069b395b7b4040b2b46a2a7190f8f0.pdf)
and [April 6, 2026 minutes, pages 6–7](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Minutes-92069de44a594aa6990824383b8252fd.pdf).
