# Approved policy matrices

Initial observations used synthetic requests at master 61d6779 and passkey
PR #182. On October 11, 2026 Andre explicitly approved preserving the current
anonymous pages, relaxed smart authentication, conditional homepage/meeting
layouts and expired-record cleanup. Specialized specifications record those
decisions. No public-access or authentication predicate changed.

## Public reporting and source navigation (#172)

| Audience / mode | Source PDF/city/recording hrefs | Current committee roster | Generated reporting / item identities |
| --- | --- | --- | --- |
| Open anonymous / approved | All five supplied hrefs | Both roster identities | Full reporting marker; both item/speaker identities |
| Gated anonymous | Zero supplied hrefs/URLs in raw HTML | Zero roster identities | Reporting marker absent; both item/speaker identities remain |
| Gated approved | All five supplied hrefs | Both roster identities | Full reporting marker; both item/speaker identities |
| Pending/rejected/disabled browser account | Open: five; gated: zero | Open: two; gated: zero | Authentication rejected; anonymous presentation asserted |
| Verified crawler in both modes | All five supplied hrefs | Both roster identities | Full reporting marker; offline verified-IP cache, not live provider verification |
| Impersonated crawler | Open: five; gated: zero | Open: two; gated: zero | Fake User-Agent follows anonymous presentation |
| Authorized active API owner, both modes | All five source metadata URLs | Both roster identities | Full generated marker in actual meeting/committee JSON |
| Revoked API key, both modes | HTTP 401 | HTTP 401 | No authorized read |

Sources: meetings/show and document-chip partials, committees/show, AccessHelper,
Crawlers::Verifier, API serializers and the July 24 access design. Existing
AnonymousLeakSweepTest has distinct signed-in presence and anonymous absence
passes; it also uses an offline crawler cache. Separate quantity/stable-identity
tests complement the withheld-byte sweep.

Historical four-source observer setup: two explicit-role committee members, two structured agenda
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

Owner decision October 11: preserve the current signed-out pages. A fresh
signed-out Chromium profile inspected meeting 277 and City Council's committee
page through public HTTPS: source chips/Share disabled, roster withheld and
teaser reporting retained. The web search crawler receives a different verified
crawler audience and is not evidence of the ordinary anonymous presentation.

Exact approved limits: meeting lede 100 characters, bodies 30 characters at word
boundaries; no quantity or identity cap on structured highlights, agenda titles
or speakers. Votes/tallies, decisions, roll calls, hearing lines, citations and
topic doors are withheld. Source chips emit zero meeting-source URLs; committee
rosters emit zero identities. Topic listings/search retain the existing two-card
cap, pinned identities on later pages of the same query, public-name search and
no withheld-headline matching. The possessed-blob question remains in #154.

`SourceAccessContractTest` converts the matrix to approved expectations using
five source URLs (including Packet), two roster identities and two distinct
items/speakers. It proves the allowed fixture first, checks actual hrefs and raw
HTML/metadata/share attributes, authenticated API JSON, denied formats and
next-request revalidation. `SourceNavigationJourneysTest` opens the rendered
City Website link in a real browser window, receives the distinct offline Rack
publisher page and verifies logout removes the source controls. Publisher
content is synthetic; external publisher availability and CDN caches remain
outside this local proof. Existing canary/search/stream and independent
quantity/pagination-identity faults remain complementary.

## Passkey page and endpoints (#175)

| Same session/request state | Rendered Add/Remove controls | Direct registration/removal gate |
| --- | --- | --- |
| Fresh proof, matching anchor | Unlocked | Allowed, subject to ceremony/ownership/admin safeguards |
| Fresh proof, remembered pair different from anchor | Locked | Context and freshness gates allow the task |
| Fresh proof, unknown different pair | Locked | Challenged; JSON 403 |
| Stale proof, matching anchor | Locked | Challenged; JSON 403 |
| Stale proof, remembered pair | Locked | Freshness still challenges; JSON 403 |

Sources: Settings::SecurityController#show, Reauthentication's strict/fresh
gates and PasskeysController. The stale exact-match endpoint comment is corrected;
the owner approved preserving this page/endpoint distinction on October 11.
Rename has its own endpoint contract and must not be conflated with Add/Remove.

Approved intended contract: endpoints retain fresh AND (matching anchor OR
remembered pair); the page retains fresh AND matching anchor, offering step-up
otherwise. Ownership and last-usable-admin protection are independent.
[PR #182](https://github.com/AndreRobitaille/TwoRiversReporter/pull/182)
verifies that approved matrix. Its secure-localhost virtual CTAP2 journeys
also prove native browser registration/signature verification, sign-in/removal
and stale-proof step-up. Hardware/biometric/consent remain simulated. Seeded
credentials and stubbed verification stay distinct component evidence; see the
[audit](overnight-progress.md#passkey-draft-175).

## Expired-link cleanup interaction (#173)

July 23 requires a fresh-link action for a known expired approval context.
July 25's audit/cleanup section requires deleting used or expired MagicLink
rows. The recovery branch supports an eligible, unused, expired sign-in row
that still exists, and an expectation verifies cleanup removes
that context. It does not change token retention or create a general email
lookup endpoint.

Owner decision October 11: keep current cleanup; recovery is limited to the time
before cleanup removes the unused expired row. No retention extension. Recovery
keeps old links unusable for sign-in, respects eligibility/throttling and sends
a new usable link to the correct account.
