# Read-only User API — Implementation Design

**Date:** 2026-10-02

**Status:** Adopted; implementation and local validation complete.

**Release:** Requested on 2026-10-02; follow the repository deployment playbook.

## Purpose and confirmed scope

Approved users should be able to give their own scripts or agents a revocable
API key for reading Two Rivers Reporter. The requested scope is all
resident-facing content, including summaries, transcripts, and public officials.
No API key needs access to anything in `/admin/`.

Users must be able to name a key when creating it so they can recognize its
purpose later. Admin user management must show whether keys have been
provisioned for each account, along with their names and current status.

A key delegates an existing person's resident access. It does not create a bot
account, a new role, or another way to become a member. Even a key owned by an
administrator has exactly the same resident-content scope as any other key.
There are no content writes or administrative API operations.

The requirements above come from the owner. Endpoint names, expiration choices,
pagination, and rate limits below are the adopted implementation defaults.

## Baseline before implementation

The inspected baseline had no API namespace or API-key model. It supplied:

- `User#active_for_authentication?`, requiring active status and no disable time.
- Browser account settings, magic links, passkeys, and step-up reauthentication.
- `AuditEvent` with actor/subject snapshots that survive user deletion.
- Approved topic visibility, meeting canonicalization, preferred summaries,
  public committee rosters, official positions, attendance, and votes.
- Solid Cache in production and parameter filters covering tokens, secrets,
  and keys.

The website's public-access mode controls anonymous HTML visitors. Approved
members see the full resident content in either mode. Verified crawler access
is a limited HTML/sitemap exception; it does not authenticate a person.

Meeting pages link to official documents and recordings. Transcript text is
stored in `MeetingDocument#extracted_text`, but is not rendered as a transcript
reader on the resident page. Exposing that text is explicitly included in this
API because the owner requested transcripts. `Member` means a civic
official; `User` means a site account. Only the former belongs in content
responses.

This inspection used local source in both repositories. No production account,
database, access mode, or deployment state was inspected or changed.

## Pattern to reuse from LegionPostTools

The relevant reference is personal `AgentAccessToken`, rather than the
organization-owned website publication token:

- A token belongs to a person and has a recognizable public identifier plus a
  random secret. Only an HMAC digest of the secret is stored.
- Authentication checks the secret with a constant-time comparison, then
  checks expiry, revocation, and the owner's eligibility.
- The person names the key, chooses an expiry, and sees its secret once.
- Creation requires a recent browser authentication. Token management is not
  part of the API, and bearer credentials cannot authenticate those screens.
- Last-use writes are throttled to one update per fifteen minutes.
- Revocation takes effect on the next authentication lookup.

Reference files in `~/Development/LegionPostTools/`:

- `app/models/agent_access_token.rb`
- `app/controllers/agent_access_tokens_controller.rb`
- `app/controllers/api/base_controller.rb`
- `test/models/agent_access_token_test.rb`
- `test/controllers/api/token_management_boundary_test.rb`

LegionPostTools also supports authorized writes and browser-session API access.
Those mechanisms are unnecessary for this fixed-scope, read-only API.

## Credential and browser workflow

Add `ApiAccessToken` with `user_id`, `public_id`, `secret_digest`, `display_hint`,
`name`, `expires_at`, `last_used_at`, `revoked_at`, and timestamps. Give `public_id`
a unique database index. Keep lifecycle attribution in `AuditEvent` rather than
adding another user foreign key for the revoker.

Use `trr_<public_id>_<secret>`, with twelve random bytes for the public identifier
and thirty-two random bytes for the secret, both hex encoded. Digest the secret
with HMAC-SHA256 and the application's existing `secret_key_base`, matching the
reference app. Rotating that application secret invalidates outstanding keys;
include this fact in the operator documentation.

Authentication requires all of: correct secret, `revoked_at` absent,
`expires_at > Time.current`, and `user.active_for_authentication?`. Re-read the
current owner on every request; do not cache authorization across requests.
Pending, rejected, disabled, or deleted accounts cannot use keys. Disabling an
account suspends its keys; reactivating it restores unexpired, unrevoked keys.
User deletion destroys its key rows while retaining audit snapshots.

