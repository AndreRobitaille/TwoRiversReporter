# Application inventory and access model

See [baseline/evidence definitions](README.md) before treating this as runtime
proof. The detailed [route inventory](routes.md) supplies exact verbs and paths.

## Actors are separate from states

| Actor or state | Identity and intended authority | Source evidence |
| --- | --- | --- |
| Anonymous visitor | Public reporting in open mode; teaser reporting in gated mode; may start an application/sign-in | [SiteAccess](../../app/controllers/concerns/site_access.rb), [access design](../superpowers/specs/2026-07-24-tiered-public-access-design.md) |
| Applicant | Website `User` is pending and disabled; application can be email-pending or submitted. An application link permits that form, not member access | [ApplicationsController](../../app/controllers/applications_controller.rb), [MembershipApplication](../../app/models/membership_application.rb) |
| Active account | `status == active` and no `disabled_at`; session grants resident content and own settings | [User](../../app/models/user.rb), [Authentication](../../app/controllers/concerns/authentication.rb) |
| Administrator | Active account plus `admin`; requires at least one passkey and the admin context gate | [Admin::BaseController](../../app/controllers/admin/base_controller.rb) |
| Administrator without a passkey | Can authenticate by email; `/admin` redirects to own Security setup until ready | [Admin::BaseController](../../app/controllers/admin/base_controller.rb) |
| Disabled/rejected/pending account | Cannot authenticate or resume member sessions. A disabled active account can be re-enabled; a rejected/pending account needs a membership decision | [User](../../app/models/user.rb), [UsersController](../../app/controllers/admin/users_controller.rb) |
| Valid session from unfamiliar context | Ordinary browsing remains authenticated; sensitive controls require step-up | [Reauthentication](../../app/controllers/concerns/reauthentication.rb) |
| Expired/missing/revoked session | Resume clears invalid cookie/session; subsequent protected navigation requires sign-in | [Session](../../app/models/session.rb), [Authentication](../../app/controllers/concerns/authentication.rb) |
| Verified reporting crawler | Identity AND current published IP range allow selected HTML and sitemap reads in gated mode; no account/admin/API authority | [Crawler policy](../verified-crawler-access.md), [SiteAccess](../../app/controllers/concerns/site_access.rb) |
| Bearer API client | Valid unexpired/unrevoked key owned by an active eligible account grants only resident JSON reads; browser cookies do not authenticate it | [API base](../../app/controllers/api/base_controller.rb), [key model](../../app/models/api_access_token.rb) |
| Civic official | `Member` represents a public official. This is reporting data, not a website login role or a membership application | [Member](../../app/models/member.rb), [API contract](../read-only-api.md) |
| Operator/background worker | Runs repository jobs/tasks; capabilities are operational, not a public user role | [recurring jobs](../../config/recurring.yml), [job launcher](../../app/controllers/admin/job_runs_controller.rb) |

## Access matrix

An active signed-in account receives full resident reporting in both modes.
`open` does not open Account or Admin. Every API request still needs a bearer
key. Disabled/expired sessions fall back to the applicable anonymous tier.

| Surface | Anonymous, open | Anonymous, gated: observed in source | Active browser account | Verified crawler, gated |
| --- | --- | --- | --- | --- |
| What's New `/` | Full selections | Topic names/dates, shortened generated headline/description; per-card sign-in note | Full | Full HTML |
| Topics `/topics`, including search | Full cards/pagination | First two hero/search cards; page pinned to 1; generated headlines teased; no remaining topic list | Full | Full HTML; no full-content Turbo-stream exception |
| Topic `/topics/:id` | Full | Header/dek and What to Watch, then gate; story/decisions/record/upcoming content below gate withheld | Full | Full HTML |
| Meetings `/meetings`, including search | Full | Cards with teased headline; scheduling/identity remains visible | Full | Full HTML |
| Meeting `/meetings/:id` | Full | Header/headline teaser; document/recording/city chips disabled; share disabled; structured decision/input/item body teasers, with vote/citation/topic details withheld | Full | Full HTML |
| Committees `/committees` | Full directory | Full directory | Full | Ordinary public directory; no special exception needed |
| Committee `/committees/:slug` | Full | Header/description; current roster and recent activity contents withheld | Full | Full HTML |
| Official `/members/:id` | Full | Identity, current memberships and attendance; voting record withheld | Full | Full HTML |
| About `/about` | Full | Full | Full | Public |
| Explore `/topics/explore` | Coming-soon page | Same coming-soon page | Same | Same; not a research interface |
| Sign-in / application entry | Available | Available | Not a privilege grant | No extra privileges |
| Own settings | Requires sign-in | Requires sign-in | Own data; some mutations require context/freshness | Requires sign-in |
| `/admin` and descendants | Requires eligible admin | Requires eligible admin | Eligible admin only | Requires eligible admin |
| `/api`, `/api/v1/...` | Bearer required | Bearer required | Cookies alone rejected | Crawler identity alone rejected |
| `/sitemap.xml` | Canonical catalog | Home and About only | Canonical catalog | Canonical catalog in XML |
| `/robots.txt`, `/llms.txt` | Public static guidance | Same public guidance; no reporting dump | Same | Same |

