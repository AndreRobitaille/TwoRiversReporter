# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Civic transparency site for Two Rivers, WI. Ingests official city meeting documents (PDFs, HTML), preserves them as authoritative records, and produces citation-backed AI summaries for residents. **Topics** (persistent civic concerns) are the primary organizing structure; meetings are inputs.

## Binding Documents

- **`docs/DEVELOPMENT_PLAN.md`** — Authoritative product spec and architectural constraints. Treat as binding.
- **`docs/topics/TOPIC_GOVERNANCE.md`** — Non-negotiable rules for all topic extraction, classification, summarization, and lifecycle logic. Read before any topic-related work.
- **`docs/plans/2026-03-28-atomic-design-system-spec.md`** — Authoritative visual design spec. Covers color palette, typography, graphic motifs (with SVG path data), component patterns, spacing, CSS architecture, and anti-patterns. Read before any UI/styling work.

## Instruction Precedence

If guidance overlaps, follow this order:

1. `docs/DEVELOPMENT_PLAN.md` for product and architecture requirements
2. Specialized binding docs for their domains
   - `docs/topics/TOPIC_GOVERNANCE.md` for topic logic
   - `docs/plans/2026-03-28-atomic-design-system-spec.md` for UI/styling
3. `CLAUDE.md` and `AGENTS.md` for repo working conventions
4. Tool-local memory or personal workflow notes

## Before Changing X, Read Y

- Topic extraction / triage / summaries / lifecycle → `docs/topics/TOPIC_GOVERNANCE.md`
- UI, CSS, components, themes → `docs/plans/2026-03-28-atomic-design-system-spec.md`
- Meeting/topic behavior or recent feature details → relevant spec in `docs/superpowers/specs/`
- Prompt template or AI pipeline work → the `deploying` skill (prompt-template deploy ordering)
- Deploy / production operations → the `deploying` skill + `config/deploy.yml`
- Homepage / topic show / meeting show / transcript pipeline → the `page-architecture` skill
- Sign-in, sessions, applications, admin access, transactional email → `docs/superpowers/specs/2026-07-23-passwordless-auth-and-applications-design.md`
- Anything an anonymous visitor can see → `docs/superpowers/specs/2026-07-24-tiered-public-access-design.md`
- Session lifetime, step-up reauthentication, IP or device matching → `docs/superpowers/specs/2026-07-25-session-and-reauthentication-hardening-design.md`

## Commands

Standard Rails and Omakase invocations (`bin/setup`, `bin/dev`, `bin/jobs`, `bin/rails test`, `bin/rubocop`, `bin/rails console`, `bin/rails db:migrate`) work as expected. Project-specific tasks:

| Task | Command |
|------|---------|
| Full local CI (lint + security, no tests) | `bin/ci` |
| Run job inline | `bin/rails runner "JobClass.perform_now(id)"` |
| Backfill topic descriptions | `bin/rails topics:generate_descriptions` |
| Seed category blocklist | `bin/rails topics:seed_category_blocklist` |
| Split a broad topic | `bin/rails topics:split_broad_topic[topic_name]` |
| Extract memberships from minutes | `bin/rails members:extract_from_minutes` |
| Merge members | `bin/rails members:merge[source_name,target_name]` |
| Auto-merge single-word members | `bin/rails members:cleanup` |
| List duplicate members | `bin/rails members:list_duplicates` |
| Validate prompt templates | `bin/rails prompt_templates:validate` |
| Regenerate OG image (social preview) | `bin/rails og:generate` |
| Backfill all meetings since 2025 | `bin/rails backfill:run` |
| Check backfill progress | `bin/rails backfill:status` |
| Backfill transcripts (date range) | `bin/rails "transcripts:backfill[2026-01-01,2026-04-09]"` |
| Backfill agenda-only preview summaries | `bin/rails agenda_previews:backfill` |
| Import local SRT files | `bin/rails "transcripts:import[/path/to/srt/files]"` |

CI (`bin/ci` / `config/ci.rb`) runs: setup, rubocop, bundler-audit, importmap audit, brakeman. Note: CI does **not** run tests currently.