Add an **API keys** tab in account settings, under `/settings/api_keys`:

1. List the current user's names, hints, creation/expiry dates, last use, and
   active/expired/revoked state. Display the user-supplied name prominently so
   they can identify what each key is for. Never show another person's keys.
2. The creation form includes a required **Name** field with guidance such as
   "What will you use this key for?" and examples like "Home dashboard" or
   "Research notebook". Trim surrounding whitespace, reject blank names, and
   use an 80-character name limit, as in the reference app. Names need not be
   unique. Include the name on the one-time reveal page and later key list.
   Offer 30-, 90-, or 180-day expiry, defaulting to 90 days.
3. Require fresh reauthentication and the strict context gate for issuance,
   reusing the existing step-up flow. Offer the existing passkey/email choices.
4. Reveal the plaintext once in the successful creation response, with copy
   instructions and `Cache-Control: no-store`. Do not place it in a redirect,
   flash/session, URL, audit metadata, or later key-list response. Disable Turbo
   caching for the reveal page as well.
5. Allow the owner to revoke an individual key or all their keys from their
   authenticated browser without another step-up, so revocation remains easy.
   Rotation is creating a replacement and revoking the old key.

These management mutations retain normal Rails CSRF protection. They accept
browser sessions only. Record creation and revocation with the actor, key public
identifier/name, expiry, and request context, never the secret or digest. Use
the existing settings components and Living Room design system for the owner
workflow.

## API-key visibility in admin user management

Extend the existing account-management pages rather than adding a separate
admin key inventory. This visibility uses the administrator's browser session
and the existing admin/passkey/context gates. It does not add administrative
scope to API keys.

On `/admin/users`, add an **API keys** column to all three account groups using
the shared account-row partial. Show "No keys" when none have been issued, or
a compact provisioned/active count such as "2 provisioned · 1 active". Total
provisioned counts include expired and revoked rows; distinguish previous
issuance from keys that can currently authenticate. Batch-load the counts for
the account list rather than querying each row separately.

On `/admin/users/:id`, add an **API keys** section alongside the existing
account/session information. List each key's user-supplied name, display hint,
creation time, expiry, last use, and state. Use this state precedence: revoked,
then expired, then suspended if the owner cannot authenticate, otherwise
active. For a disabled account with an unexpired/unrevoked key, show
"Suspended — account disabled" and count no active keys. Keep expired/revoked
key rows while the account exists so prior provisioning remains visible.

The section has a clear empty state, "No API keys have been provisioned for
this account." Names and hints are metadata; neither plaintext secrets nor
secret digests appear in HTML, attributes, alternate formats, or audit data.
Escape user-supplied names through the normal view helpers. This metadata is
available only in the authenticated admin browser UI, not through the resident
API. Follow the existing Silo table/panel patterns and the admin design spec.

Implementation touchpoints:

- `app/controllers/admin/users_controller.rb`: batch counts and the selected
  user's key metadata.
- `app/views/admin/users/index.html.erb` and `_account_row.html.erb`: consistent
  API-key column across Needs attention, Denied, and Approved groups.
- `app/views/admin/users/show.html.erb`: per-key names, lifecycle metadata, and
  the empty state.
- `docs/superpowers/specs/2026-07-26-admin-ui-revamp-design.md`: existing admin
  access, component, and responsive-layout guidance.

## API authentication and boundary

Require `Authorization: Bearer trr_...` on every API request, including the
handbook, HEAD requests, and any later conditional reads. This remains true in
both open and gated website modes. A cookie, claimed crawler identity, or token
in a query parameter cannot substitute for the header.

Use a separate `Api::BaseController < ActionController::API` shared by the
handbook and versioned content controllers. This avoids inheriting
the website's browser-version restriction, sign-in redirects, importmap ETags,
and HTML crawler exception. Keep the bearer identity in an API-specific
controller instance variable. Do not teach the
browser authentication concern to accept bearer credentials, and do not create
a browser session for a key.

