# Read-only resident API

Active accounts can create named API keys in **Account → API keys**
(`/settings/api_keys`). A fresh sign-in or step-up is required to issue a key.
Choose 30, 90, or 180 days, copy the full key once, and save it in the tool's
secret settings. Later visits show only its name, status, suffix, and dates.
Revoke an individual key or all your keys from the same screen.

Keys read the full resident content available to an active website account in
either public-access mode. Administrator-owned keys have the same fixed scope.
They cannot write content, run jobs, manage credentials, read site accounts, or
open any `/admin/` page. Browser cookies and crawler identity do not authenticate
the API. Key-management and admin screens require browser authentication.

## Connect a client

Set `TRR_BASE_URL` to your site's origin and `TRR_API_KEY` to the saved key in
your tool's secret configuration. Send the credential only in the header:

```sh
curl --fail-with-body \
  -H "Authorization: Bearer $TRR_API_KEY" \
  "$TRR_BASE_URL/api"
```

`GET /api` is an authenticated JSON handbook with absolute endpoint URLs,
pagination instructions, source labels, and error codes. All content endpoints
support GET and HEAD, return JSON, and use `Cache-Control: private, no-store`.
Responses have no ETag or Last-Modified validators. Do not send keys in URLs.

## Two bot workflows

### Find what changed since the last visit

Start with `/api/v1/meetings?sort=updated` and
`/api/v1/topics?sort=updated`. Add `updated_since` for an incremental check:

```sh
curl --fail-with-body --get \
  -H "Authorization: Bearer $TRR_API_KEY" \
  --data-urlencode "updated_since=2026-10-01T00:00:00Z" \
  --data-urlencode "sort=updated" \
  "$TRR_BASE_URL/api/v1/meetings"
```

`updated_since` is inclusive and requires an ISO 8601 timestamp with a timezone.
When supplied, it defaults sorting to `updated`. A meeting held months ago can
appear first when its minutes, transcript, or preferred analysis arrive today.
`from` / `to` still refer to **meeting dates**; combine them only when you want
to restrict updates to meetings held within that date range.

Meeting and topic payloads contain `updated_at` derived from their own record
and resident child records. Meeting updates also consider the latest document
of each supported type and substantive agenda items; topic updates consider
briefings, appearances, and aliases. `last_document_updated_at` and
`last_analysis_updated_at` distinguish available source updates from generated
analysis updates. Meetings also report `available_document_types`,
`has_analysis`, and `has_transcript`; topics report `has_analysis`. A transcript
source can appear in document types before readable text is available;
`has_transcript` becomes true when stored text can be read.
Document metadata has its own `created_at` and `updated_at`.
These timestamps retain microsecond precision. `last_activity_at` and
`starts_at` continue to describe civic activity and meeting dates.

Follow the meeting's `links.documents`, `links.agenda_items`, and
`links.transcript` to read the updated material. Read each topic through its
`links.api` and continue into appearances and decisions. Follow `links.next`
for every page, preserve the returned timestamp precision, overlap polls, and
deduplicate by resource ID and `updated_at`. Pages are live and offset-based;
concurrent changes can shift results. This is discovery of current available
content, not an event stream, deletion log, or exact replication protocol.
Resource-row maintenance can also advance its update timestamp. An unchanged document re-fetch (matching SHA or HTTP 304) refreshes last-checked time and cache headers without advancing `updated_at`; `updated_at` moves when the document content changes. Repeat scrapes or parses that find no meeting or document changes do not advance the meeting timestamp.

### Research a question across meetings and topics

Search both collections; they provide complementary entry points:

```sh
curl --fail-with-body --get \
  -H "Authorization: Bearer $TRR_API_KEY" \
  --data-urlencode "q=stormwater" \
  "$TRR_BASE_URL/api/v1/meetings"

curl --fail-with-body --get \
  -H "Authorization: Bearer $TRR_API_KEY" \
  --data-urlencode "q=stormwater" \
  "$TRR_BASE_URL/api/v1/topics"
```

Meeting search combines existing body/date and approved-topic-name matches
with official document/transcript full text, substantive agenda titles/plans,
and the preferred resident summary's headline, highlights, public input, and
item analysis. Topic search covers names, aliases, descriptions, headlines,
current-state narratives, what to watch, process concerns, and timeline events.
Legacy resident narratives remain searchable. PostgreSQL full-text matching
supports word stemming and quoted phrases for the narrative/source branches;
name/description/body matches also retain the existing substring behavior.
Results use date/activity order rather than relevance scores by default.

Combine meeting searches with `committee_id`, `from`, `to`, or `status`, and
topic searches with `lifecycle`. Either can also use `updated_since` and
`sort=updated`. Follow a topic's briefing, appearances and decisions to trace
its history; follow meeting detail/agenda/document/transcript links to inspect
individual evidence. Verify generated claims against the official source URLs.
Search indexes only named resident fields in generated JSON, so internal notes
and malformed nested values cannot influence the results. Superseded or
cancelled recaps do not become research matches through their hidden analysis.

## Endpoints and fields

Paths below begin with `/api/v1`.