When host binding matters for local development, prefer `0.0.0.0` over `localhost`; the dev machine is accessed remotely.

`bin/rails og:generate` requires Chromium (`chromium`, `chromium-browser`, or `google-chrome` on `PATH`) and optionally `pngquant` for PNG compression. On Arch: `sudo pacman -S chromium pngquant`. The task renders `app/views/og/default.html.erb` to a temp file, screenshots it at 1200×630, writes `public/og-image.png`, and cleans up. Only rerun when the OG design changes.

## Verification Expectations

- Ruby/model/job/service changes: run targeted Minitest files and `bin/rubocop`.
- Prompt changes: run local prompt validation; do not treat prod `prompt_templates:populate` as a substitute for verification.
- Multi-step AI/data pipeline changes: verify data across each major layer, not just the final rendered output.
- Before claiming work is complete, state what commands or checks were actually run.

For multi-pass AI/data pipelines, verify upstream → downstream preservation explicitly. Do not assume that more specific-looking final output proves the upstream data flowed through every layer. When possible, compare counts or distinctive content at each stage.

## Architecture

### Data Flow (Ingestion Pipeline)

```
City Website → Scraper Jobs (discover/parse meetings)
  → Document Download → PDF Text Extraction (+ OCR if image scan)
  → Topic Detection & Association (AI) ← runs on agenda parse AND minutes arrival
  → Topic Continuity Analysis (lifecycle derivation)
  → Summarization (topic-aware, with citations)
      • agenda_pdf only → SummarizeMeetingJob(:agenda_preview) with 5-min delay
        (meeting-level preview summary + TopicBriefing refresh; no TopicSummary)
      • packet_pdf → SummarizeMeetingJob immediately (:full, produces packet_analysis)
      • minutes_pdf → SummarizeMeetingJob 10-min delayed (:full, produces minutes_recap)
      Higher tiers destroy lower-tier summaries: minutes > transcript > packet > agenda_preview
  → Resident-Facing Pages

YouTube Channel → DiscoverTranscriptsJob (match videos to recent council meetings)
  → DownloadTranscriptJob (fetch auto-captions via yt-dlp)
  → SummarizeMeetingJob (preliminary summary if no minutes; supplementary context when minutes arrive)
```

### Core Domain Models