Authenticate before looking up content. Missing, malformed, expired, revoked,
or ineligible credentials all return the same JSON `401` with
`WWW-Authenticate: Bearer`; do not reveal which condition failed. An invalid
header remains invalid even if a valid browser cookie accompanies it.

Only GET/HEAD content routes exist. Unsupported mutation requests have no
matching content route and return `404`, following normal Rails routing.
There are no API routes for keys, users, membership applications, audit logs,
jobs, prompts, knowledge-source administration, uploads, regeneration, or topic
moderation. Bearer headers alone cannot authenticate any browser settings or
`/admin/` request, including when the key owner is an administrator.

“Read-only” concerns civic content: requests cannot change records, enqueue
ingestion/generation jobs, invoke paid AI, or initiate repairs. Throttled key
last-use metadata and rate-limit cache counters are the expected operational
writes. Reading content must not invoke model helpers that create aliases,
resolve/create members, or change processing state.

## Proposed v1 endpoint surface

`GET /api` returns an authenticated JSON handbook with the fixed read-only
scope, endpoint URLs, filters, pagination, source labels, errors, and version.
Content lives under `/api/v1`; every response is JSON.

| Endpoint | Resident content |
| --- | --- |
| `/api/v1/home` | Current Top Stories, Wire, and Next Up selections and links |
| `/api/v1/topics` | Approved topic cards; `q` and lifecycle filters |
| `/api/v1/topics/:id` | Topic description, briefing/story, What to Watch, concerns, upcoming references, and links to decisions/history |
| `/api/v1/topics/:id/appearances` | Paginated meeting/agenda appearances and resident timeline entries |
| `/api/v1/topics/:id/decisions` | Paginated linked motions, outcomes, and roll-call votes |
| `/api/v1/meetings` | Canonical meetings; `q`, date-range, committee, and status filters |
| `/api/v1/meetings/:id` | Date, body, location, cancellation, source links, preferred summary, and links to agenda/documents/topics |
| `/api/v1/meetings/:id/agenda_items` | Ordered substantive agenda items, displayed analysis, citations, motions, votes, and approved topic references |
| `/api/v1/meetings/:id/documents` | Latest agenda, packet, minutes, and transcript metadata/source links used by the resident page |
| `/api/v1/meetings/:id/transcript` | Latest ingested transcript text, recording URL, text quality, and supplemental-source label |
| `/api/v1/committees` | Committee directory with the resident index's status/exclusion rules |
| `/api/v1/committees/:slug` | Description, current public roster, recent approved topic references, and meeting links |
| `/api/v1/officials` | Civic `Member` records with public-page links, names, and current titles |
| `/api/v1/officials/:id` | Public positions, current committee memberships, attendance aggregates, and vote-history link |
| `/api/v1/officials/:id/votes` | Paginated resident-visible voting record with motion, topic, meeting, and outcome references |

Keep response fields explicit. Topic briefings expose the displayed headline,
`what_to_watch`, `current_state`, `process_concerns`, and factual timeline fields;
retain the existing editorial-content fallback for older briefings. Meeting
summaries expose `summary_type`, source type, headline, highlights, public input,
item analysis, citations, and the legacy Markdown fallback when applicable.
Preserve the resident-facing public-input formatting/redaction behavior.

All associations are recursively allowlisted, including nested arrays in stored
JSON. Never return whole Active Record objects or wholesale `generation_data`.
`TopicSummary` is upstream pipeline material, not a separate resident-facing
archive: expose the displayed briefing rather than all stored intermediate
summaries. Likewise omit processing markers, moderation history, private
resident-context notes, prompt/model traces, embeddings, import records, and
raw PDF/OCR text. Transcript text is the deliberate exception described above.

Include existing resident illustration URLs/alt text when available and label
them illustrative. Do not expose generation prompts or uploader identity, and
do not generate an image when none exists.

## Content selection and source authority

Use `Topic.publicly_visible` for every topic lookup and embedded reference.
Proposed/blocked topics are unavailable even to an administrator's key. Return
JSON `404` for unavailable topic IDs; there is no HTML redirect.

