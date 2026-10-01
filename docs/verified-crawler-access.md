# Verified crawler access

## Policy

In `gated` mode, approved members and verified reporting crawlers may read
generated reporting. Ordinary anonymous visitors and unverified bots receive
the existing teasers; no withheld text reaches their HTML, metadata,
attributes, inline JSON, or alternate representations.

The owner approved human-directed AI retrieval on 2026-09-30 and accepts that
an AI receiving full reporting may answer a person's questions about it.
Verification controls delivery, not what another service tells a human.
Crawler access never creates an account/session or satisfies authentication,
membership approval, admin permissions, or reauthentication. Training crawlers
have no full-content exception.

## Supported providers

| Provider | Allowed HTTP identities | Verification feed |
| --- | --- | --- |
| Google Search, including its AI search features | `Googlebot`, `Google-InspectionTool` | [Google common crawler ranges](https://developers.google.com/static/crawling/ipranges/common-crawlers.json) |
| Bing and Copilot experiences powered by Bing | `bingbot` | [Bingbot ranges](https://www.bing.com/toolbox/bingbot.json) |

Google News uses ordinary Googlebot HTTP identities; `Googlebot-News` is a
robots.txt policy token. Image, video, ads, and generic research crawlers do
not receive a reporting exception. `Crawlers::Providers` holds the identities
and official feeds. Both an exact token and a matching source IP are required.
Similar names, several allowed identities in one request, query parameters,
and claimed verification headers cannot grant access.

Bingbot receives full reporting for indexing. This supports Copilot experiences
powered by Bing's index; it is not a universal exception for every Microsoft
browser or fetcher. `BingPreview` and arbitrary Azure addresses do not qualify.
No `data-nosnippet` restriction is added because the owner permits reporting
to inform AI answers.

## Rendering and caching

`SiteAccess#gated_for_visitor?` remains the only rendering predicate. The
exception covers GET/HEAD requests for ordinary HTML on the homepage, topic
and meeting indexes/searches/details, and committee/member detail pages.
Turbo streams and other formats retain anonymous behavior. Account, sign-in,
application, and admin permissions are unchanged. About retains the human
membership-policy copy.

Every gated reporting response sends `Cache-Control: private, no-store` so
full crawler responses cannot be reused for anonymous humans. Verification is
memoized for the request, never persisted as a cookie or user privilege.

Gated reporting pages include `WebPage` JSON-LD with
`isAccessibleForFree: false` for every audience. Google supports this for
subscription or registration access. The JSON contains no reporting text.
Optional `hasPart` selectors are omitted because the surfaces have different
teaser/restricted sections; the page-level flag is the required property.
Open mode omits the paywall markup.

## Verification data upkeep

`Crawlers::RefreshIpRangesJob` fetches every feed hourly at minute 7 through
the existing Solid Queue worker. Each snapshot is replaced atomically after
HTTPS, response-size, JSON, family, and CIDR validation. Redirects, empty
feeds, private networks, and excessively broad ranges are rejected. Page
requests never make verification network calls.

Snapshots use the existing shared Rails cache (Solid Cache in production).
They expire 48 hours after the last successful retrieval. Failed refreshes
retain still-current snapshots without extending their lifetime. Missing or
expired data keeps bots gated. All feeds are attempted even if one fails;
the job reports failures and retries.

An empty cache is populated by the next hourly run. To populate immediately
after release or a cache reset, run in the released application through the
production deployment playbook:

```sh
bin/rails crawlers:refresh
```

No migration or API credential is required. Local refreshes need a real cache
store; tests use temporary MemoryStore instead of the environment's NullStore.
Never seed permanently trusted IPs into source code.

## Proxy trust

`Crawlers::ClientIp` starts from the socket's `REMOTE_ADDR` and ignores
forwarding headers from untrusted peers. For trusted proxies, it walks
`X-Forwarded-For` right to left, stopping at the closest untrusted hop and
discarding earlier client-supplied addresses. Malformed chains fail
verification. `Client-IP`, `Forwarded`, and custom bot headers are ignored.

Defaults cover loopback (Thruster) and `172.16.0.0/12` (Docker). Override
`CRAWLER_TRUSTED_PROXY_CIDRS` for other networks or to narrow it to the actual
container subnet. These are proxy peers, not crawler ranges. Keep application
and Thruster ports private, exposing only the Kamal edge. The edge must append
or replace its observed client address. A chain outside configured ranges
fails verification.

## Sources and validation

- [Google verification](https://developers.google.com/crawling/docs/crawlers-fetchers/verify-google-requests)
- [Google identities](https://developers.google.com/crawling/docs/crawlers-fetchers/google-common-crawlers)
- [Google paywall/registration markup](https://developers.google.com/search/docs/appearance/structured-data/paywalled-content)
- [Bing crawler verification](https://www.bing.com/webmasters/help/Verify-Bingbot-2195837f)
- [Bing indexing and Copilot preview controls](https://blogs.bing.com/webmaster/2025/10/Bing-Introduces-Support-for-the-data-nosnippet-HTML-Attribute/)

Request tests first prove full reporting reaches verified crawlers, then prove
the same content is absent for spoofed requests. They cover forwarding-header
spoofing, missing ranges, formats, cache isolation, and account/admin denial.
The existing anonymous canary sweep and quantity/identity caps protect human
readers. Feed tests use controlled responses. A live feed refresh checks the
current endpoint; it does not prove a real crawler visit or a deployment.