- **`Topic`** — Central organizing model. Has `status` (approved/proposed/blocked), `review_status`, `lifecycle_status` (active/dormant/resolved/recurring). Linked to meetings via `AgendaItemTopic`. Has aliases, blocklist entries, appearances, status events, summaries.
- **`Committee`** — Governing body (city board, tax-funded nonprofit, or external). Has `committee_type`, `status` (active/dormant/dissolved), `description` (injected into AI prompts). Linked to meetings via FK, members via `CommitteeMembership`, and historical names via `CommitteeAlias`. Normalizes the free-form `body_name` string.
- **`MeetingAttendance`** — Per-meeting roll call record. Tracks present/absent/excused with attendee type (voting_member/non_voting_staff/guest). Created by `ExtractCommitteeMembersJob`. Drives automatic CommitteeMembership creation and departure detection (2 consecutive absences from roll call).
- **`Meeting`** — Single official meeting. Has documents, agenda items, motions, summaries. `belongs_to :committee` (optional); keeps `body_name` as historical display text.
- **`MeetingDocument`** — PDF/HTML/transcript artifact. Has `extracted_text`, `text_quality`, `ocr_status`. Page-level text stored in `Extraction` rows. Document types: `agenda_pdf`, `agenda_html`, `packet_pdf`, `packet_html`, `minutes_pdf`, `minutes_html`, `transcript`. Transcript documents store YouTube auto-captions with `text_quality: "auto_transcribed"`.
- **`Member`** — Public official or committee member. Has canonical `name`, linked via `MemberAlias` for name variants (titles stripped, suffixes removed, last-name-only entries auto-aliased). `Member.resolve(raw_name)` centralizes normalization + alias lookup + auto-aliasing. Merge duplicates via `Member#merge_into!(target)`.
- **`AgendaItem`** — Item on agenda. Links to topics via `AgendaItemTopic`. Has motions and votes.
- **`KnowledgeSource` / `KnowledgeChunk`** — Admin-maintained context for RAG. Chunks have vector embeddings.
- **`TopicSummary` / `MeetingSummary`** — AI-generated summaries. Topic summaries use a two-pass architecture (structured analysis → editorial rendering). Meeting summaries use a single-pass architecture — `generation_data` stores structured JSON (headline, highlights, public_input, item_details) rendered directly by the view. Internal categories (factual record, institutional framing, civic sentiment) exist in `TopicSummary.generation_data` JSON but are synthesized into unified editorial prose for display. `MeetingSummary.summary_type` is one of: `minutes_recap`, `transcript_recap`, `packet_analysis`, `agenda_preview`. `generation_data["source_type"]` tracks the source: `"minutes"`, `"transcript"`, `"minutes_with_transcript"`, `"packet"`, or `"agenda"`. Supersede chain when regenerating from a higher-tier source: minutes > transcript > packet > agenda_preview.
- **`TopicBriefing`** — Rolling briefing per topic (one record, updated in place). Has `headline` (backward-looking, used for "What Happened" cards), `upcoming_headline` (forward-looking, used for "Coming Up" cards; nullable), `editorial_content`, `record_content`, and `generation_tier` (headline_only/interim/full). Both headline fields are generated by AI; `upcoming_headline` is null when no future meetings exist.
- **`GeneratedImage`** — Polymorphic ActiveStorage-backed model for `Meeting` and `Topic` image assets. Stores provenance/controls for generated civic images.
- **`PromptTemplate`** — Stores AI prompt text (system_role + instructions) with `{{placeholder}}` interpolation. 15 fixed templates (seeded), editable via admin UI. Auto-versions on save via `PromptVersion`.

### Key Services

- **`Ai::OpenAiService`** — All OpenAI calls centralized here. Two model constants: `DEFAULT_MODEL` (gpt-5.2, reasoning) and `LIGHTWEIGHT_MODEL` (gpt-5.4-mini, for cheap tasks like description generation). Note: the `-mini` models do **not** support the `temperature` parameter — the API returns 400 if you set it. Key summary methods use a two-pass architecture: `analyze_topic_briefing` / `render_topic_briefing` (rolling briefings) and `analyze_topic_summary` / `render_topic_summary` (per-meeting snapshots). Prompts loaded from `PromptTemplate` (database); no hardcoded fallback — missing templates raise `RecordNotFound`. When using `response_format: { type: "json_object" }`, messages MUST contain the word "json" or OpenAI returns 400.
- Other services (`RetrievalService`, `VectorService`, `Topics::*`, `GeneratedImages::*`) are discoverable under `app/services/`. All OpenAI usage routes through `Ai::OpenAiService` regardless of caller.

### Authentication & Membership

**There are no passwords.** `password_digest`, `totp_*` and `recovery_codes_digest` were dropped from `users`; there is no password, TOTP, recovery-code or MFA route left in the app. Product-level model and constraints are in `docs/DEVELOPMENT_PLAN.md` (Membership and Authentication); implementation detail is in `docs/superpowers/specs/2026-07-23-passwordless-auth-and-applications-design.md`; production configuration is in the `deploying` skill.

