# Approved local council catch-up — November 8, 2026

The owner approved the [prepared subset](council-history-proposal-2026-11-08.md)
with a $10 total ceiling. This was executed in an isolated copy of existing local
data, using official minutes and the retained campaign sources. No production
data was copied, no broad meeting/topic backfill ran, and nothing was merged or
deployed. The accepted $10/month recurring comparison ceiling remains inactive.

## Useful results and retained gaps

| Boundary | Result |
| --- | --- |
| Selected source PDFs → retained text | All 20 PDFs retained and checked against the prepared hashes/dates; 11 used the existing local OCR path. |
| Minutes → shared records | 19 vote stages and 19 attendance stages completed; 19 meetings published 98 motions, 853 vote records and 327 attendance entries. Attendance entries include staff/guests; these totals are not voting or attendance denominators. |
| Initial cohort | Added 92 Bittner, 94 Brandt and 96 Derby vote records, including recorded non-voting dispositions. Other eligible members share the same extraction. |
| Existing records | All prior 2,174 votes, 752 motions, 2,260 attendance entries, 715 retained statement rows and completed campaign analyses remained unchanged. |
| Shared promise/action comparisons | 55 pairs completed; two remain unpublished after their two allowed source-quote validation attempts. Review rejected 18 overbroad positives across three batches. The effective results are 10 direct, 44 not direct and one insufficient-evidence pair. These are relationships, not promise grades. |
| Retained forums → topic links | Both stages completed: 43 new candidates processed, all 133 earlier decisions reused. Across the combined 176 decisions: 75 matched, 99 no-match and two unresolved. |
| Unchanged replay | Replayed every completed prepared stage with provider construction forbidden: zero calls and unchanged record, citation, topic-link and reservation counts. |

The local command was terminated during the July 28, 2025 vote request. No response
was saved. Its receipt is explicitly uncertain, its full reservation remains, and
neither it nor the paired attendance stage was redriven. All other selected minutes
completed. This gap and the two held comparisons do not imply that a member did
nothing. New comparisons created by forum links or historical facts were not
silently added to the approved request list.

The real source review found that common terminology had produced false
connections: general affordable-housing funding did not establish work on the
named Hamilton site or remote-worker recruitment; financing-district closures and
a budget vote did not establish the claimed broader objectives or skills. The
[reviewed rejection mechanism](campaign-match-rejections-2026-11-08.md) removes
these connections while retaining raw evidence and cached results. A separate
Hamilton community-vision decision remains directly related, with its limited
scope preserved. This is bounded source review, not proof of universal accuracy.

## Spending and admission

- **54 requests dispatched**, including two validation retries and the one
  uncertain request. Every request used `Ai::OpenAiService` and the existing ledger.
- **$4.242167 reserved** against exact prepared request ceilings, within the
  owner's $10 maximum. Reported tokens price at **$0.736803** using the conservative
  approved rates; this is not the provider's invoice. The unknown request retains
  **$0.076165** separately, giving $0.812968 when added to that usage estimate.
- The new explicit supplement preserved the original day/month approvals. After
  interrupted/held batches, each continuation's maximum was the original $10 less
  **all** earlier reservations. No balance was refunded or allowance enlarged.
- One request at a time, two attempts per stage, exact request parameters and the
  prepared request-count limit were retained. Every temporary run is now revoked;
  the monthly recurring policy is still empty.

The general topic/meeting recap pipeline and newly created comparison candidates
remain outside this run. Ordinary downstream jobs were captured without execution.
No new recurring schedule, monthly rewrite, production activation or full-term
absence verdict is included.

## Verification and delivery

Application changes build on `d7b76f3` (PR #308), whose complete CI and build/smoke
checks passed. The match-correction change has 19 targeted PostgreSQL tests / 180
assertions, an HTTP defect-detection check, and clean RuboCop; its own PR carries
the final revision and CI result. Providers in implementation tests were deterministic.

Real-data checks preserved upstream/downstream counts, compared a sewer-project
award and a facade-grant deadline extension against their official roll calls,
and exercised a phone member-page search through the meeting's official minutes
link. Final phone/desktop views check the corrected campaign panels separately
from the ordinary voting record. Prior full cohort/access acceptance is reused;
this run does not claim actual Google indexing or complete historical coverage.

Automatic code/security reviews on #308 again declined for usage limits. That is
a review gap, not a returned code finding. Parent #234 and historical rollout #245
remain open for the agreed review/delivery boundaries and any separately approved
broader history.