These are **implementation observations**, not resolutions of specification
conflicts. Meeting source-link gating, committee roster gating, and expanded
meeting teasers differ from older descriptions; see V-04/V-05 in the
[verification register](verification-register.md). Exact teaser sizes live in
the helpers, not this map.

## Pages, interfaces, actions and navigation

Public navigation: **What's New → Meetings → Topics → Committees → About**.
Signed-in users get **Account**, eligible admins get **Admin**, and both public
and admin shells offer **Sign out**. Anonymous visitors get **Sign in / Apply**.
Account tabs link Profile, Security, and API keys. Public/Account uses the Living
Room theme; admin uses Silo. Mobile admin navigation uses a drawer/scrim.

| Area / entry | Interfaces and available actions | Navigation out / workflows | Evidence |
| --- | --- | --- | --- |
| Home `/` | Top Stories (up to 2), Wire (up to 4 cards + 6 rows), Next Up (up to 2 council events), browse links | Story/wire controls link to topics; Next Up links to meeting; browse Topics/Meetings | [Home views](../../app/views/home/index.html.erb), [selection](../../app/services/resident_content/home_selection.rb); RES-01 |
| Topics `/topics` | Search, recent active hero cards, remaining active list, highlight/freshness badges, pagination/Turbo show-more | Topic detail; gated sign-in/application | [controller](../../app/controllers/topics_controller.rb), [index](../../app/views/topics/index.html.erb); RES-02/03 |
| Topic detail | Header, What to Watch, Coming Up, Story/process concerns, Key Decisions, Record; sections adapt to available data | Upcoming/history meeting links, return to Topics; no reader editing/follow button | [view](../../app/views/topics/show.html.erb); RES-04 |
| Meetings `/meetings` | Upcoming/recent enriched cards and thin compact rows, collapsed lists, search, further search pages | Meeting detail | [index](../../app/views/meetings/index.html.erb); RES-05 |
| Meeting detail | Source chips; summary-source/cancellation banners; headline, decisions, input, agenda detail, linked topics; legacy markdown fallback; expandable roll-call; Share dropdown | Official source/recording in new tab, linked topic, agenda anchor, copy summary, native share/Facebook, back to Meetings | [view](../../app/views/meetings/show.html.erb), [share controller](../../app/javascript/controllers/share_controller.js); RES-06/07/08 |
| Committees | Directory grouped into Council, Council Subcommittees, Advisory Boards, Independent Authority, Tax-Funded Nonprofits; each has detail page | Roster names → officials; activity → topics; back to directory | [controller](../../app/controllers/committees_controller.rb), [views](../../app/views/committees/index.html.erb); RES-09 |
| Officials `/members/:id` | Current offices/memberships, attendance and peer comparison, topic-grouped voting record, Other Votes disclosure | Committee/topic/meeting links; `/members` redirects to directory | [view](../../app/views/members/show.html.erb); RES-10 |
| Membership application | Email entry; token-backed form with required name/street/city/state and optional phone/Facebook/notes; stateless submitted confirmation | Sign-in later after approval; no self-approval | [views](../../app/views/applications/edit.html.erb); AUTH-06/07, ADM-02 |
| Authentication | Email request, confirmation POST, passkey button, invalid/expired notice; reauthentication challenge has eligible passkey or email option | Return to safe stored destination or homepage; required setup → Security | [sessions](../../app/views/sessions/new.html.erb), [challenge](../../app/views/reauthentications/new.html.erb); AUTH-01–05/12 |
| Profile | Read-only account and latest application details | Security/API keys; no profile edit action | [controller](../../app/controllers/settings/profile_controller.rb); AUTH-09 |
| Security | Add, rename, remove own passkeys; confirmation link while locked; known network/browser list; passkey reminder dismissal elsewhere | Reauthenticate then return; eligible Admin after first passkey | [view](../../app/views/settings/security/show.html.erb); AUTH-10/11/12 |
| API keys | Metadata list, new key name/expiry, one-time secret and Copy button, revoke one/all | Authenticated `/api` guide for tools; no admin or write scope | [controller](../../app/controllers/settings/api_keys_controller.rb); AUTH-13/14/15, RES-13–15 |
| About | Purpose/access/source guidance and site links | Public navigation and access application | [view](../../app/views/pages/about.html.erb); RES-12 |