- **Two sign-in paths.** `MagicLink` — 15-minute expiry, single use, only the HMAC digest is stored (`MagicLink.consume!` locks the row and marks `used_at`). `PasskeyCredential` — WebAuthn, configured in `config/initializers/webauthn.rb` from the three `WEBAUTHN_*` env vars. WebAuthn is `[SecureContext]`-only, so passkeys are invisible over plain-HTTP origins; develop against `localhost`, not the LAN IP.
- **Membership is by application.** `MembershipApplication` moves `email_pending → submitted → approved | rejected`. `User.status` is `pending | active | rejected`, gated by `active_for_authentication?` (active **and** `disabled_at` blank). Admin approval at `/admin/users/:id` activates the account and emails a magic link in one transaction; a delivery failure rolls the approval back.
- **Admin access needs a passkey.** `Admin::BaseController` requires admin + `active_for_authentication?` + at least one `PasskeyCredential`. A magic-link-only admin is redirected to `/settings/security`.
- **Throttles.** `SignInAttempt` allows one delivery per address per `SignInAttempt::WINDOW` (15 minutes), released via `SignInAttempt.release!` when delivery actually fails so an outage doesn't lock someone out. Separately, `rate_limit to: 10, within: 3.minutes` per IP on sessions, applications and passkeys.
- **Sessions.** `Session::INACTIVITY_LIMIT` (60 days) is rolling — `touch_last_seen_if_stale!`
  refreshes `last_seen_at` at most once per `Session::TOUCH_INTERVAL`. `Session::ABSOLUTE_LIFETIME`
  (1 year, from `created_at`) is a hard ceiling that active use cannot extend. `Session#expired?`
  ORs the two, and `resume_session` destroys the session and clears the cookie when it expires or
  the user stops being active.
- **Sessions are anchored to a context.** `ip_prefix` (IPv4 /24, IPv6 /48 via `NetworkPrefix`) and
  `device_fingerprint` (browser family and platform, version discarded, via `DeviceFingerprint`)
  are recorded at sign-in and compared on every admin request through `SessionContext`.
  **A mismatch never destroys a session** — it withholds sensitive surfaces until a step-up.
  `Reauthentication#require_verified_context` guards the admin boundary;
  `require_fresh_reauthentication` guards hard-deleting a user or application, creating or granting
  admin, and adding or removing a passkey, requiring proof within `Session::REAUTH_FRESHNESS`
  (15 minutes) regardless of context. The accepted cost: entering `/admin` from a genuinely new
  network costs one passkey tap. On mobile, moving between cell towers can cross a /24, so
  occasional taps during phone admin use are expected behavior, not a defect.
- **A step-up rewrites the recorded context and stamps `reauthenticated_at`**, so accepting a new
  network and proving you are still there are one operation. A fresh sign-in also stamps it, which
  is what lets a new member add a first passkey without a second email.
- **The step-up magic link is the ordinary sign-in link, deliberately.** An emailed link often
  opens in a different browser than the one awaiting step-up — tapped from a phone while the
  session sits in desktop Chrome — where a reauth-specific token would have no session to apply to.
  Do not replace it with a dedicated purpose without solving that.
- **`ReauthenticationsController` is gated by neither callback.** Gating it redirects the page that
  fixes an unverified context to itself and locks out every admin at once. There is a test for this.
- **Destructive admin actions are recorded as `AuditEvent`s** with `actor_email` and `subject_label`
  snapshots, because those actions delete their own subjects. `AuditEvent.record!` and the
  corresponding `destroy!`/`update!` share one `ApplicationRecord.transaction`, so a refused
  deletion leaves no audit row. Readable at `/admin/audit_events`, linked from the admin dashboard's
  "Security & Users" card. `ExpiredAuthRecordsCleanupJob` runs daily at 4am (`config/recurring.yml`)
  sweeping expired sessions, used/expired magic links, and sign-in attempts past their window.
- **All transactional email goes through `TransactionalEmail` → `LoopsDelivery`.** No ActionMailer views, no other delivery path. `LOOPS_API_KEY` comes from encrypted credentials; outside production `Message#deliver_now` is a no-op, so local and test runs never hit Loops.

Two properties are load-bearing and easy to break without noticing:

