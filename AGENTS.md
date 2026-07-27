# AGENTS.md — TwoRiversReporter

This file is the compact entrypoint for coding agents working in this repository.

## Source of Truth / Precedence
- Product and architecture requirements: `docs/DEVELOPMENT_PLAN.md`
- Topic extraction, governance, and lifecycle rules: `docs/topics/TOPIC_GOVERNANCE.md`
- UI/styling/design-system rules: `docs/plans/2026-03-28-atomic-design-system-spec.md`
- Detailed project handbook: `CLAUDE.md`
- Production playbook: `.claude/skills/deploying/SKILL.md`
- Page and transcript-pipeline playbook: `.claude/skills/page-architecture/SKILL.md`

If guidance overlaps, follow the more specialized document.

The `.claude/skills/` files are shared repository playbooks despite their
tool-specific directory name. Non-Claude agents should read them directly
rather than duplicating them into another agent directory.

## Before Changing X, Read Y
- Topic extraction / triage / summaries / lifecycle → `docs/topics/TOPIC_GOVERNANCE.md`
- UI, CSS, components, themes → `docs/plans/2026-03-28-atomic-design-system-spec.md`
- Meeting/topic behavior or recent feature details → relevant spec in `docs/superpowers/specs/`
- Prompt template or AI pipeline work → `CLAUDE.md`, `.claude/skills/deploying/SKILL.md`
- Homepage / topic show / meeting show / transcript pipeline → `.claude/skills/page-architecture/SKILL.md`
- Sign-in, membership, admin access, or transactional email → `docs/superpowers/specs/2026-07-23-passwordless-auth-and-applications-design.md`
- Session lifetime, persistent sessions, context matching, or step-up reauthentication → `docs/superpowers/specs/2026-07-25-session-and-reauthentication-hardening-design.md`
- Anonymous/public access behavior → `docs/superpowers/specs/2026-07-24-tiered-public-access-design.md`
- Deploy / production operations → `.claude/skills/deploying/SKILL.md`, `config/deploy.yml`
- Admin navigation, admin styling, or any `/admin` page → `docs/superpowers/specs/2026-07-26-admin-ui-revamp-design.md`

## Core Commands
- Setup: `bin/setup --skip-server`
- Dev server: `bin/dev`
- Jobs: `bin/jobs`
- Tests: `bin/rails test`
- Lint: `bin/rubocop`
- Local CI: `bin/ci`

CI note: `bin/ci` currently runs setup, RuboCop, bundler-audit, importmap audit, and Brakeman; it does **not** run tests.

## Verification Rules
- Ruby/model/job/service changes: run targeted Minitest files and `bin/rubocop`.
- Multi-stage AI/data changes: compare counts and distinctive content at every major upstream → downstream boundary; polished final output is not proof that data survived.
- Absence/gating tests: first prove the content is present for an allowed user, then remove the guard and confirm the test fails. Test quantity and identity caps separately from canary-text sweeps.
- Ruby syntax-only checks use `ruby -c path.rb`; never use `load` for syntax checking because it executes the file.
- After `bin/rails db:migrate`, run `bin/rubocop -A db/schema.rb` and inspect its diff so schema formatting noise does not hide the real migration.
- Before claiming completion, state which commands and checks actually ran.

## Repo Rules
- Single Rails app; avoid introducing new services/frameworks.
- Prefer server-rendered HTML; use minimal JavaScript.
- Keep controllers thin; put business/pipeline logic in jobs and services.
- Jobs must be idempotent and safe to re-run.
- AI calls go through `Ai::OpenAiService`.
- Official documents remain authoritative; AI output must not replace source records.
- Gated mode protects generated analysis and aggregation, not the authority or public nature of official records. Withheld content must never be rendered into HTML, metadata, attributes, or alternate response formats.
- Prompt JSON arrays must state explicit cardinality; schema shape alone does not prevent the model from collapsing distinct events. Scope editorial voice to named fields and keep evidence-bearing fields neutral.
- After two rounds of phrase-level prompt fixes for the same failure mode, investigate upstream data, topic governance, or prompt structure instead of extending a banned-phrase list.
- Production prompt-template changes must be deployed before running production `prompt_templates:populate`; the task reads from the running image.
- Do not use emoji in user-facing copy.

## Local Development Gotchas
- Bind servers to `0.0.0.0` because the development machine is accessed remotely. Browser automation that exercises passkeys must use a `localhost` origin because WebAuthn requires a secure context.
- Generated-image blobs are absent in local development. Broken local thumbnails are expected; do not treat them as an image-loading regression.

## More Detail
For architecture, domain models, deployment notes, and workflow caveats, read `CLAUDE.md`.
