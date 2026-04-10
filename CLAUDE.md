# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Civic transparency site for Two Rivers, WI. Ingests official city meeting documents (PDFs, HTML), preserves them as authoritative records, and produces citation-backed AI summaries for residents. **Topics** (persistent civic concerns) are the primary organizing structure; meetings are inputs.

## Binding Documents

- **`docs/DEVELOPMENT_PLAN.md`** — Authoritative product spec and architectural constraints. Treat as binding.
- **`docs/topics/TOPIC_GOVERNANCE.md`** — Non-negotiable rules for all topic extraction, classification, summarization, and lifecycle logic. Read before any topic-related work.
- **`docs/plans/2026-03-28-atomic-design-system-spec.md`** — Authoritative visual design spec. Covers color palette, typography, graphic motifs (with SVG path data), component patterns, spacing, CSS architecture, and anti-patterns. Read before any UI/styling work.

## Tech Stack

- Rails 8.1, Ruby 4.0, PostgreSQL (with pgvector for embeddings)
- Server-rendered HTML, Turbo/Stimulus, ImportMap, Propshaft
- Atomic-era design system with two themes: Living Room (public) and Silo (admin)
- Typography: Outfit (display), Space Grotesk (body), DM Mono (data) via Google Fonts
- Solid Queue (jobs), Solid Cache, Solid Cable
- OpenAI API via `ruby-openai` for summarization/extraction
- Minitest for testing, RuboCop Rails Omakase for style

## Commands

| Task | Command |
|------|---------|
| Setup (install deps + prepare DB) | `bin/setup --skip-server` |
| Start dev server | `bin/dev` |
| Start background job worker | `bin/jobs` |
| Run full test suite | `bin/rails test` |
| Run single test file | `bin/rails test test/models/meeting_test.rb` |
| Run test by line number | `bin/rails test test/models/meeting_test.rb:42` |
| Run test by name pattern | `bin/rails test test/models/meeting_test.rb -n "/test_name/"` |
| Run test directory | `bin/rails test test/jobs` |
| Lint (RuboCop) | `bin/rubocop` |
| Full local CI (lint + security) | `bin/ci` |
| Security scan (Brakeman) | `bin/brakeman --no-pager` |
| Gem audit | `bin/bundler-audit` |
| Rails console | `bin/rails console` |
| Run migration | `bin/rails db:migrate` |
| Run job inline | `bin/rails runner "JobClass.perform_now(id)"` |
| Backfill topic descriptions | `bin/rails topics:generate_descriptions` |
| Seed category blocklist | `bin/rails topics:seed_category_blocklist` |
| Split a broad topic | `bin/rails topics:split_broad_topic[topic_name]` |
| Extract memberships from minutes | `bin/rails members:extract_from_minutes` |
| Merge members | `bin/rails members:merge[source_name,target_name]` |
| Auto-merge single-word members | `bin/rails members:cleanup` |
| List duplicate members | `bin/rails members:list_duplicates` |
| Validate prompt templates | `bin/rails prompt_templates:validate` |
| Backfill all meetings since 2025 | `bin/rails backfill:run` |
| Check backfill progress | `bin/rails backfill:status` |
| Backfill transcripts (date range) | `bin/rails "transcripts:backfill[2026-01-01,2026-04-09]"` |
| Import local SRT files | `bin/rails "transcripts:import[/path/to/srt/files]"` |

CI (`bin/ci` / `config/ci.rb`) runs: setup, rubocop, bundler-audit, importmap audit, brakeman. Note: CI does **not** run tests currently.

## Architecture

### Data Flow (Ingestion Pipeline)