## Administration inventory

The sidebar and dashboard launcher share [Admin::Navigation](../../app/models/admin/navigation.rb).
Contextual image, application-deletion, and repair interfaces are reached from
their parent record; they do not need separate sidebar entries.

| Navigation group | Entry and controls | Workflow IDs |
| --- | --- | --- |
| Topics | All Topics: filters by name/status/review/lifecycle/pinned/sort, inline edits, row expansion/lazy evidence, approve/block/review/pin; detail decision board, merge/canonical repair, aliases, context and impact edits; Blocklist: add/remove | ADM-06–09 |
| Meetings | Meetings: latest 100 with image state and detail; Add Transcript: latest 250 meeting choices, filter, YouTube URL, optional SRT/remove file, Check URL, Begin Import, latest 25 workflow logs; Summaries: coverage counters/regenerate one/all | ADM-13/14/15 |
| The Record | Committees: type/status filter, CRUD, descriptions and aliases; Members: civic identities, aliases/merge, attendance/votes; Knowledge Sources: status/origin filter, note/PDF CRUD, verification/active state, re-ingest; Knowledge Search: query, retrieved chunks/doc excerpts, optional Ask AI | ADM-10/11/12 |
| The Machine | Run a Job: allowed type + targets/preview count; Queue & Failures: worker heartbeat/queue counts, latest 50 completed/failed, retry one/all, discard, Clear All Finished; Prompts: template edit/version diff/examples/model test-run | ADM-16/17/18 |
| Site | Access Mode: open/gated choice; Redirects: list/new/edit/delete; User Accounts: pending/denied/approved groups, new admin, application decisions, account role/disable/delete, session revoke, key metadata; Audit Log: latest 200 events | ADM-01–05/19/20 |
| User menu | Public Site, own Security, Sign Out; mobile navigation drawer | ADM-01, AUTH-04/10 |

Evidence: corresponding [admin controllers](../../app/controllers/admin/base_controller.rb)
and [route tables](routes.md). Exact method/path details belong to the route
inventory. Unimplemented REST actions and preserved orphan actions are not
advertised capabilities; see V-02 and V-06.

## Boundaries beyond a rendered page

- **HTTP/browser:** Turbo issues DELETE for the sign-out link; other controls
  use forms, Turbo frames/streams, Stimulus, confirmation dialogs, clipboard,
  native share, and WebAuthn. Direct controller calls cannot validate these.
- **Authorization representations:** withheld bytes, identities, quantity caps,
  search result shape, metadata, share attributes, JSON-LD, page variants, and
  Turbo payloads all matter. HTML-only text inspection is insufficient.
- **Records:** a removed public record returns an actual 404; missing admin
  records redirect with a notice. Merged topic URLs and duplicate meeting URLs
  have distinct redirect mechanisms.
- **Framework delivery:** Active Storage blob/proxy/representation/direct-upload
  and Action Mailbox routes appear in the development route set. They are not
  resident editorial/account workflows. They do not inherit the application's
  `SiteAccess` gate; possession of a source/blob URL is a separate boundary.
  Production route/configuration behavior was not inspected.
- **Static/unrouted files:** robots/llms guidance and static error pages are
  served outside controller routes. Old password and PWA templates remain in
  `app/views` without corresponding application routes. They are not evidence
  of available password sign-in, password reset, or installed PWA support.
- **Health:** `/up` checks boot health, not successful sign-out, database data
  integrity, worker completion, email delivery, or provider availability.

Data and external dependencies are in [data-and-background.md](data-and-background.md).
