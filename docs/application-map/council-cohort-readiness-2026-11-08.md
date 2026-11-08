# Council cohort checks and operating-cost readiness — November 8, 2026

Scope: RES-10/11 and BG-09, parent #234 and #238/#240/#243/#245. The owner's
accepted compact panel remains the presentation contract. Personal actions,
Council decisions and subsequent issue outcomes stay distinct; partial evidence
cannot establish full-term inaction. Broad historical processing remains subject
to the owner's approval. This report describes local development, not deployment.

## Real-data cohort check

The combined stack through `cb4cb12` was exercised against the existing local
copy for Mark Bittner, Doug Brandt and Shannon Derby, without fixtures or a new
production data copy. Their documented service starts April 16, 2024. The page
inventory contains 56 known eligible Council meetings; it is not a completeness
claim. Attendance has nine unknown entries for each of these members. The article
and both owner-attributed forums remain present, including retained statements
for candidates who did not win.

A bounded, explicitly limited local provider pilot analyzed two already-loaded
minutes sources once each for everyone. The May 5, 2025 source produced one
Bittner rental-lighting amendment and one separate ordinance update. Its two
campaign comparisons rejected the unsupported connection to a lottery or
owner-occupancy proposal. The April 6, 2026 source produced ten issue updates and
ten attributed actions across participants. The saved response was recovered
from a verified page-footer mismatch without another request (PR #299).

A shared ten-pair comparison of the April source retained four direct links:
the two TID-funded business grants relate to statements by Bittner and Brandt.
Four stronger claims lacked sufficient evidence and two industry-specific
comparisons were unrelated. These outcomes do not establish personal credit,
completion of the improvements or a claimed tax-base effect. No explicit staff
recommendation was extracted; positive recommendation accuracy remains unproven
by this pilot. Policy-adoption text did not create a formal complaint.

Fresh projection reads show eleven shared issue updates for each cohort member
and two, one and three attributed actions respectively. Both saved source stages
and both matching stages were replayed with provider construction prohibited:
zero new calls or reservations, unchanged votes and campaign statements. All
pilot run allowances were revoked; no recurring policy was enabled.

## Small presentation correction

Real grant outcomes exposed an ordering problem: two same-day Council updates
occupied the compact preview, hiding the member's own yes votes in “more records.”
The ordering now keeps newest dates first and, within a date, places personal
votes and recorded work before general issue outcomes. Vote rows already display
the Council result. Outcomes remain separately available through the existing
disclosure; later outcomes still precede earlier actions. No generation, grouping
heuristic, extra visible prose or permanent per-member editing is introduced.

A resident reviewer supported that tie-breaker provided the vote row still shows
what Council decided. This is readability feedback, not validation of the source
claims. The source assertions above were separately checked against the retained
minutes. The original cross-thread review session was unavailable.

## Historical inventory and approval boundary

A read-only query of the public city meeting list, with explicit April 1, 2024–
November 8, 2026 date filters and all six result pages, found 119 Council-named
listings. Five are explicitly canceled; two precede the cohort's service start.
Of the remaining 112, 58 match a local detail URL, two match only a timestamp and
52 have no local match (29 in 2024, 23 in 2025). These are listing counts, not
held-meeting, source-completeness or attendance denominators. Listening sessions,
joint bodies, organizational-title variants, duplicates and source availability
must be reconciled before applying eligibility rules.

No historical meeting details or documents were imported by this inventory, and
no jobs or AI calls were queued. The existing `backfill:run` and
`backfill:reprocess` tasks are unsuitable for the requested bounded operation:
they cover a different date window and enqueue the wider pipeline. Do not use
them as an approved council-profile backfill. A concrete historical run needs an
explicit source/stage manifest, retained checkpoints and an enforced allowance
covering every paid stage it invokes. Existing accepted votes must be reused.

## Recurring cost proposal and limits

The sample-based conservative workload is five minutes analyses, five packet
analyses, ten campaign/vote comparison batches and ten campaign/issue comparison
batches per month. At the prepared sample sizes this reserves about **$6.35 for
one attempt each, or $12.70 if every request uses two attempts**. The full twenty-
pair issue batches are size scenarios, not twenty independently observed pairs;
the larger real vote batches contained up to ten pairs. Request-size and pricing
changes can alter these figures.

A proposed initial **$15 monthly hard ceiling** for these incremental stages
leaves some headroom while preserving pause-on-exhaustion. This is a proposal,
not an installed policy or a promise of complete processing within that amount.
Daily/request/concurrency/retry limits and the approved live starting date remain
mandatory. Existing nightly processing checks missed work; page reads and
unchanged stages do not generate new content. New calendar months require an
explicit allowance rather than silent rollover.

This excludes the site's existing topic/meeting AI, one-time campaign intake,
formal-case processing, broader source channels and historical backfill. The old
site-wide prompt log does not provide a complete token/cost ledger, so this is
not an estimate of the entire site's invoice. The separately retained local
pilot report distinguishes conservative reservations from reported token usage;
reported usage is not a provider invoice. Pricing was checked November 8 and
requires renewal after November 21.

## Executed verification and remaining boundaries

- Exact-head PR #299 CI: 2,630 application tests / 18,683 assertions, one skip;
  46 browser journeys / 1,265 assertions, no skips. Runtime image, code review
  and security review completed successfully.
- The new ordering assertion and existing matching integration tests passed
  17 tests / 156 assertions. Removing the personal-action tie-breaker then failed
  the intended assertion: the member's vote disappeared from the two-row preview.
  The fault was restored before the passing rerun.
- The real local three-member journey checked phone/desktop layouts, independent
  disclosures, both forums and the article, selected-term page-two navigation and
  refresh, peer fractions, explicit incomplete formal coverage and source links.
  The duplicate Airbnb timeframe appeared only once. No horizontal overflow was
  observed at 390 pixels. External providers were not invoked by browsing.

Historical completeness, broader source interpretation, positive real formal
cases, eventual full-term assessment and production operation are not verified
here. An open implementation PR is not a shipped feature or completion of parent
#234. No broad historical backfill, production operation, merge or deployment ran.

Sources: [city meeting list](https://www.two-rivers.org/meetings),
[May 5, 2025 minutes](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Minutes-0a069b395b7b4040b2b46a2a7190f8f0.pdf),
[April 6, 2026 minutes](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Minutes-92069de44a594aa6990824383b8252fd.pdf).

## Existing minutes authority carried into profiles

The owner reaffirmed the existing app contract: the current meeting's minutes
establish its votes and decisions. Packets often contain old subcommittee minutes
as consent-agenda attachments. The new profile path now applies that same source
boundary. Packet responses cannot add actions or issue outcomes, and saved packet
rows are excluded from those profile projections. Explicit recommendations remain
separate; the existing vote extractor and accepted votes are unchanged.

The separate bounded December packet experiment remained held after quotation
and attribution validation failed. None of its generated updates or recommendations
were published. No further paid retry or new retry machinery was introduced.

The source-boundary checks first proved minutes-backed actions/outcomes visible,
then showed identical text in a packet could supply only the separate recommendation.
Cached packet actions were also excluded. Removing the parser boundary and then
the projection boundary independently failed the intended assertions; both faults
were restored. The final selection passed 45 tests / 436 assertions, with no
skips; full RuboCop passed across 867 files. This is a correction to the new
profile path, not a new vote-extraction
workflow or a claim of comprehensive source accuracy.

The routine cost scenario should consequently start with minutes. Removing the
five assumed packet analyses from the earlier scenario gives approximately
**$4.56 for one attempt each, or $9.12 if all requests use two attempts**. Selected
packet recommendation work is additional and remains inside any explicit overall
allowance. No allowance is enabled; the earlier five-packet scenario is an upper
workload illustration, not the default workflow.