- **The sign-in response is byte-identical** whether the address has an active account, a pending application, or no account at all. That identity is the enumeration protection — the *email* is what tells the real person which case they are in. Malformed addresses are dropped silently and before `SignInAttempt`, so garbage input cannot burn a real address's window. Do not add a branch-specific flash, status code, redirect target or timing difference to `SessionsController#create`.
- **URLs sent to Loops must be absolute.** `TransactionalEmail` builds them from `config.action_mailer.default_url_options` (per environment; production reads `APP_HOST`) and passes the options to each route helper explicitly. A bare path in an email is not clickable, and the magic link is the only way most members can sign in. Do not set `Rails.application.routes.default_url_options` globally to fix this — route-set defaults outrank the request host and would rewrite every redirect the app issues.
- **`SessionsController#consume_magic_link!` must redirect via `after_authentication_url`, not a hardcoded path.** It reads and clears `session[:return_to_after_authenticating]`, so both an ordinary sign-in and a step-up fallback land back on the page that was actually asked for instead of the home page. `after_authentication_url` checks the stored URL's host against `request.host` before using it, so this is not an open redirect. Simplifying this back to `redirect_to root_path` looks harmless and quietly reintroduces the bug it fixed.

### Page & Pipeline Details

Layout, helper, and data-flow detail for the homepage, topic show page, meeting show page, and YouTube transcript pipeline lives in the **`page-architecture` skill** (`.claude/skills/page-architecture/SKILL.md`). Invoke it before changing any of those surfaces.

## Production Deployment

Live at `https://tworiversmatters.com` (Hetzner VPS, Kamal 2, Docker + pgvector). Deploy commands, infrastructure, secrets, recurring jobs, and the mandatory **deploy-before-`prompt_templates:populate`** ordering live in the **`deploying` skill** (`.claude/skills/deploying/SKILL.md`). Invoke it before any production operation.

## Conventions