Apply meeting identity/cancellation rules before pagination and totals. Lists
contain canonical meetings only. A duplicate detail ID returns the canonical
record with `requested_id` and `canonical_id`, without an HTML redirect. Follow
the website's preferred summary priority: minutes recap, transcript recap,
packet analysis, then agenda preview. A cancelled meeting returns cancellation
and planned/source content without a recap claiming the meeting occurred.

Committee rosters retain current terms and omit staff/non-voting memberships
as the resident pages do. Position titles retain official-source precedence.
Officials are never serialized from `User` or `MembershipApplication`.
Share the existing resident vote grouping/procedural filtering and attendance
calculations rather than making a competing interpretation in the API.

Keep source records and generated analysis visibly distinct in JSON:

- Official documents: document type, original source URL, and available
  document/page identifiers.
- AI summaries/briefings: `ai_generated: true`, generation time, summary tier,
  source type, citation labels, and links back to their evidence.
- Transcript: `official_record: false`, recording URL, stored text quality,
  and an explicit statement that the text supplements official minutes.
- Public positions/rosters: preserve source URL and verification date when
  present; attendance-derived membership must not be labelled official.

Preserve citation labels as stored. Resolve a document/page link only when the
stored evidence establishes that mapping; unknown document IDs/pages stay null.
Never infer that a transcript claim appears in approved minutes, invent a page,
or select an unrelated PDF just to make a citation clickable. API reads do not
regenerate or repair missing evidence.

## Response size, consistency, and operations

Use an envelope with `data`, collection `pagination`, and `links`. Return
ISO 8601 timestamps and absolute resident/source/API links. Use null for absent
single content and empty arrays for empty collections. Missing transcript text
returns a JSON `404` rather than a synthesized transcript.

Proposed collection defaults are `limit=50`, maximum 100, and nonnegative
`offset`, with `returned_count`, `total_count`, and `next` link. Every collection
has a stable sort with an ID tie-breaker. These are ordinary live reads, not a
database snapshot; offsets can shift as content changes. Validate filters and
pagination instead of accepting arbitrary scopes/includes/sort expressions.
Keep long histories in paginated endpoints rather than unbounded embedded
arrays; detail responses carry continuation links and explicit counts.

For transcripts, use character-offset pagination: default 20,000 characters,
maximum 50,000, with `offset`, `returned_chars`, `total_chars`, document ID,
content checksum, and next link. Preserve every character across chunks. Pin
continuation requests to the returned document ID/checksum and return `409` if
the current transcript changes, so clients cannot silently splice revisions.
The text endpoint reads stored content; it does not download from YouTube or
start a transcript import.

Set `Cache-Control: private, no-store` and `Vary: Authorization` on all API
responses, including errors. Do not introduce ETags/304 responses in v1.
Authentication must remain before any future cache revalidation. Key secrets
belong in a client's secret store and Authorization header, never links, request
parameters, public browser code, analytics, or logs. Server-side scripts/agents
are the initial client use case; no permissive cross-origin browser access is
needed.

Start with a shared Solid Cache request budget of 120 requests/minute per owner,
so creating more keys cannot multiply it. Use a separate pre-authentication IP
budget for invalid/missing credentials; choose its threshold during
implementation so it does not throttle valid owners behind a shared IP. Return
JSON `429` with `Retry-After`. These values are initial defaults, not a measured
capacity claim. Preload relationships and check query behavior with realistic
collections before settling them.

## Implementation sequence

1. Add the token migration/model, owner association, audit events, browser
   settings with required purpose names, one-time reveal, revocation, admin
   account-list counts/detail metadata, and authenticated `/api` handbook.
2. Add the isolated JSON base controller, shared authentication, cache headers,
   and rate limiting. Prove the browser/admin boundary before adding content.
3. Add resident query/serializer services for topics, canonical meetings,
   summaries, documents, and transcript chunks. Extract small shared read
   selectors where website/API behavior must match; preserve HTML behavior.
4. Add homepage selections, committee/official serializers, attendance, and
   paginated decisions/votes/history. Verify recursive visibility and source
   provenance throughout.
