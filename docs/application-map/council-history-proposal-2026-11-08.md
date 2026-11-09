# Council history proposal — November 8, 2026

Resident question: which parts of a member's record are missing, and what useful
history can be added without paying to repeat accepted work? The current member
record has passed [bounded implementation acceptance](council-profile-integration-2026-11-08.md#final-bounded-implementation-acceptance).
This proposal is an approval point under #245, not an executed backfill.

## Available history and explicit gaps

The [source/stage manifest](council-history-manifest-2026-11-08.json) covers the
119 public Council-named listings from April 1, 2024 through November 8, 2026.
The initial three members' service begins April 16. Shared source processing
serves every eligible member; the initial cohort is not a separate extraction.

| Disposition | Listings | Treatment |
| --- | ---: | --- |
| Existing minutes/records available | 49 | Reuse accepted votes, attendance, summaries and comparisons. Some fields remain incomplete; availability is not complete coverage. |
| Missing facts with a checked minutes URL and sized PDF | 20 | Prepared vote and attendance requests; no import or AI call yet. Eleven PDFs need local OCR, already sized without paid processing. |
| City-page access unresolved | 35 | 33 challenge responses and two unsuccessful page requests. Do not interpret these as missing minutes or absent meetings. |
| Genuine meeting pages without a minutes link | 3 | October 19, October 26 and November 2, 2026; await minutes. |
| Joint/listening listings | 7 | Retain separately; do not infer Council attendance or votes from the title alone. |
| Cancelled listings | 5 | Exclude from held-meeting and attendance denominators. |

These are listing classifications, not an attendance denominator or a completion
percentage. Two existing local records match the listing only by time; their
identity mapping remains held rather than creating duplicate meetings. No source
is treated as free analysis merely because its text is unavailable.

The 20 prepared sources range from April 22, 2024 to August 4, 2025. Source URLs,
PDF hashes, stage dispositions, request digests and conservative ceilings are in
the manifest. Public-page reads and local PDF/OCR sizing made no database writes,
queued no jobs and called no provider. The original PDFs are retained privately;
the repository does not contain a full source mirror. OCR text was sized for
planning, not approved as a published interpretation.

## Concrete local catch-up option

**Proposed one-time ceiling: $10**, in a disposable local copy, for the following
prepared work only. The broader/full-term backfill stays deferred.

| Work | First attempts | Ceiling with one retry each |
| --- | ---: | ---: |
| Vote and attendance extraction from the 20 newly available minutes | 40 requests; $1.801817 | $3.603634 |
| Already-pending comparisons from existing history: 57 uncached pairs in 11 contexts | Up to 11 batches; $1.692160 | $3.384320 |
| Two retained forum-topic catch-up requests | 2 requests; $0.547581 | $1.095162 |
| Prepared total | Up to 53 requests; $4.041558 | **$8.083116** |

The comparison estimate deliberately retains cached pairs in the request-size
ceiling; those decisions must be reused rather than purchased again. New topic
links or historical votes can create later comparison candidates. Those are not
in the 53 prepared requests and must remain paused until separately prepared and
admitted within an agreed allowance. The $10 is a cap, not a commitment to spend
the balance or a claim that it completes all campaign connections.

The actual parameters use the existing vote/attendance request builders and
current templates, with Terra for votes and Luna for attendance. Existing
conservative [pricing assumptions](council-saved-history-2026-11-08.md#measured-comparison-workload-and-recurring-proposal)
apply; the current checked rates expire November 21. Estimates are not invoices.

### Execution after personal approval

1. Use a disposable local copy with ordinary background workers stopped. Preserve
   accepted records. Import only the manifest's 20 source identities, retain PDFs,
   and use the existing deterministic text/OCR path. Verify source/meeting dates
   and source hashes before preparing the exact staged requests. A mismatch is a
   hold, not permission to substitute another document.
2. Use the existing `CouncilProfiles::ExtractMinutesJob` and shared campaign
   matching stages. Do not run `backfill:run`, `backfill:reprocess`, the general
   discovery pipeline, or unlisted follow-up jobs. Record pending downstream work
   without dispatching it. Reuse existing completed stages and negative matches.
3. Authorize only exact prepared stage/request digests using the existing shared
   reservation ledger: $10 cumulative run ceiling, at most $0.60 per request,
   106 requests including retries, one concurrent request, at most two attempts
   per stage, and matching day/month headroom. Check actual input/output limits
   against the prepared requests and expire the run after the approved day.
   This one-time allowance is separate from recurring processing.
4. Proceed in five-meeting batches, then the existing campaign catch-up. Use the
   existing completed stage/request receipts as checkpoints. Unchanged resume is
   free; an uncertain response keeps its reservation and does not auto-retry.
   Stop on exhausted allowance, expired pricing, oversized input or unsupported
   output. Do not reset attempts or enlarge the allowance to finish a batch.
5. Check persisted counts and selected meaningful decisions through the member
   page and source links. Retain coverage gaps, revoke the temporary allowance,
   and report what was added and what remains held. Production synchronization,
   merge and deployment are separate authorizations.

## What this does not price or complete

This is a bounded records/campaign catch-up, **not the complete historical meeting
and topic reporting pipeline**. `SummarizeMeetingJob` also generates topic summaries
and other follow-up work; `ExtractTopicsJob` can trigger additional classification
and triage. Those existing paths are outside the new stages' request reservations.
They must not be silently included in a supposedly capped historical run.

Existing summaries and topic links are reused. Regenerating old meeting recaps,
creating missing historical topic links and broad topic narratives, unavailable
sources, and complete formal-case discovery remain outside this $10 option.
Further history can be priced when its source/stage scope is concrete. No second
general minutes-analysis system or billing redesign is proposed to prepare this
decision. The current partial record remains useful without these additions.

A separate **$10/month incremental comparison ceiling** is proposed in #238 for
new evidence after activation; existing site AI and one-time work are excluded.
Neither the one-time nor recurring allowance is enabled by this document.
No current-term record receives a full-three-year absence/broken-promise verdict.
Parent #234 and historical rollout #245 remain open.
