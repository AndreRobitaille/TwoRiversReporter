# Observed policy matrices pending owner decisions

These are observations, not new approved expectations. Public access was
measured through real synthetic HTTP requests at master 61d6779; passkey
states were verified in draft PR #182. Binding requirements and the exact
owner choices in #172/#175 must be reconciled before policy changes.

## Public reporting and source navigation (#172)

| Audience / mode | Source PDF/city/recording hrefs | Current committee roster | Generated reporting / item identities |
| --- | --- | --- | --- |
| Open anonymous / approved | All four supplied hrefs | Both roster identities | Full reporting marker; both item/speaker identities |
| Gated anonymous | Zero supplied hrefs/URLs in raw HTML | Zero roster identities | Reporting marker absent; both item/speaker identities remain |
| Gated approved | All four supplied hrefs | Both roster identities | Full reporting marker; both item/speaker identities |
| Pending/rejected/disabled browser account | Open: four; gated: zero | Open: two; gated: zero | Authentication rejected; anonymous presentation measured |
| Verified crawler in both modes | All four supplied hrefs | Both roster identities | Full reporting marker; offline verified-IP cache, not live provider verification |
| Impersonated crawler | Open: four; gated: zero | Open: two; gated: zero | Fake User-Agent follows anonymous presentation |
| Authorized active API owner, both modes | All four source metadata URLs | Both roster identities | Full generated marker in actual meeting/committee JSON |
| Revoked API key, both modes | HTTP 401 | HTTP 401 | No authorized read |

Sources: meetings/show and document-chip partials, committees/show, AccessHelper,
Crawlers::Verifier, API serializers and the July 24 access design. Existing
AnonymousLeakSweepTest has distinct signed-in presence and anonymous absence
passes; it also uses an offline crawler cache. Those tests do not resolve the
source/roster policy conflict or replace separate quantity/stable-identity tests.

Synthetic setup: two explicit-role committee members, two structured agenda
items/speakers, a generated marker beyond teaser length and city/minutes/agenda/
recording URLs. Approved-reader presence was asserted first in both modes.
The external observer passed one test / 66 assertions, with undecided anonymous
values measured rather than asserted as approved policy. Exact method/command
and capture paths are in the [audit](overnight-progress.md#source-access-characterization-172).

The same client observed open → gated on its next request. An approved client's
active session was then disabled; next request removed that server session and
cleared its authentication cookie. Gated meeting/committee responses were
`private, no-store`; open responses were `max-age=0, private, must-revalidate`.
The fixture reporting marker was absent from metadata in all HTML rows. These
observations cover the supplied HTML/JSON routes, not external source usability,
share/OG/search/stream representations, production CDN caches or any decided
meeting item/speaker cap. No example source was fetched.

Owner decision needed: exact anonymous hrefs, roster identity visibility and
item/speaker teaser quantity/identity limits. The separate blob-possession
decision stays in #154. Next verification must use allowed-content proof first,
raw representations, stable quantities/identities, transitions and independent
guard/cap fault experiments. No withholding rule changed here.

## Passkey page and endpoints (#175)

| Same session/request state | Rendered Add/Remove controls | Direct registration/removal gate |
| --- | --- | --- |
| Fresh proof, matching anchor | Unlocked | Allowed, subject to ceremony/ownership/admin safeguards |
| Fresh proof, remembered pair different from anchor | Locked | Context and freshness gates allow the task |
| Fresh proof, unknown different pair | Locked | Challenged; JSON 403 |
| Stale proof, matching anchor | Locked | Challenged; JSON 403 |
| Stale proof, remembered pair | Locked | Freshness still challenges; JSON 403 |

Sources: Settings::SecurityController#show, Reauthentication's strict/fresh
gates and PasskeysController. The page comment saying the endpoint requires an
exact match is stale relative to the remembered-context addendum. This is an
unnecessary challenge candidate, not evidence of an authorization bypass.
Rename has its own endpoint contract and must not be conflated with Add/Remove.

Recommended intended contract: fresh AND (matching anchor OR remembered pair),
with independent ownership and last-usable-admin protection. Owner decision
remains pending. Draft [PR #182](https://github.com/AndreRobitaille/TwoRiversReporter/pull/182)
verifies this existing discrepancy through the same-state HTTP matrix; it does
not approve the fresh-known UI row. Its secure-localhost virtual CTAP2 journeys
also prove native browser registration/signature verification, sign-in/removal
and stale-proof step-up. Hardware/biometric/consent remain simulated. Seeded
credentials and stubbed verification stay distinct component evidence; see the
[audit](overnight-progress.md#passkey-draft-175).

## Expired-link cleanup interaction (#173)

July 23 requires a fresh-link action for a known expired approval context.
July 25's audit/cleanup section requires deleting used or expired MagicLink
rows. The recovery branch supports an eligible, unused, expired sign-in row
that still exists, and a characterization verifies cleanup currently removes
that context. It does not change token retention or create a general email
lookup endpoint.

Owner choice pending: retain unused expired sign-in rows for a bounded recovery
window (proposed seven days), or explicitly limit recovery to the time before
cleanup removes the row. Recovery must keep old links unusable for sign-in,
respect eligibility/throttling and send a new usable link to the correct account.