```
City Website → Scraper Jobs (discover/parse meetings)
  → Document Download → PDF Text Extraction (+ OCR if image scan)
  → Topic Detection & Association (AI) ← runs on agenda parse AND minutes arrival
  → Topic Continuity Analysis (lifecycle derivation)
  → Summarization (topic-aware, with citations)
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
- **`TopicSummary` / `MeetingSummary`** — AI-generated summaries. Topic summaries use a two-pass architecture (structured analysis → editorial rendering). Meeting summaries use a single-pass architecture — `generation_data` stores structured JSON (headline, highlights, public_input, item_details) rendered directly by the view. Internal categories (factual record, institutional framing, civic sentiment) exist in `TopicSummary.generation_data` JSON but are synthesized into unified editorial prose for display. `MeetingSummary.summary_type` is one of: `minutes_recap`, `transcript_recap`, `packet_analysis`. `generation_data["source_type"]` tracks the source: `"minutes"`, `"transcript"`, or `"minutes_with_transcript"`.
- **`TopicBriefing`** — Rolling briefing per topic (one record, updated in place). Has `headline` (backward-looking, used for "What Happened" cards), `upcoming_headline` (forward-looking, used for "Coming Up" cards; nullable), `editorial_content`, `record_content`, and `generation_tier` (headline_only/interim/full). Both headline fields are generated by AI; `upcoming_headline` is null when no future meetings exist.
- **`PromptTemplate`** — Stores AI prompt text (system_role + instructions) with `{{placeholder}}` interpolation. 15 fixed templates (seeded), editable via admin UI. Auto-versions on save via `PromptVersion`.

### Key Services

- **`Ai::OpenAiService`** — All OpenAI calls centralized here. Handles summarization, topic extraction, vote extraction, triage, topic analysis, topic description generation. Two model constants: `DEFAULT_MODEL` (gpt-5.2, reasoning) and `LIGHTWEIGHT_MODEL` (gpt-5-mini, for cheap tasks like description generation). Note: `gpt-5-mini` does not support the `temperature` parameter. Key summary methods use a two-pass architecture: `analyze_topic_briefing` / `render_topic_briefing` (rolling briefings) and `analyze_topic_summary` / `render_topic_summary` (per-meeting snapshots). Prompts loaded from `PromptTemplate` (database); no hardcoded fallback — missing templates raise `RecordNotFound`.
- **`RetrievalService`** — RAG implementation using pgvector. Retrieves context chunks for AI prompts and admin knowledge search.
- **`VectorService`** — Low-level pgvector operations (embed, search).
- **`Topics::ContinuityService`** — Derives lifecycle status from agenda anchors and resolution signals.
- **`Topics::FindOrCreateService`** — Creates topics with blocklist/alias resolution.
- **`Topics::SummaryContextBuilder`** — Assembles topic context (KB + meeting data) for summarization.
- **`Topics::TriageTool`** — AI-assisted topic merging, approval, blocking.

### Job Namespaces

- `Scrapers::` — Meeting discovery, page/agenda parsing, transcript discovery (`DiscoverTranscriptsJob`)
- `Documents::` — Download, PDF analysis, OCR, transcript download (`DownloadTranscriptJob`)
- `Topics::` — Continuity updates, backfills, description generation (`GenerateDescriptionJob`, `RefreshDescriptionsJob`)
- Top-level: `ExtractTopicsJob` (runs on agenda parse AND minutes arrival; prefers minutes text over packet), `ExtractVotesJob`, `ExtractCommitteeMembersJob`, `SummarizeMeetingJob`, `IngestKnowledgeSourceJob`

### Routes

Public: `/ (home#index)`, `/meetings`, `/topics`, `/members` (all read-only index+show).
Admin: `/admin` namespace with dashboard, session/MFA auth, topic management (approve/block/merge/alias), committees (CRUD with alias management), knowledge sources, summaries, job monitoring, `/admin/prompt_templates` (edit AI prompts), `/admin/job_runs` (re-run pipeline jobs with targeting), `/admin/search` (knowledge search with RAG-powered Q&A).

### Topic Navigation Pattern

Topic cards (`topics/_topic_card` partial) are the primary navigation element to topic pages. The same partial is reused on the topics index (hero + list) and meeting show page ("Issues in This Meeting" section). Meeting show page splits topics into "Ongoing" (2+ appearances) and "New This Meeting" (1 appearance) subsections. Homepage meeting row topic pills are filtered to `resident_impact_score >= 2`.

### Homepage — Newspaper Layout (Apr 2026)

The homepage uses a newspaper-style inverted pyramid layout. Four zones, top to bottom:

1. **Top Stories (1-2 items)**: Highest-impact topics with recent activity. Full cards with topic name, description, briefing headline, meeting reference, "Meeting details →" button. Uses `_top_story.html.erb` partial.
2. **The Wire (4 cards + 6 rows)**: Next tier by impact. Mid-tier cards in 2-col grid (`_wire_card.html.erb`), compact rows below (`_wire_row.html.erb`). Cards link to meetings; rows link to topics.
3. **Next Up (1-2)**: Next council meeting and/or work session. Calendar-style date slabs with terra-cotta (council) or teal (work session) coloring. Uses `_next_up.html.erb`.
4. **Escape Hatches**: "Browse All Topics →" and "All Meetings →" buttons.

**Data flow**: `HomeController` builds `@top_stories` (impact ≥ 4, 30d window), `@wire_cards`/`@wire_rows` (impact ≥ 2, excludes top stories), `@next_up` (council/work session patterns), `@headlines` (from `TopicBriefing`), `@meeting_refs` (most recent meeting appearance per topic).

**Sort order**: Impact score descending, then recency. NOT chronological.

**CSS**: `app/assets/stylesheets/home.css` — homepage-specific styles. Three visual tiers with decreasing card weight. Atomic motifs (starburst, diamond dividers, atom markers). Explicit click affordances on all interactive elements.

**Known issue**: Top story and wire card links go to meeting pages, which may have thin content (no minutes/transcript). Plan to switch to topic page links once topic pages are improved (see #63, #76, #89).

**Design spec**: `docs/superpowers/specs/2026-04-10-homepage-redesign-design.md`

### Topic Show Page

The topic show page (`topics/show.html.erb`) uses a **fixed inverted-pyramid layout** — all sections always render, with empty state messages when data is absent. Section order: Header → What to Watch → Coming Up → The Story → Key Decisions → Record.

**Structured JSON rendering:** Briefing content renders from `TopicBriefing.generation_data` (pass 1 structured JSON) instead of pass 2 markdown. Helper methods in `TopicsHelper` extract fields: `briefing_what_to_watch`, `briefing_current_state`, `briefing_process_concerns`, `briefing_factual_record`, `format_record_date`. Markdown fields (`editorial_content`, `record_content`) are fallbacks for briefings without `generation_data`.

**Key CSS classes:** `.topic-watch` (What to Watch section), `.topic-watch-callout` (warm callout card), `.topic-story` (The Story section), `.topic-concerns-callout` (process concerns), `.topic-record` (Record section), `.topic-timeline` / `.topic-timeline-entry` (timeline layout), `.section-empty` (empty state text).

**Design doc:** `docs/plans/2026-03-01-topic-show-consistent-layout-design.md`

**Known issues (Apr 2026):**
- **Key Decisions empty for all topics** — `Motion.agenda_item_id` is always nil, so votes can't be traced to topics. Fix: #76 (link motions to agenda items in `ExtractVotesJob`).
- **Record entries are low-information** — most say "appeared on the agenda" instead of summarizing what happened. Fix: #89 (enrich Record entries with meeting content).
- **Record entries don't link to meetings** — committee names are plain text, not links. Fix: #89.
- **Coming Up empty most of the time** — agendas not published far in advance. No fallback like "typically discussed at [committee]."
- **Overall UX**: #63 tracks the full topic page overhaul needed to make it the primary homepage destination.

### Meeting Show Page

The meeting show page (`meetings/show.html.erb`) uses a **fixed inverted-pyramid layout** — all sections always render, with empty state messages when data is absent. Section order: Header → Headline → Highlights → Public Input → Agenda Items → Topics → Documents.

**Structured JSON rendering:** Meeting summary content renders from `MeetingSummary.generation_data` (single-pass structured JSON from `analyze_meeting_content`) instead of two-pass markdown. Helper methods in `MeetingsHelper` extract fields: `meeting_headline`, `meeting_highlights`, `meeting_public_input`, `meeting_item_details`, `decision_badge_class`. The `content` (markdown) field is a fallback for meetings without `generation_data`.

**Single-pass pipeline:** `SummarizeMeetingJob` calls `analyze_meeting_content` directly and stores the structured JSON in `generation_data`. The old two-pass flow (analyze → render markdown) is bypassed. The `render_meeting_summary` method remains for backward compatibility but is not called by the job.

**Key CSS classes:** `.meeting-headline`, `.meeting-highlights`, `.highlight-vote`, `.highlight-citation`, `.public-input-list`, `.public-input-item`, `.meeting-item-card` (agenda item cards), `.decision-badge` with `--passed`/`--failed`/`--tabled`/`--default` variants, `.meeting-legacy-recap` (markdown fallback), `.section-empty` (empty state text).

**Design doc:** `docs/plans/2026-03-01-meeting-show-redesign-design.md`

### YouTube Transcript Pipeline

Council meetings and work sessions are recorded and posted to YouTube (`@Two_Rivers_WI`). The transcript pipeline ingests auto-generated captions to produce same-day preliminary summaries, then enriches minutes-based summaries when official minutes arrive.

**Job chain:** `DiscoverMeetingsJob` (daily 11pm) → `DiscoverTranscriptsJob` → `DownloadTranscriptJob` → `SummarizeMeetingJob`

**`Scrapers::DiscoverTranscriptsJob`** — Queries for Council Meeting / Work Session meetings in the last 48 hours without a transcript document. Runs `yt-dlp --flat-playlist` to list channel videos, parses titles with `TITLE_PATTERN` regex to extract dates, matches to Meeting records. Channel URL and body names are constants on the class.

**`Documents::DownloadTranscriptJob`** — Takes `(meeting_id, video_url)`. Validates URL against `YOUTUBE_URL_PATTERN`, fetches SRT via `yt-dlp` in a temp directory, parses SRT to plain text (strips timestamps/sequence numbers), creates `MeetingDocument` with `document_type: "transcript"`, attaches raw SRT file. Enqueues `SummarizeMeetingJob` if no `minutes_recap` summary exists.

**Summarization priority:** `SummarizeMeetingJob` uses: minutes > transcript > packet. When minutes + transcript both exist, transcript text (truncated to 15K chars) is appended as supplementary context. Old `transcript_recap` summaries are cleaned up when minutes arrive.

**Transcript banner:** Meeting show page displays a cool-toned banner when `generation_data["source_type"] == "transcript"`. Automatically removed when minutes-based summary replaces it.

**Infrastructure:** `yt-dlp` standalone binary (`yt-dlp_linux`) installed in Dockerfile. No Python dependency. **Known issue:** YouTube rate-limits/bot-detects requests from datacenter IPs (see GitHub issue). Local `yt-dlp` works fine; production server gets blocked. Current workaround: download SRTs locally, import via `transcripts:import` rake task.

**Design doc:** `docs/superpowers/specs/2026-04-09-youtube-transcript-ingestion-design.md`

## Production Deployment

**Live at:** `https://tworiversmatters.com`

### Infrastructure

- **Host:** Hetzner VPS at `178.156.250.235` (Ubuntu 24.04, 4GB RAM, 3 CPUs)
- **Deploy tool:** Kamal 2, configured in `config/deploy.yml`
- **Container registry:** ghcr.io (`ghcr.io/andrerobitaille/two_rivers_reporter`)
- **SSH:** root access via `~/.ssh/andreg7-id_ed25519` (key-only, no password)
- **SSL:** Let's Encrypt via kamal-proxy, auto-renewed

### Services (all Docker containers on the same VPS)

| Container | Image | Purpose |
|-----------|-------|---------|
| `two_rivers_reporter-web` | App image | Rails + Puma + Thruster + Solid Queue (in-process) |
| `two_rivers_reporter-db` | `pgvector/pgvector:pg17` | PostgreSQL 17 with pgvector |
| `kamal-proxy` | `basecamp/kamal-proxy` | Reverse proxy, SSL termination, zero-downtime deploys |

### Databases (all in the Postgres container)

- `two_rivers_reporter_production` (primary, has pgvector extension)
- `two_rivers_reporter_production_cache` (Solid Cache)
- `two_rivers_reporter_production_queue` (Solid Queue)
- `two_rivers_reporter_production_cable` (Solid Cable)

### Secrets

- `RAILS_MASTER_KEY` — from `config/master.key` (gitignored), injected via `.kamal/secrets`
- `TWO_RIVERS_REPORTER_DATABASE_PASSWORD` — from `.env` (gitignored), shared between app and Postgres container
- `KAMAL_REGISTRY_PASSWORD` — from `gh auth token` (GitHub PAT with `write:packages` scope)

### Deploy Commands

| Task | Command |
|------|---------|
| Full deploy | `source .env && export TWO_RIVERS_REPORTER_DATABASE_PASSWORD && bin/kamal deploy` |
| First-time setup | `source .env && export TWO_RIVERS_REPORTER_DATABASE_PASSWORD && bin/kamal setup` |
| Rails console (prod) | `bin/kamal console` |
| Tail logs | `bin/kamal logs` |
| Shell into container | `bin/kamal shell` |
| DB console | `bin/kamal dbc` |
| Reboot app | `bin/kamal app boot` |
| Run a job | `bin/kamal app exec "bin/rails runner 'JobClass.perform_now(id)'"` |

Note: all `bin/kamal` commands require the env vars exported first (`source .env && export TWO_RIVERS_REPORTER_DATABASE_PASSWORD`).

### Recurring Jobs (Solid Queue, `config/recurring.yml`)

| Job | Schedule | Purpose |
|-----|----------|---------|
| `clear_solid_queue_finished_jobs` | Hourly at :12 | Prune completed job records |
| `refresh_topic_descriptions` | Mondays at 3am | Regenerate stale topic descriptions (90-day threshold) |

### Key Files

- `config/deploy.yml` — Kamal configuration (servers, registry, accessories, env)
- `.kamal/secrets` — Secret sourcing (shell expressions, not raw values)
- `.env` — Database password (gitignored, required for deploys)
- `config/postgres/init.sql` — Creates cache/queue/cable databases and pgvector extension
- `Dockerfile` — Production image (Ruby 4.0, poppler-utils, tesseract, yt-dlp, jemalloc)

## Conventions

- **Single Rails app** — No microservices, no SPA. Server-rendered HTML + background jobs.
- **Thin controllers** — Business logic in services and jobs, not controllers.
- **Jobs must be idempotent** — Safe to re-run; clear/rebuild derived rows when appropriate.
- **Member resolution uses `Member.resolve`** — Both extraction jobs (`ExtractCommitteeMembersJob`, `ExtractVotesJob`) use `Member.resolve(raw_name)` instead of direct `find_or_create_by!`. This centralizes name normalization, alias lookup, and auto-aliasing.
- **AI calls go through `Ai::OpenAiService`** — Don't scatter OpenAI API calls elsewhere. Committee context injected via `prepare_committee_context` (database-driven, not hardcoded).
- **Summaries require citations** — All factual claims must trace to document artifacts (e.g., `[Packet Page 12]`).
- **Separate fact from inference** — Topic summaries distinguish factual record, institutional framing, and civic sentiment.
- **Credentials** — Encrypted in `config/credentials.yml.enc`, decrypted via `config/master.key` (gitignored). Access via `Rails.application.credentials.<key>`.
- **Style** — RuboCop Rails Omakase (`.rubocop.yml`). No Sorbet. Prefer clarity over metaprogramming.
- **Topic granularity** — Category names (Zoning, Infrastructure, Finance, etc.) are blocked as topic names. Topics must name specific civic concerns at "neighborhood conversation" level. See `docs/plans/2026-02-28-broad-topic-prevention-design.md`. Use `topics:split_broad_topic[name]` to re-extract items from an overly-broad topic.
- **Documentation** — When adding features, update `docs/DEVELOPMENT_PLAN.md` (authoritative spec), this file (CLAUDE.md), and any relevant GitHub issues. Documentation must be useful to any developer, not just AI tools.
- **Design system** — All colors via CSS custom properties, never hardcoded hex. Two themes: `.theme-living-room` (public, warm cream) and `.theme-silo` (admin, cool concrete). Spec at `docs/plans/2026-03-28-atomic-design-system-spec.md`.
- **SVG motifs** — Reusable partials in `app/views/shared/` (`_atom_marker`, `_diamond_divider`, `_starburst`, `_boomerang`, `_radar_sweep`). Atom marker and diamond divider used in both themes; starburst/boomerang are Living Room only; radar sweep is Silo only.
- **Typography roles** — Outfit (display: headings, stats, nav labels, always uppercase), Space Grotesk (body: paragraphs, buttons, forms), DM Mono (data: metadata, timestamps, status chips, always uppercase with wide tracking).
