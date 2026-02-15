# AGENTS.md — TwoRiversReporter

This file is for agentic coding assistants operating in this repository.

## Source of Truth
- Product/architecture requirements: `docs/DEVELOPMENT_PLAN.md` (treat as binding).
- CI workflow: `.github/workflows/ci.yml` and `config/ci.rb`.
- No Cursor/Copilot rules found (`.cursor/rules/`, `.cursorrules`, `.github/copilot-instructions.md`).

---

## Build / Run / Lint / Test

### Setup
- Install dependencies + prepare DB: `bin/setup --skip-server`
- Start server: `bin/dev` (runs `bin/rails server`)
- Run background job worker (Solid Queue): `bin/jobs`

### CI (recommended “do everything” command)
- Run local CI steps (lint + security scans): `bin/ci`
  - Defined in `config/ci.rb` (runs `bin/setup --skip-server`, `bin/rubocop`, `bin/bundler-audit`, `bin/importmap audit`, `bin/brakeman`).

### Lint / Static Analysis
- Ruby style (RuboCop): `bin/rubocop`
  - Auto-correct (be cautious): `bin/rubocop -A`
- Security:
  - Brakeman: `bin/brakeman --no-pager` (CI uses stricter flags)
  - Bundler audit: `bin/bundler-audit`
  - Importmap audit: `bin/importmap audit`

### Tests
This is a Rails app using Minitest (no RSpec detected).

- Run full test suite: `bin/rails test`
- Run a single test file: `bin/rails test test/models/meeting_test.rb`
- Run a single test by line number: `bin/rails test test/models/meeting_test.rb:42`
- Run a single test by name (pattern): `bin/rails test test/models/meeting_test.rb -n "/test_the_thing/"`
- Run one test directory: `bin/rails test test/jobs`

### Common Workflows
- Run a single job inline:
  - `bin/rails runner "Documents::AnalyzePdfJob.perform_now(<document_id>)"`
  - `bin/rails runner "Documents::OcrJob.perform_now(<document_id>)"`
  - `bin/rails runner "SummarizeMeetingJob.perform_now(<meeting_id>)"`
  - `bin/rails runner "ExtractVotesJob.perform_now(<meeting_id>)"`
  - `bin/rails runner "ExtractTopicsJob.perform_now(<meeting_id>)"`
- Backfills should be done via idempotent jobs (clear/rebuild derived rows).

### Background Jobs (Solid Queue)
- Start worker: `bin/jobs`
- Inspect queue counts: `bin/rails runner "p SolidQueue::Job.count"`
- Prefer `perform_later` in app code; use `perform_now` for local debugging.

### Rails / DB
- Create + migrate DB: `bin/rails db:prepare`
- Run migrations: `bin/rails db:migrate`
- Reset DB (destructive): `bin/rails db:reset`
- Open console: `bin/rails console`
- One-off scripts: `bin/rails runner path/to/script.rb` or `bin/rails runner "..."`

### Assets / Build
- Precompile assets: `bin/rails assets:precompile`
- Build container image: `docker build -t two_rivers_reporter .`

---

## Codebase Conventions (Rails)

### Architecture
- Single Rails app; avoid new services/frameworks.
- Prefer server-rendered HTML; minimal JavaScript.
- Background work via ActiveJob + Solid Queue; do not do heavy work in controllers.
- Keep controllers thin; put pipeline logic in jobs/services.

### Common Domain Concepts
- `Meeting` has many `MeetingDocument`, `AgendaItem`, summaries, motions.
- Documents are authoritative; AI output must never replace PDFs.
- Prefer progressive enrichment (download → extract → summarize → analyze).

### Background Jobs
- Jobs should be idempotent:
  - Safe to re-run without duplicating rows.
  - Clear/rebuild derived tables where appropriate (e.g., `destroy_all` then recreate).
- Always log clearly (`Rails.logger.info/warn/error`).
- Use status fields for long-running pipelines when available (e.g., OCR status).
- Avoid raising unhandled exceptions in jobs; mark record state as failed when possible.

### OCR / Extraction Pipeline
- `Documents::AnalyzePdfJob` extracts text and computes `text_quality`.
- For `text_quality == "image_scan"`, OCR is queued (`Documents::OcrJob`).
- `Extraction` rows store page-aware text; keep page numbers stable.

### AI Usage
- Use `Ai::OpenAiService` for OpenAI calls; do not scatter API calls across the codebase.
- Prompts should:
  - Be explicit about output format (use JSON mode when parsing).
  - Require citations for summaries when page-aware text is available.
  - Prefer “I don’t know / not in document” to invention.
- Always label AI-generated content in UI.

### Data & Retrieval
- Knowledgebase ingestion lives in `KnowledgeSource`/`KnowledgeChunk` + `IngestKnowledgeSourceJob`.
- Retrieval behavior is centralized in `RetrievalService` and `VectorService`.
- Keep retrieval caps/thresholds explicit and documented.

---

## Style Guidelines

### Ruby Style
- Follow RuboCop Rails Omakase (`.rubocop.yml`).
- Prefer small, readable methods over clever metaprogramming.
- Prefer `bin/rubocop` to ensure consistent config.
- No static typing framework (no Sorbet); avoid adding one.

### Naming
- Use conventional Rails names and namespaces:
  - Jobs: `Documents::...`, `Scrapers::...`, etc.
  - Models are singular (`MeetingDocument`, `AgendaItemTopic`).
- Avoid ambiguous abbreviations; prefer clarity (e.g., `meeting_document`, not `md`).

### Imports / Requires
- Rails autoloading should handle most constants.
- If you must `require`, prefer `require "uri"` at top of the file (as done in scrapers).

### Database / Models
- Prefer real DB constraints + validations for invariants:
  - Add indexes for uniqueness where needed.
  - Use `belongs_to` + `has_many` with appropriate `dependent:`.
- Prefer `find_or_create_by!` for reference data (e.g., `Member`, `Topic`).

### Error Handling
- Handle external command failures explicitly:
  - Check exit status for system calls.
  - Record failure status on affected model (`text_quality`, `ocr_status`, etc.).
- Avoid swallowing errors silently; log with enough context (IDs, URLs).

### Formatting / Rendering
- Keep views simple and data-prepared in controllers/jobs.
- When rendering Markdown, keep output labeled as AI and encourage verification.
- Reuse existing CSS classes/components before adding new ones.

---

## Security / Secrets
- Do not commit `config/master.key` (it is gitignored) or any `.env` files.
- Credentials live in `config/credentials.yml.enc` and are decrypted via `RAILS_MASTER_KEY`.
- Never print secrets in logs or console output.

---

## Deployment Notes (Fly.io / Docker)
- The `Dockerfile` installs `poppler-utils` and `tesseract-ocr` for PDF extraction/OCR.
- If deploying via buildpacks instead of Docker, ensure equivalent OS packages are installed.
