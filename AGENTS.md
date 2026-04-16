# AGENTS.md — TwoRiversReporter

This file is the compact entrypoint for coding agents working in this repository.

## Source of Truth / Precedence
- Product and architecture requirements: `docs/DEVELOPMENT_PLAN.md`
- Topic extraction, governance, and lifecycle rules: `docs/topics/TOPIC_GOVERNANCE.md`
- UI/styling/design-system rules: `docs/plans/2026-03-28-atomic-design-system-spec.md`
- Detailed project handbook: `CLAUDE.md`

If guidance overlaps, follow the more specialized document.

## Before Changing X, Read Y
- Topic extraction / triage / summaries / lifecycle → `docs/topics/TOPIC_GOVERNANCE.md`
- UI, CSS, components, themes → `docs/plans/2026-03-28-atomic-design-system-spec.md`
- Meeting/topic behavior or recent feature details → relevant spec in `docs/superpowers/specs/`
- Prompt template or AI pipeline work → `CLAUDE.md`
- Deploy / production operations → `CLAUDE.md`, `config/deploy.yml`

## Core Commands
- Setup: `bin/setup --skip-server`
- Dev server: `bin/dev`
- Jobs: `bin/jobs`
- Tests: `bin/rails test`
- Lint: `bin/rubocop`
- Local CI: `bin/ci`

CI note: `bin/ci` currently runs setup, RuboCop, bundler-audit, importmap audit, and Brakeman; it does **not** run tests.

## Repo Rules
- Single Rails app; avoid introducing new services/frameworks.
- Prefer server-rendered HTML; use minimal JavaScript.
- Keep controllers thin; put business/pipeline logic in jobs and services.
- Jobs must be idempotent and safe to re-run.
- AI calls go through `Ai::OpenAiService`.
- Official documents remain authoritative; AI output must not replace source records.

## More Detail
For architecture, domain models, deployment notes, and workflow caveats, read `CLAUDE.md`.