| Path | Resident content | Filters |
| --- | --- | --- |
| `/home` | Website top stories, wire selections, upcoming council meetings | — |
| `/topics` | Approved topics, headlines, lifecycle, impact, illustrations and links | `q`, `lifecycle`, `updated_since`, `sort` |
| `/topics/:id` | Topic briefing, current state, what to watch, process concerns, upcoming appearances and history links | — |
| `/topics/:id/appearances` | Generated timeline events and recorded agenda appearances, with distinct event identities | `limit`, `offset` |
| `/topics/:id/decisions` | Linked motions, outcomes, public official identities and votes | `limit`, `offset` |
| `/meetings` | Canonical meeting identities, cancellation, preferred summaries and source links | `q`, `from`, `to`, `committee_id`, `status`, `updated_since`, `sort` |
| `/meetings/:id` | Meeting details, summary, approved topics, latest source documents and child links | — |
| `/meetings/:id/agenda_items` | Substantive agenda items, displayed analysis, evidence labels, approved topics, motions and votes | `limit`, `offset` |
| `/meetings/:id/documents` | Latest agenda, packet, minutes and transcript metadata and original URLs | `limit`, `offset` |
| `/meetings/:id/transcript` | Stored recording transcript text, source URL, quality, checksum and chunk boundaries | `limit`, `offset`, `document_id`, `checksum` |
| `/committees` | Resident committee directory | `limit`, `offset` |
| `/committees/:slug` | Description, public roster, current public titles, roster provenance and recent approved topics | — |
| `/officials` | Civic officials and current titles; these are `Member` records, not website `User` accounts | `limit`, `offset` |
| `/officials/:id` | Current offices, committee memberships, official source links, attendance and peer comparison | — |
| `/officials/:id/votes` | Resident-visible voting record using the website's topic grouping and procedural-vote rules | `limit`, `offset` |

All collection endpoints accept `limit` and `offset`, including lists whose
filter column omits them. Limits default to 50 and cannot exceed 100. Offsets are
nonnegative integers. Responses contain `data`, `pagination` (offset, limit,
returned count, total count), and `links.self` / `links.next`. Follow `links.next`
until it is null. Ordering is stable for unchanged data, but these are live
reads: content changes between pages can shift offsets.

Single resources and the homepage return `data` and `links.self`. Summary
projections contain the headline, highlights, public input, source type,
generation time, and a link to agenda-item analysis. Legacy summaries retain
`legacy_markdown` when structured generation data is absent. Internal generation
fields, prompts, review notes, account details, and credentials are excluded
recursively. Topic references always require approved visibility.

`sort` accepts `date` or `updated` for meetings and `activity` or `updated` for
topics. All orders put the newest value first with an ID tiebreaker.

`lifecycle` accepts `active`, `dormant`, `resolved`, or `recurring`. Meeting
`status` accepts `scheduled` or `cancelled`; `from` and `to` are inclusive ISO
dates. Searches are text of at most 200 characters. Duplicate meeting IDs resolve
to the same preferred record; details include both `requested_id` and
`canonical_id`. Cancelled meetings never return a generated recap.

## Read a complete transcript

The first request can omit revision parameters:

```sh
curl --fail-with-body \
  -H "Authorization: Bearer $TRR_API_KEY" \
  "$TRR_BASE_URL/api/v1/meetings/123/transcript"
```

Transcript limits are **Unicode characters**, defaulting to 20,000 with a maximum
of 50,000. Append each `data.text` chunk and follow `links.next`. Continuation URLs
pin the document ID and SHA-256 checksum. A continuation with a positive offset
requires both revision values. Changed or replaced text returns 409; restart at
offset zero instead of mixing revisions. A missing transcript returns 404.

## Source authority

Official documents remain authoritative. Generated summaries, agenda-item
analysis and topic timelines are labelled `ai_generated`; recording transcripts
are supplemental text and are not official minutes. Document responses preserve
the original source URL and quality metadata. Citation objects preserve `label`,
`document_id`, `source_url`, and `page_number`. Validated references add `status:
"resolved"`, `source_id`, `source_type` (document type), `source_version`,
`citation_id`, and `location` (`whole_source` or `pdf_page`, with a page number).
PDF URLs include `#page=N`; transcript references link to the recording, with no
invented page or timestamp. Whole-source labels identify their scope explicitly.
Legacy or changed-source references return `status: "unresolved"`, a `reason`,
and null document/link/page fields while retaining the legacy label. The API
never infers a source from an ambiguous label such as “Page 4,” and does not
return raw source catalogs or internal citation metadata. Citation-only repairs
advance the recap timestamp and are discoverable through `updated_since`.
Illustrations are labelled as illustrative.

## Errors and limits

Errors use `{ "error": { "code": "…", "message": "…" } }`.

| Status | Meaning |
| --- | --- |
| 401 | Missing, malformed, expired, revoked, or owner-ineligible credential; replace or sign in to inspect your keys |
| 404 | Resource or resident-visible content not found; unsupported routes and write verbs also return 404 |
| 409 | Transcript revision changed; restart the read |
| 422 | Invalid filters, pagination, or unpinned transcript continuation |
| 429 | Request limit reached; wait for `Retry-After` |

Each account has 120 authenticated requests per minute shared across its keys
and API endpoints. Invalid credentials have a separate limit of 30 requests per
minute per IP address. Rate-limited responses send `Retry-After: 60`.

## Operations and account management

Apply `20261002000000_create_api_access_tokens` during the normal release process.
No backfill, account provisioning, AI calls, or production keys are required.
The development-plan extension and detailed design are in
[the implementation spec](superpowers/specs/2026-10-02-read-only-user-api-design.md).

Admin **User Accounts** lists provisioned and currently active key counts for
each account. Account details show key names, status and lifecycle metadata;
admins cannot recover a full secret. Creation and revocation produce audit events
with snapshots that survive account deletion. They contain no secret or digest.

Only an HMAC-SHA256 digest is stored. Authentication uses the current owner status
on every request; disabling or rejecting an owner immediately suspends access.
Restoring account eligibility reactivates otherwise valid keys, so revoke keys
before restoring access if they should remain unusable. Deleting an owner deletes
their keys. Last-use timestamps are approximate, updated at most every 15 minutes.
Rotating `secret_key_base` invalidates all outstanding keys. Normal expiry or
replacement needs no application-secret rotation.
