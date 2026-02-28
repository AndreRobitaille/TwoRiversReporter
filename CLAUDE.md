# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Civic transparency site for Two Rivers, WI. Ingests official city meeting documents (PDFs, HTML), preserves them as authoritative records, and produces citation-backed AI summaries for residents. **Topics** (persistent civic concerns) are the primary organizing structure; meetings are inputs.

## Binding Documents

- **`docs/DEVELOPMENT_PLAN.md`** — Authoritative product spec and architectural constraints. Treat as binding.
- **`docs/topics/TOPIC_GOVERNANCE.md`** — Non-negotiable rules for all topic extraction, classification, summarization, and lifecycle logic. Read before any topic-related work.

## Tech Stack

- Rails 8.1, Ruby 4.0, PostgreSQL (with pgvector for embeddings)
- Server-rendered HTML, Turbo/Stimulus, ImportMap, Propshaft
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

CI (`bin/ci` / `config/ci.rb`) runs: setup, rubocop, bundler-audit, importmap audit, brakeman. Note: CI does **not** run tests currently.

## Architecture

### Data Flow (Ingestion Pipeline)

```
City Website → Scraper Jobs (discover/parse meetings)
  → Document Download → PDF Text Extraction (+ OCR if image scan)
  → Topic Detection & Association (AI)
  → Topic Continuity Analysis (lifecycle derivation)
  → Summarization (topic-aware, with citations)
  → Resident-Facing Pages
```

### Core Domain Models

- **`Topic`** — Central organizing model. Has `status` (approved/proposed/blocked), `review_status`, `lifecycle_status` (active/dormant/resolved/recurring). Linked to meetings via `AgendaItemTopic`. Has aliases, blocklist entries, appearances, status events, summaries.
- **`Committee`** — Governing body (city board, tax-funded nonprofit, or external). Has `committee_type`, `status` (active/dormant/dissolved), `description` (injected into AI prompts). Linked to meetings via FK, members via `CommitteeMembership`, and historical names via `CommitteeAlias`. Normalizes the free-form `body_name` string.
- **`Meeting`** — Single official meeting. Has documents, agenda items, motions, summaries. `belongs_to :committee` (optional); keeps `body_name` as historical display text.
- **`MeetingDocument`** — PDF/HTML artifact. Has `extracted_text`, `text_quality`, `ocr_status`. Page-level text stored in `Extraction` rows.
- **`AgendaItem`** — Item on agenda. Links to topics via `AgendaItemTopic`. Has motions and votes.
- **`KnowledgeSource` / `KnowledgeChunk`** — Admin-maintained context for RAG. Chunks have vector embeddings.
- **`TopicSummary` / `MeetingSummary`** — AI-generated summaries. Topic summaries use a two-pass architecture (structured analysis → editorial rendering). Internal categories (factual record, institutional framing, civic sentiment) exist in `generation_data` JSON but are synthesized into unified editorial prose for display.
- **`TopicBriefing`** — Rolling briefing per topic (one record, updated in place). Has `headline`, `editorial_content`, `record_content`, and `generation_tier` (headline_only/interim/full).

### Key Services

- **`Ai::OpenAiService`** — All OpenAI calls centralized here. Handles summarization, topic extraction, vote extraction, triage, topic analysis, topic description generation. Two model constants: `DEFAULT_MODEL` (gpt-5.2, reasoning) and `LIGHTWEIGHT_MODEL` (gpt-5-mini, for cheap tasks like description generation). Note: `gpt-5-mini` does not support the `temperature` parameter. Key summary methods use a two-pass architecture: `analyze_topic_briefing` / `render_topic_briefing` (rolling briefings) and `analyze_topic_summary` / `render_topic_summary` (per-meeting snapshots).
- **`RetrievalService`** — RAG implementation using pgvector. Retrieves context chunks for AI prompts.
- **`VectorService`** — Low-level pgvector operations (embed, search).
- **`Topics::ContinuityService`** — Derives lifecycle status from agenda anchors and resolution signals.
- **`Topics::FindOrCreateService`** — Creates topics with blocklist/alias resolution.
- **`Topics::SummaryContextBuilder`** — Assembles topic context (KB + meeting data) for summarization.
- **`Topics::TriageTool`** — AI-assisted topic merging, approval, blocking.

### Job Namespaces

- `Scrapers::` — Meeting discovery and page/agenda parsing
- `Documents::` — Download, PDF analysis, OCR
- `Topics::` — Continuity updates, backfills, description generation (`GenerateDescriptionJob`, `RefreshDescriptionsJob`)
- Top-level: `ExtractTopicsJob`, `ExtractVotesJob`, `SummarizeMeetingJob`, `IngestKnowledgeSourceJob`

### Routes

Public: `/ (home#index)`, `/meetings`, `/topics`, `/members` (all read-only index+show).
Admin: `/admin` namespace with dashboard, session/MFA auth, topic management (approve/block/merge/alias), committees (CRUD with alias management), knowledge sources, summaries, job monitoring.

### Topic Navigation Pattern

Topic cards (`topics/_topic_card` partial) are the primary navigation element to topic pages. The same partial is reused on the homepage ("Coming Up", "What Happened"), topics index (hero + list), and meeting show page ("Issues in This Meeting" section). Meeting show page splits topics into "Ongoing" (2+ appearances) and "New This Meeting" (1 appearance) subsections. Homepage meeting row topic pills are filtered to `resident_impact_score >= 2`.

## Conventions

- **Single Rails app** — No microservices, no SPA. Server-rendered HTML + background jobs.
- **Thin controllers** — Business logic in services and jobs, not controllers.
- **Jobs must be idempotent** — Safe to re-run; clear/rebuild derived rows when appropriate.
- **AI calls go through `Ai::OpenAiService`** — Don't scatter OpenAI API calls elsewhere. Committee context injected via `prepare_committee_context` (database-driven, not hardcoded).
- **Summaries require citations** — All factual claims must trace to document artifacts (e.g., `[Packet Page 12]`).
- **Separate fact from inference** — Topic summaries distinguish factual record, institutional framing, and civic sentiment.
- **Credentials** — Encrypted in `config/credentials.yml.enc`, decrypted via `config/master.key` (gitignored). Access via `Rails.application.credentials.<key>`.
- **Style** — RuboCop Rails Omakase (`.rubocop.yml`). No Sorbet. Prefer clarity over metaprogramming.
- **Topic granularity** — Category names (Zoning, Infrastructure, Finance, etc.) are blocked as topic names. Topics must name specific civic concerns at "neighborhood conversation" level. See `docs/plans/2026-02-28-broad-topic-prevention-design.md`. Use `topics:split_broad_topic[name]` to re-extract items from an overly-broad topic.
- **Documentation** — When adding features, update `docs/DEVELOPMENT_PLAN.md` (authoritative spec), this file (CLAUDE.md), and any relevant GitHub issues. Documentation must be useful to any developer, not just AI tools.
