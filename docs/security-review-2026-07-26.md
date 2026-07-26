# Security Review — July 26, 2026

This document records the disposition of the July 2026 application security
review. It is a backlog, not evidence that deferred risks have been remediated.
Product and architecture requirements in `docs/DEVELOPMENT_PLAN.md` and the
specialized governance and authentication specifications remain authoritative.

## Addressed in this review

- Rack was upgraded from 3.2.5 to 3.2.6 to fix the unbounded chunked multipart
  upload vulnerability. Thruster now rejects request bodies larger than 25 MiB
  before Rack parses them.
- Membership applications accept only HTTPS Facebook profile URLs on
  `facebook.com` or its subdomains. Both admin and member views also pass stored
  values through `safe_external_url`, which protects against unsafe legacy data.
- Administrator demotion, disablement, deletion, and final-passkey removal
  cannot leave the site without an active, passkey-backed administrator. Admin
  roster changes are serialized with database row locks, self-demotion and
  self-disable are refused in the controller, and disablement now requires fresh
  strict-context reauthentication.
- The production image pins the Ruby base-image digest and exact Deno and
  yt-dlp releases, verifies downloaded binary checksums, and excludes both
  development and test gems. A weekly fail-closed workflow checks the latest
  stable Ruby release, Dockerfile frontend, Deno, and yt-dlp metadata; validates
  a complete production image build; and opens a reviewable pull request
  without merging or deploying it.

## Deferred security backlog

### P1 — Constrain remote document retrieval and native parsing

Scraped city pages can introduce attachment URLs that `Documents::DownloadJob`
fetches without an origin allowlist, private-address rejection, redirect
revalidation, explicit byte limits, or explicit network timeouts. Downloaded
content then reaches Poppler and Tesseract without process timeouts or page and
resource caps.

Future work should:

- allow only HTTPS document origins required by configured government sources;
- resolve and reject loopback, private, link-local, and metadata-service
  addresses before each request and after every redirect;
- set open/read timeouts and a maximum response size;
- verify file signatures and MIME types before selecting a parser;
- cap PDF pages, extracted text, OCR resolution, runtime, memory, and temporary
  disk use; and
- isolate native document parsing from the web and job processes where
  practical.

### P1 — Reduce autonomous AI authority over civic records

Scraped agenda and attachment text is untrusted model input. Topic triage
currently applies model-provided names and confidence values automatically, and
merges destroy the source topic after moving its records.

Future work should:

- label and delimit retrieved text as untrusted data in system instructions;
- validate model output against immutable IDs included in the request;
- allow automatic mutations only for the proposed topics in that request;
- prohibit automatic merge, block, or deletion of approved topics;
- require human confirmation for destructive merges; and
- retain enough before-state to audit and reverse every automated mutation.

### P2 — Add a restrictive Content Security Policy

The Rails CSP initializer is disabled. Introduce a report-only policy first,
remove or nonce inline scripts and event handlers, account for importmap and the
configured font/analytics origins, then enforce the policy. This is defense in
depth for any future HTML or URL sanitization failure.

### P2 — Remove the latent SQL interpolation sink

`Topic.similar_to` binds the `WHERE` values but interpolates its `ORDER BY`
expression. Current callers pass normalized topic names, so the reviewed paths
are not directly exploitable, but the scope should use a bound SQL expression
so a future caller cannot turn it into an injection vulnerability.

### P2 — Bound outbound email calls and public-field abuse

`LoopsDelivery` has no explicit open, read, or write timeouts. Public
application fields also lack server-side length limits, and distributed
requests can bypass a throttle keyed only by source IP. Add short provider
timeouts, appropriate field lengths, and per-recipient throttling that preserves
email-enumeration resistance.

### P2 — Define retention for membership application data

Membership applications retain residential address, phone, Facebook profile,
notes, and submitted IP address. Establish and document a retention/deletion
policy, confirm encrypted backups and least-privilege database access, and
disclose IP collection where appropriate.

### Ongoing — Clear the remaining dependency advisories

The review's Bundler Audit found advisories beyond the directly exploitable Rack
issue. Upgrade the remaining affected gems in small tested groups, confirm
whether each vulnerable feature is reachable in production, and keep any
accepted exception narrow, documented, and time-bounded.
