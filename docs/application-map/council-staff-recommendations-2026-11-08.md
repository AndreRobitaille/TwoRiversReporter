# Explicit staff recommendations — November 8, 2026

Scope: BG-09 → RES-10/11, bounded #242 work under #234. The
[binding design](../superpowers/specs/2026-11-07-council-accountability-design.md#agreement-with-staff-or-the-city-manager)
requires an actual attributable recommendation and comparable proposal before
calculating agreement. Being a presenter or report author is insufficient.

## Implemented boundary

New shared official-source requests now include explicit recommendations alongside
issue milestones and attributed actions. All people use the same retained result;
there is no recommendation request per member. Named managers, individual staff,
departments, advisory bodies and explicitly attributed collective staff remain
distinct. The record retains source name/role, full proposal, position relative to
that proposal, extra conditions, date, timing and an exact contiguous passage.
The author, role if supplied, and complete proposal must occur in that passage.
These checks locate evidence; they do not independently validate the model's
interpretation. A real-provider accuracy evaluation remains open.

The first deterministic comparison requires a single substantive motion on the
same agenda item, the complete unchanged proposal wording (case/whitespace only),
an explicit pre-decision recommendation and an independently recorded yes/no vote.
A yes vote on a motion to reject agrees with support for that rejection motion.
Extra conditions, amendments/multiple motions, conflicting versions, unclear timing
and ambiguous duplicate meeting imports remain excluded, with the reason visible.
Missing recommendations are unknown. Duplicate source copies do not multiply a
decision within the same recommending source. No cross-meeting or different-wording
semantic matching is claimed. Member service dates limit eligible decisions.

The closed Staff and advisory recommendations section shows all/divided fractions.
Each fraction opens paginated decisions and exclusions; full motions and quotations
stay behind disclosures. Corrected source inputs remove stale comparisons on the
next request without modifying accepted votes. Existing reader/verified-Google
access applies, including no-store and HTML-only responses. No generated data is
published into the real development preview by these tests.

## Cost and reuse

Explicitly selected packets are now admitted, up to 120,000 serialized-context
characters; minutes retain 60,000. Complete output stays capped at 8,000 tokens,
with at most two attempts and existing exact-request/run/day/month reservations.
Oversized or incomplete work holds rather than silently truncating. This slice
does not enable automatic source discovery, a live allowance or a new schedule.

Schema version 3 is retained on newly prepared requests but excluded from source
identity. Existing completed results, including older milestone/action results,
are reused unchanged; a prompt/schema edit cannot trigger historical processing.
Page views, fractions, filtering and nightly unchanged-input checks call no AI.

Offline construction from six existing official-minutes contexts estimates
conservative one-attempt ceilings of $0.141728–$0.173785 at rates checked November 8
and valid through November 21. A full 90,495-character official packet with a
representative 12-item agenda allowance estimates $0.357420, or $0.714840 for two
attempts. The packet estimate is a planning scenario, not an actually prepared
production request, token measurement or invoice. Monthly sustainability still
needs the remaining stages and actual workload; spending ceilings remain binding.
No allowance, paid generation or historical backfill ran.

## Executed verification

Branch `codex/council-recommendation-evidence`, based on `cf7c073`, Ruby 4.0.9,
isolated PostgreSQL `trr_council_recommendations_test`. Provider transport alone is
deterministic. Request preparation, budget reservation, receipt, parsing,
persistence, calculation and subsequent HTTP/browser requests run normally.

- `bin/rails test test/integration/council_staff_recommendations_test.rb
  test/integration/council_issue_updates_test.rb
  test/integration/council_recorded_actions_test.rb`: **30 tests, 312 assertions**,
  green. Shared counts/identities, retained qualifications, rejection polarity,
  source copies, conflicting departments, changed officeholder attribution,
  source correction, service dates, unknown ballots, pagination, input/allowance
  bounds and reader/Google/gated access are covered. Source analysis accuracy is
  simulated, not demonstrated by these tests.
- `bin/rails test test/system/member_staff_recommendations_journeys_test.rb`:
  **1 test, 11 assertions**, green at 390px. Closed section → fraction → source →
  divided selection → same-term return executes in Chromium. Screenshot inspected;
  no horizontal page overflow. The installed Chrome/driver versions warned about
  compatibility but completed the journey. Initial case-sensitive text expectation
  was corrected for the existing uppercase table style.
- After a clean passing baseline, bypassing the exact-proposal check failed the
  intended amended-wording assertion; bypassing visitor gating exposed one row
  where zero was required. Both faults were isolated and restored. The entire
  recommendation integration file reran green: **11 tests, 111 assertions**.
- Existing campaign-action matching, nightly reconciliation and prompt-definition
  files also passed: **14 tests, 155 assertions**. All 438 checked local document
  link targets exist, and `git diff --check` is clean.
- Full `bin/rubocop`: **842 files**, no offenses. Initial checks found the new
  route missing from crawler/no-store configuration; the implementation now
  includes it and the allowed Google/spoofed-request assertions pass.

The real reference is page 4 of the [December 1, 2025 Council packet](https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Packet-7f330ca5db25423e8ee9dbcbc77975e9.pdf).
The PDF page was visually checked. It explicitly attributes the concession
renovation recommendation to City Staff; it does not establish a named manager
as recommender. Its full recommended action matches the stored actual motion in
the existing local data, preserving the $520,000/$256,000/$131,000 limits. The
fixture uses that official excerpt with a deterministic response. The neighboring
operations item merely saying staff presented options is not an attribution of
support. Neither this comparison nor the funding vote establishes project completion.

No production access, data sync, paid request, broad backfill, PR merge or deploy
was performed. The other session's voter review remains unavailable; this record
does not claim that those reviewers approved this new section.
