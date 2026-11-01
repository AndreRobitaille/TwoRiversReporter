# Two Rivers Reporter

Civic transparency site for Two Rivers, WI. Ingests official city meeting documents (PDFs, HTML), preserves them as authoritative records, and produces citation-backed AI summaries for residents.

**Topics** (persistent civic concerns like "Downtown TIF District" or "Lead Service Line Replacement") are the primary organizing structure; meetings are inputs.

## What It Does

- Scrapes and archives official city meeting documents (agendas, packets, minutes)
- Extracts topics, motions, votes, and attendance from meeting records, then
  reconciles current committee membership against stronger official and
  organization-published rosters where available
- Generates AI summaries with citations back to source documents
- Presents everything in a resident-friendly interface organized around civic topics

## Design System

The site uses an **Atomic-era design system** inspired by 1950s-60s post-war optimism — Lustron houses, Formica countertops, Franciscan dinnerware, Googie architecture. The aesthetic conveys warmth and hope, wrapping civic watchdog tooling in the visual language of a mid-century living room.

### Two Themes

- **Living Room** (public pages) — warm cream backgrounds, terra cotta accents, full decorative vocabulary (starbursts, boomerangs, orbital rings). Tone: "Come sit down, here's what happened at city hall."
- **Silo** (admin pages) — cool concrete backgrounds, deep teal dominance, minimal decoration (atom markers, radar sweeps). The Titan missile silo aesthetic — serious infrastructure underneath the community.

### Typography

| Role | Font | Usage |
|------|------|-------|
| **Display** | [Outfit](https://fonts.google.com/specimen/Outfit) | Headings, stats, nav labels. Always uppercase, tight tracking. |
| **Body** | [Space Grotesk](https://fonts.google.com/specimen/Space+Grotesk) | Paragraphs, buttons, forms. Readable at all sizes. |
| **Data** | [DM Mono](https://fonts.google.com/specimen/DM+Mono) | Metadata, timestamps, status chips. Uppercase, wide tracking. |

### Color Palette

| Color | Hex | Role |
|-------|-----|------|
| Deep Teal | `#004a59` | Primary headings, links, nav chrome |
| Terra Cotta | `#c2522a` | Accent, action, section labels |
| Amber | `#d4872a` | Warnings, active states |
| Forest Green | `#2a7a4a` | Success states |
| Brick Red | `#9e2a2a` | Danger, errors |

Full spec with SVG motif path data, component patterns, spacing scale, and CSS architecture: **[`docs/plans/2026-03-28-atomic-design-system-spec.md`](docs/plans/2026-03-28-atomic-design-system-spec.md)**

## Tech Stack

- **Ruby on Rails 8.1** — server-rendered HTML, Turbo/Stimulus, ImportMap, Propshaft
- **PostgreSQL** with pgvector for embeddings
- **Solid Queue** for background jobs, **Solid Cache**, **Solid Cable**
- **OpenAI API** via `ruby-openai` for summarization and topic extraction
- **Plain CSS** with custom properties (no preprocessor) — single `application.css` file
- **Google Fonts** — Outfit, Space Grotesk, DM Mono

## Key Documents

| Document | Purpose |
|----------|---------|
| [`CLAUDE.md`](CLAUDE.md) | AI coding agent instructions — architecture, conventions, commands |
| [`docs/DEVELOPMENT_PLAN.md`](docs/DEVELOPMENT_PLAN.md) | Authoritative product spec and architectural constraints |
| [`docs/application-map/README.md`](docs/application-map/README.md) | Application inventory, intended workflows, state transitions, and independent QA reference |
| [`docs/SHARED_HOST_DEPLOYMENT.md`](docs/SHARED_HOST_DEPLOYMENT.md) | Common build, publication, SSH session and release workflow for the three Hetzner apps |
| [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) | Two Rivers deployment prerequisites, commands, automatic checks and operator duties |
| [`docs/superpowers/specs/2026-09-03-canonical-committee-rosters-design.md`](docs/superpowers/specs/2026-09-03-canonical-committee-rosters-design.md) | Committee roster authority, source precedence, and repair operations |
| [`docs/plans/2026-03-28-atomic-design-system-spec.md`](docs/plans/2026-03-28-atomic-design-system-spec.md) | Visual design system — colors, typography, motifs, components |
| [`docs/topics/TOPIC_GOVERNANCE.md`](docs/topics/TOPIC_GOVERNANCE.md) | Topic extraction, classification, and lifecycle rules |

## Getting Started

Configure local gem storage in each clone/worktree before running setup:

```bash
bundle config set --local path "$HOME/.local/share/bundle/tworiversreporter"
bundle check || bundle install --jobs 1
bin/setup --skip-server   # Install deps + prepare DB
bin/dev -b 0.0.0.0        # Start dev server on the remotely accessed workstation
bin/jobs                  # Start background job worker (separate terminal)
```

### Local Ruby gems

On Andre's workstation, installed gems live at
`/home/andre/.local/share/bundle/tworiversreporter` (Ruby-specific subdirectories
are managed by Bundler). Use the Ruby version in `.ruby-version`. This permanent,
application-specific store is shared by the application's local checkouts.

`bundle config set --local` records the path in the checkout's `.bundle/config`.
That file is deliberately ignored by Git, so repeat the configuration command
in every new clone or worktree. Normal `bundle`, `bin/rails`, `bin/dev`, and
`bin/jobs` commands then use the external store without an environment override.
Check the effective setting with `bundle config get path`; use `bundle config list`
to inspect conflicting settings rather than assuming `BUNDLE_PATH` overrides an
existing local configuration.

The former `vendor/bundle/` installation was removed on November 1, 2026 after
the current locked dependencies were installed externally and development boot,
eager loading, and the local database connection were verified. Keep these rules:

- Do not recreate `vendor/bundle/` or configure local development with
  `path vendor/bundle` or Bundler deployment mode.
- Keep persistent development dependencies outside `/tmp`; temporary test/review
  bundles from earlier tasks are not the workstation's dependency installation.
- Preserve the external store during checkout cleanup. Deleting it, or pruning
  its gems, can break another local checkout using different locked versions.
- Preserve the tracked `vendor/fonts/` assets used by the application.
- When the lockfile changes or gems are missing, run `bundle install --jobs 1`
  against the checked-in `Gemfile.lock`. Do not update dependency versions merely
  to repair a local installation.

After changing the bundle path, verify it and boot Rails against the local
development database before removing an old installation. Confirm that inherited
database URLs do not point at production; this check only reads the local database:

```bash
bundle config get path
bundle check
bin/rails runner -e development - <<'RUBY'
abort "Unexpected database" unless ActiveRecord::Base.connection_db_config.database == "two_rivers_reporter_development"
Rails.application.eager_load!
puts "Rails development boot: #{Rails.version}"
puts "Local database SELECT 1: #{ActiveRecord::Base.connection.select_value('SELECT 1')}"
RUBY
```

In the agent sandbox, Bundler can warn that `/home/andre` is not writable and
fall back to a temporary home directory. Verify the effective gem path and boot
checks above; that warning alone is not a reason to relocate the installed gems.

CI and production images use their own dependency installation settings. This
workstation path belongs in the ignored local configuration, not in `Gemfile`,
`Gemfile.lock`, or the Docker deployment configuration.

## Non-Goals

- No SPA — server-rendered HTML everywhere
- No microservices
- No commenting system
- No automatic self-registration — member applications require admin approval

## License

TBD