5. Publish the endpoint/field contract and a short client example in repository
   documentation and the authenticated handbook; update the authoritative
   development plan when the design is adopted. Complete local verification
   before any separately authorized release.

Each step needs its own tests and remains part of the requested complete
resident-content API. The sequence is not a proposal to stop after key issuance.
No production keys, account changes, backfills, or paid AI calls are needed to
implement it.

## Required verification before implementation is complete

Use synthetic test data, including distinct content at the beginning, middle,
and end of summaries, timelines, vote collections, and transcripts.

- Valid keys read every documented endpoint; malformed, expired, revoked,
  pending-owner, rejected-owner, disabled-owner, and deleted-owner credentials
  fail. Test exact expiry and owner status changes after successful use.
- Issuance stores no plaintext, reveals it once, requires fresh browser proof,
  and cannot be performed by bearer credentials. One owner cannot list or
  revoke another owner's key. Revocation/audit snapshots survive user deletion.
- Key creation trims names and rejects blank/overlong names. The supplied name
  appears on the reveal page, owner list, and admin detail view; HTML in a name
  is escaped. Duplicate names do not prevent issuance.
- Admin account rows distinguish no provisioning from active, expired, revoked,
  or owner-suspended keys. Verify totals and active counts independently. The
  detail view shows each key's name and lifecycle metadata without secrets or
  digests; ordinary users and bearer-only requests cannot read this metadata.
- Keys never authenticate browser settings or admin pages, never inherit admin
  powers, and cannot write civic content or trigger jobs/AI. A valid session
  cookie cannot rescue an invalid API header or authenticate the API alone.
- Open/gated mode, crawler claims, JSON/format variants, HEAD, and conditional
  headers cannot bypass credential validation or retain authorized content in
  a cache after revocation. API errors contain no content or credential details.
- Only approved topics appear in lists, lookups, search, and nested references.
  Put canaries in internal notes and nested JSON fields and assert they are
  absent. Prove allowed content is present first, then remove each meaningful
  guard and confirm its exclusion test fails, restoring the guard afterward.
- Compare canonical meeting IDs/counts, cancellation state, summary priority,
  roster identities, public title precedence, vote grouping, and attendance
  against the website selectors. Test quantity/identity boundaries separately
  from text canaries.
- Reconstruct all paginated histories and transcript chunks; assert exact
  counts/content, no lost trailing text, preserved Unicode, and rejection of
  mixed transcript revisions. Assert rate limiting works across multiple keys
  owned by one user and returns `Retry-After`.
- Verify the settings flow, one-time reveal, admin API-key column, and admin
  key-detail section at desktop and narrow widths.
  Local thumbnails missing because generated blobs are absent are expected.

Run targeted Minitest files and `bin/rubocop`; after migrations run
`bin/rubocop -A db/schema.rb` and inspect the schema diff. Because this introduces
authentication and a new response surface, run `bin/ci` before claiming the
implementation complete. Record the actual commands/results, including any
blocked checks. The verification record below distinguishes completed local checks from release
work, which requires separate authorization.

## Local implementation and verification record — 2026-10-02

Implemented the complete endpoint surface and named-key lifecycle described
above. `Api::BaseController` serves both the handbook and versioned resources,
with a controller-local bearer identity. A Rack boundary strips automatically
added validators before conditional responses and returns JSON for unsupported
API routes. Website and API reads share homepage, committee directory, preferred
summary, attendance, and voting selectors. The client/operator contract is
[documented separately](../../read-only-api.md).

Completed checks:

- `bin/rails db:migrate`, `bin/rubocop -A db/schema.rb`, and schema diff inspection:
  only the token table, its indexes/foreign key, and schema version changed.
- Targeted model, API, settings, admin, resident controller, and reanalysis tests:
  134 tests / 1,089 assertions passed before the final CSRF case; the separate
  final settings suite passed 6 tests / 72 assertions with CSRF enforcement.