- **Single Rails app** — No microservices, no SPA. Server-rendered HTML + background jobs.
- **Thin controllers** — Business logic in services and jobs, not controllers.
- **Jobs must be idempotent** — Safe to re-run; clear/rebuild derived rows when appropriate.
- **Member resolution uses `Member.resolve`** — Both extraction jobs (`ExtractCommitteeMembersJob`, `ExtractVotesJob`) use `Member.resolve(raw_name)` instead of direct `find_or_create_by!`. This centralizes name normalization, alias lookup, and auto-aliasing.
- **AI calls go through `Ai::OpenAiService`** — Don't scatter OpenAI API calls elsewhere. Committee context injected via `prepare_committee_context` (database-driven, not hardcoded).
- **Generated civic images** — Topic generation is limited to the homepage top-six pool; meeting generation requires substantive structured content. Generated images are `GeneratedImage` records with ActiveStorage attachments, provenance, prompt/model/size metadata, superseding behavior, and admin repair controls: regenerate, custom prompt, upload, and disable.
- **Visual direction** — Generated civic images should resemble restrained local newspaper/editorial photos, not cartoons, vector art, AI explainer graphics, or symbolic collages. Use one dominant resident-visible physical anchor; do not try to show every meeting item. Prefer streets, curbs, sidewalks, utility infrastructure, homes, parks, lakefront/beach access, and public facilities. For named/specific local places or landmarks, use cropped non-identifying details rather than a full invented stand-in. Admin upload override is expected for hard local-facility cases. Rendering: homepage top-six cards use a small fixed side thumbnail (≈200×134 top stories, ≈104×78 wire cards) with no overlay label and no topic description; topic/meeting detail pages show an edge-to-edge feature image with a drop shadow and an "AI image" cutline. The `/topics` and `/meetings` index cards show a fixed 3:2 thumbnail (≈132px, matches the source aspect so it isn't over-cropped) when an image exists — floated-right inside the card body with the text wrapping around it on both topic and meeting cards (description dropped on topic cards). The float pattern keeps text readable at mobile widths instead of crushing it into a narrow column beside a fixed image; a `::after` clearfix on the body reserves the thumbnail height on short cards. Index/home image data is batch-loaded via the `LoadsGeneratedImages` controller concern (`generated_images_for(records, surface:)`). Image-less cards/pages omit the image with no reserved space (image-present layouts gated by a `--with-image` modifier class).
- **Generated image operations** — Image generation uses `Ai::OpenAiService#generate_civic_image` and defaults to `gpt-image-1` at `1536x1024`. After editing `lib/prompt_template_data.rb`, run `bin/rails prompt_templates:populate` locally before manual regeneration so the database prompt reflects code. For production, deploy first, then run `bin/kamal app exec "bin/rails prompt_templates:populate"` before regenerating images.
- **Summaries require citations** — All factual claims must trace to document artifacts (e.g., `[Packet Page 12]`).
- **Separate fact from inference** — Topic summaries distinguish factual record, institutional framing, and civic sentiment.
- **Credentials** — Encrypted in `config/credentials.yml.enc`, decrypted via `config/master.key` (gitignored). Access via `Rails.application.credentials.<key>`.
- **Style** — RuboCop Rails Omakase (`.rubocop.yml`). No Sorbet. Prefer clarity over metaprogramming.
- **Browser automation** — Prefer the `claude-in-chrome` MCP server; it drives a real Chrome, so you see actual rendering rather than a headless approximation. Fall back to the `agent-browser` CLI when no Chrome is available to attach to — working from an iPad, or any SSH-only session — since it launches its own headless Chrome on the dev machine and needs no extension. `agent-browser --help` documents its commands. Either way, drive the app through `localhost`, not the LAN IP: WebAuthn is `[SecureContext]`-only, so passkeys are invisible on a plain-HTTP IP origin.
- **Site access modes** — `SiteSetting.access_mode` is `open` (fully public) or `gated` (anonymous visitors get a teaser tier), switchable at `/admin/site_settings` with no deploy. Production currently runs **gated**. Views branch on the `gated_for_visitor?` helper only — never `authenticated?`, `Current.user`, or `SiteSetting` directly — and render truncated content via the `teaser` helper plus the `shared/_gate` partial. **Withheld content is never rendered**: not hidden, not CSS-blurred, and not smuggled into `data-` attributes, `title=`/`alt=`, `<meta>` tags (including `og:` and `twitter:`), turbo-stream payloads, or `?page=N` / format variants of the same URL. Helpers that build share text or meta descriptions must consult `gated_for_visitor?` themselves — gating the primary template is not sufficient. Several of the leaks found while building this were helpers whose justification had quietly expired: they derived share text or a meta description from content the page used to display and no longer does. Spec: `docs/superpowers/specs/2026-07-24-tiered-public-access-design.md`.
- **Gating tests need both halves** — `test/controllers/anonymous_leak_sweep_test.rb` sweeps every gated surface for a canary string in two passes (absent for anonymous, *present* when signed in, so an empty section can't pass as a gated one). A canary sweep catches "content that shouldn't be here" but never "the wrong two of the allowed two": a cap that shows two cards passes the sweep even when `?page=2` walks it forward to a *different* two. Quantity and identity caps need their own assertions — see the card-identity checks in `test/controllers/topics_index_gating_test.rb`.
- **Topic granularity** — Category names (Zoning, Infrastructure, Finance, etc.) are blocked as topic names. Topics must name specific civic concerns at "neighborhood conversation" level. See `docs/plans/2026-02-28-broad-topic-prevention-design.md`. Use `topics:split_broad_topic[name]` to re-extract items from an overly-broad topic.
- **Documentation** — When adding features, update `docs/DEVELOPMENT_PLAN.md` (authoritative spec), this file (CLAUDE.md), and any relevant GitHub issues. Documentation must be useful to any developer, not just AI tools.
- **Design system** — All colors via CSS custom properties, never hardcoded hex. Two themes: `.theme-living-room` (public, warm cream) and `.theme-silo` (admin, cool concrete). Spec at `docs/plans/2026-03-28-atomic-design-system-spec.md`.
- **SVG motifs** — Reusable partials in `app/views/shared/` (`_atom_marker`, `_diamond_divider`, `_starburst`, `_boomerang`, `_radar_sweep`). Atom marker and diamond divider used in both themes; starburst/boomerang are Living Room only; radar sweep is Silo only.
- **Typography roles** — Outfit (display: headings, stats, nav labels, always uppercase), Space Grotesk (body: paragraphs, buttons, forms), DM Mono (data: metadata, timestamps, status chips, always uppercase with wide tracking).

