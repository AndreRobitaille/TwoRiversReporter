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

## Supported and pending providers

| Provider | Allowed HTTP identities | Verification feed |
| --- | --- | --- |
| Google Search, including its AI search features | `Googlebot`, `Google-InspectionTool` | [Google common crawler ranges](https://developers.google.com/static/crawling/ipranges/common-crawlers.json) |
| Bing and Copilot experiences powered by Bing | `bingbot` | [Bingbot ranges](https://www.bing.com/toolbox/bingbot.json) |
| ChatGPT search | `OAI-SearchBot` | [OpenAI search ranges](https://openai.com/searchbot.json) |
| ChatGPT user-directed retrieval | `ChatGPT-User` | [OpenAI user retrieval ranges](https://openai.com/chatgpt-user.json) |
| Claude search and user-directed retrieval | `Claude-SearchBot`, `Claude-User` | [Anthropic crawler ranges](https://claude.com/crawling/bots.json) |
| Perplexity search and user-directed retrieval | `PerplexityBot`, `Perplexity-User` | [PerplexityBot ranges](https://www.perplexity.ai/perplexitybot.json), [Perplexity-User ranges](https://www.perplexity.ai/perplexity-user.json) |
| Grok | No full-content exemption yet | No operator verification source confirmed |

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

OpenAI's search and user-directed retrieval each require their own feed. This
allows ChatGPT to index reporting and fetch it for a human's question. `GPTBot`
is a separate training crawler and receives no full-content exception.
ChatGPT agents, Codex, and arbitrary OpenAI-operated networks do not qualify
unless the request meets one of these documented identity/feed pairs.

Anthropic publishes one crawler range feed shared by its bots. Only
`Claude-SearchBot` and `Claude-User` receive the reporting exception;
`ClaudeBot` is a training crawler and remains at the anonymous tier. API and
MCP egress ranges are not substituted for the documented crawler feed.

Perplexity publishes separate feeds for `PerplexityBot` (search indexing) and
`Perplexity-User` (user-requested fetches). The docs at
https://docs.perplexity.ai/docs/resources/perplexity-crawlers list
`https://www.perplexity.com/perplexitybot.json` and
`https://www.perplexity.com/perplexity-user.json`. Those URLs 302 to
`https://www.perplexity.ai/perplexitybot.json` and
`https://www.perplexity.ai/perplexity-user.json`. The range fetcher rejects
redirects, so the stored feed URLs are the `perplexity.ai` responses that
return 200 with a `prefixes` array. Both use the same validation and the
hourly refresh as Google and Bing.

### Grok verification prerequisite

As of 2026-09-30, review of xAI's official Web Search documentation and
documentation index did not establish a crawler identity with an operator
IP feed or a reverse/forward DNS verification procedure. Those sources
describe web search and browsing, not a publisher-facing authorization scheme.
This does not establish that Grok has no crawler; it means we cannot yet
authenticate such a request independently of its claimed name.

Grok therefore receives existing public teasers unless it authenticates as an
approved member through the ordinary account flow. No guessed bot name, broad
cloud network, or client-supplied verification header gets a full-content
exception. `GrokCrawlerAccessTest` pins that behavior even on a known crawler
network. Its sample Grok labels are simulated claims, not asserted official
user-agent strings. Direct Grok access remains unimplemented pending
verification. Tracked in GitHub Issues: #141 (https://github.com/AndreRobitaille/TwoRiversReporter/issues/141).

To enable direct Grok access later, first obtain an xAI-published identity and
verification source or an explicitly authenticated publisher arrangement.
Then add its verified pair to `Crawlers::Providers`, extend the refresh job if
its source format differs, and run the same full-content/impersonation, proxy,
cache, and account/admin tests used by the other providers. A robots.txt rule
alone cannot authenticate a request or unlock the server-side gate.

## Rendering and caching

`SiteAccess#gated_for_visitor?` remains the only rendering predicate. The
exception covers GET/HEAD requests for ordinary HTML on the homepage, topic
and meeting indexes/searches/details, and committee/member detail pages.
The XML sitemap has a scoped discovery exception described below; Turbo
streams and other reporting formats retain anonymous behavior. Account, sign-in,
application, and admin permissions are unchanged. About retains the human
membership-policy copy.

Every gated reporting response sends `Cache-Control: private, no-store` so
full crawler responses cannot be reused for anonymous humans. Verification is
memoized for the request, never persisted as a cookie or user privilege.

Gated reporting pages include `WebPage` JSON-LD with
`isAccessibleForFree: false` and a `hasPart` `WebPageElement` whose
`cssSelector` is `.gated-content`. That class wraps the full-content branch
on meeting, topic, committee, and member pages. Anonymous teasers do not
include the element. The JSON contains no reporting text. Open mode omits
the paywall markup. A separate `Organization` node and, on meeting pages, an
`Event` node describe only fields the app already has.

## Discovery files

`/sitemap.xml` is generated by Rails on each request. In gated mode, verified
crawlers and approved members receive the full canonical catalog; anonymous
visitors receive only the homepage and About URLs. Open mode exposes the full
catalog. Only this discovery action accepts verified XML requests; reporting
JSON, XML, markdown, and Turbo streams gain no crawler exception.

`Sitemaps::Catalog` includes the topic, meeting, and committee indexes, approved
topics, canonical meeting records selected by the existing cancellation/content
precedence, active/dormant committees, and civic member profiles. Blocked or
proposed topics, dissolved committees, duplicate redirect URLs, account/admin
routes, and synthetic probes are excluded. Entries contain only URLs and
optional modification dates. Topic dates include briefing/appearance/summary
updates; meeting dates include documents, summaries, agenda items, and motions.
Member/committee pages omit `lastmod` because their composite content can change
without updating the parent record. All sitemap responses use `private,
no-store`, including open mode, to prevent catalog reuse across audiences or a
mode switch. No sitemap rebuild task or scheduled job is needed.

`robots.txt` names the supported reporting identities, excludes admin, and
advertises the sitemap. The server still verifies each full-content request.
Public `/llms.txt` contains an independent-site overview, source and access
guidance, stable navigation links, and the sitemap/robots locations. It contains
no reporting copy or resource catalog. HTML advertises it with a `describedby`
link. It neither authenticates a requester nor requires Grok support. No article
markdown endpoints or `llms-full.txt` reporting dump are added.

Both public text files use `public, max-age=3600, must-revalidate` with static
Last-Modified handling, instead of the one-year production asset cache lifetime.
This also applies to HEAD and 304 responses. Fingerprinted asset caching and
reporting/sitemap privacy headers are preserved.

Google and Bing can discover the sitemap through robots.txt. Search Console or
Bing Webmaster Tools can also submit the same URL and show processing results;
deployment alone does not establish submission, indexing, or a crawler visit.
The optional llms.txt proposal provides site guidance, not an indexing guarantee.

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

## Live retrieval diagnostics

Run `bin/rails crawlers:probes` in the released application to create a public
probe and a gated probe. Each has an independent random URL and synthetic
verification code in Solid Cache and expires after 48 hours. They contain no
reporting, have no navigation or sitemap links, reject non-HTML formats, and
send `noindex, nofollow` and `private, no-store` headers. Unknown or expired
tokens return 404. Generating probes does not change the site access mode.

Give the assistant only the public URL and ask it to open the page and quote
its verification code. Repeat in a fresh chat with only the gated URL. In
gated mode, the gated code is available to approved members and the same
verified crawler identities as reporting. Unverified requests see
`Verification code withheld. Sign in to keep reading.`

Each valid HTML request writes a JSON `crawler_probe` log event with the token,
request ID, access decision, socket peer, forwarding chain, derived client IP,
and user-agent. Codes, cookies, and credentials are not logged. Correlate a
correct code with the matching request before concluding that direct retrieval
worked. A code alone may have come from a preview or intermediary. Observing
an address or user-agent does not make it a trusted provider identity.

## Sources and validation

- [Google verification](https://developers.google.com/crawling/docs/crawlers-fetchers/verify-google-requests)
- [Google identities](https://developers.google.com/crawling/docs/crawlers-fetchers/google-common-crawlers)
- [Google paywall/registration markup](https://developers.google.com/search/docs/appearance/structured-data/paywalled-content)
- [Bing crawler verification](https://www.bing.com/webmasters/help/Verify-Bingbot-2195837f)
- [Bing indexing and Copilot preview controls](https://blogs.bing.com/webmaster/2025/10/Bing-Introduces-Support-for-the-data-nosnippet-HTML-Attribute/)
- [Official OpenAI crawler documentation](https://developers.openai.com/api/docs/bots)
- [Official Anthropic crawler policy and verification source](https://support.claude.com/en/articles/8896518-does-anthropic-crawl-data-from-the-web-and-how-can-site-owners-block-the-crawler)
- [xAI Web Search](https://docs.x.ai/developers/tools/web-search)
- [xAI documentation index](https://docs.x.ai/llms.txt)
- [Google sitemap guidance](https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap)
- [Bing sitemap discovery](https://blogs.bing.com/webmaster/2025/7/Keeping-Content-Discoverable-with-Sitemaps-in-AI-Powered-Search/)
- [llms.txt proposal](https://llmstxt.org/)

Request tests first prove full reporting reaches verified crawlers, then prove
the same content is absent for spoofed requests. They cover forwarding-header
spoofing, missing ranges, formats, cache isolation, and account/admin denial.
The existing anonymous canary sweep and quantity/identity caps protect human
readers. Feed tests use controlled responses. A live feed refresh checks the
current endpoint; it does not prove a real crawler visit or a deployment.

Validation on 2026-09-30:

- `CI=1 PARALLEL_WORKERS=1 RUBOCOP_CACHE_ROOT=/tmp/trr-crawler-rubocop bin/ci`
  passed: 1,842 tests, 7,728 assertions, no failures/errors, one existing skip;
  RuboCop, dependency audits, and Brakeman passed.
- Live official feeds passed the actual fetch, validation, cache, and identity
  verification path locally: Google 317 ranges, Bing 28, OpenAI search 39,
  OpenAI user retrieval 230, and Anthropic 26. All seven supported identities
  verified against their corresponding feed.
- After positive content assertions passed, temporarily removing source-IP
  verification caused the Google impersonation test to fail as expected.
  The original verification was restored before final CI.
- These checks do not verify the production proxy chain, deploy the feature,
  or prove that a real provider crawler has visited the site. Tracked in GitHub Issues: #143 (https://github.com/AndreRobitaille/TwoRiversReporter/issues/143).

Discovery validation on 2026-09-30:

- Targeted sitemap and all four provider request suites passed: 54 tests,
  672 assertions, no failures/errors. Tests cover all seven identities, exact
  URL counts and identities, anonymous/spoofed/expired-feed denial, member/open
  access, cache/mode isolation, canonical duplicate selection, and regeneration
  timestamps. Existing provider tests retain reporting format/account limits.
- Temporarily removing the sitemap audience guard caused five expected
  gating/cache failures, including the anonymous exact-URL test. The guard was
  restored and the sitemap suite rerun before committing.
- `CI=1 PARALLEL_WORKERS=1 RUBOCOP_CACHE_ROOT=/tmp/trr-crawler-rubocop
  GEM_SPEC_CACHE=/tmp/trr-crawler-gem-spec-cache bin/ci` passed: 1,854 tests,
  7,867 assertions, no failures/errors, one existing skip; all 533 Ruby files
  passed RuboCop, both dependency audits passed, and Brakeman found no warnings.
- The robots policy matches the supported identity registry. llms.txt links
  only stable public entry points, with no diagnostic/account URLs or reporting
  catalog. Live deployment checks are separate from these local results. Tracked in GitHub Issues: #143 (https://github.com/AndreRobitaille/TwoRiversReporter/issues/143).
- Follow-up discovery cache checks passed: 12 targeted tests, 138 assertions;
  full CI passed with 1,856 tests, 7,892 assertions, no failures/errors, the same
  existing skip, all 535 Ruby files clean, dependency audits passing, and no
  Brakeman warnings. GET/HEAD/304 text-file revalidation and preservation of
  asset/reporting cache headers are covered.