- `PARALLEL_WORKERS=1 GEM_SPEC_CACHE=/tmp/trr-gem-spec-cache RUBOCOP_CACHE_ROOT=/tmp/trr-rubocop-cache bin/ci`:
  application tests passed **1,882 tests / 8,599 assertions**, with no failures
  or errors and one existing fixture-dependent skip. Gem audit, importmap audit,
  and Brakeman passed with no vulnerabilities/warnings. The aggregate command
  reported one trailing blank line from cleanup; this was fixed, and a separate
  full `bin/rubocop` rerun passed all 557 files. The initial Brakeman cache-write
  restriction was resolved with the writable `GEM_SPEC_CACHE` above.
- `bin/rails zeitwerk:check`, `git diff --check`, and test-environment
  `bin/rails assets:precompile` passed.
- Seven temporary guard removals each caused the intended exclusion test to
  fail: bearer authentication, owner eligibility, topic lookup visibility,
  nested topic visibility, issuance freshness, issuance context, and the Rack
  response-cache boundary. Every guard was restored. Quantity and identity
  checks independently verified collections, duplicate meetings, and complete
  Unicode transcript reconstruction.
- Agent-browser review at 1440px and 390px used an isolated test database and
  fictional accounts. Creation, one-time reveal, copy feedback, confirmation
  and revocation worked; owner settings, admin counts and admin key details
  matched Living Room/Silo styling. No horizontal page overflow occurred;
  the admin account table uses its existing internal horizontal scroll. Phone
  buttons have 44px touch targets. Saved reveal imagery used a nonworking
  placeholder instead of a credential. The review session/database were removed
  afterward.

No production inspection, data changes, key provisioning, commit, push, or
release were performed. Deployment still requires the normal separately
requested release process and migration.

## Bot discovery workflows — 2026-10-02 extension

The owner identified two primary bot tasks: finding recently updated reporting
(especially meetings receiving new documents/analysis), and researching a subject
across meetings and topics. Both collection endpoints now accept `updated_since`
(inclusive ISO 8601 with timezone) and `sort=updated`; supplying the timestamp
defaults to update sorting. Default date/activity browsing remains available.

Effective `updated_at` includes resident child-record timestamps rather than
relying on a meeting's held date or a topic's last civic activity. Responses add
separate document/analysis timestamps and availability flags, plus direct meeting
follow-up links. Metadata aggregation fetches only IDs/types/timestamps, not all
stored PDF or transcript text. Pagination preserves update/search filters and
microsecond boundaries. Live offset discovery requires overlap/deduplication;
it is not a durable change/deletion log.

Research search adds full-text matching on whitelisted resident summary/briefing
fields and substantive agenda plans. Public source text, approved-topic names,
body/date matches and topic aliases remain searchable. Summary preference and
cancellation apply before generated analysis can produce a match. JSON-path
string-type checks prevent malformed scalar hashes or internal nested fields
from acting as a search oracle. The shared preferred-summary selector preserves
subsecond precision to agree with the database selection on regenerated recaps.

The authenticated handbook and client contract lead with these two workflows.
No new database migration, pipeline job, AI call, or UI redesign is required.

Extension validation: targeted API and existing meeting-controller tests passed
69 tests / 880 assertions; full RuboCop passed 559 files, Zeitwerk loading and
diff whitespace checks passed. Five temporary removals independently proved the
resident JSON search whitelist, scalar type guard, approved research scope,
child-document update detection, and subsecond recap preference tests fail when
their guard is absent. Every change was restored before the final CI run.

Final extension CI passed using
`PARALLEL_WORKERS=1 GEM_SPEC_CACHE=/tmp/trr-gem-spec-cache RUBOCOP_CACHE_ROOT=/tmp/trr-rubocop-cache bin/ci`:
**1,891 tests / 8,728 assertions**, zero failures/errors, one existing skip;
all 559 Ruby files passed lint, both dependency audits passed, and Brakeman
reported zero warnings. Search expressions and priority ordering use explicit
Arel/Active Record query builders after the initial scanner flagged assembled
SQL; no scanner warnings were suppressed. The final suite includes transcript
availability before/after extraction. Release follows the normal deployment playbook and separately requested production verification.
