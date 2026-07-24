---
name: deploying
description: Use when deploying TwoRiversReporter to production, running commands against the live server, or shipping prompt-template changes. Covers Kamal 2 deploy commands, the Hetzner/Docker/pgvector infrastructure, secrets sourcing, recurring jobs, and the mandatory deploy-before-populate ordering for prompt templates.
---

# Production Deployment

**Live at:** `https://tworiversmatters.com`

## Deploy Commands

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

**Gotcha:** all `bin/kamal` commands require the env vars exported first (`source .env && export TWO_RIVERS_REPORTER_DATABASE_PASSWORD`). `.env` keys are not auto-exported to Kamal; prefer `env: clear:` in `deploy.yml` for non-secrets.

## Prompt Template Deploy Ordering

After editing `lib/prompt_template_data.rb`, production ordering matters:

1. Validate locally with `bin/rubocop` and `bin/rails prompt_templates:validate`
2. Update the local DB with `bin/rails prompt_templates:populate` if needed
3. Commit and push
4. Run `bin/kamal deploy`
5. Then run `bin/kamal app exec "bin/rails prompt_templates:populate"`

`prompt_templates:populate` on prod reads from the running image, not your local filesystem. If you skip deploy, you can repopulate the database from stale code.

The same ordering applies before regenerating generated civic images in production — deploy, then populate, then regenerate.

## Infrastructure

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

`config/master.key` is gitignored, so git worktrees don't get it. Symlink it:
`ln -s /home/andre/Development/TwoRiversReporter/config/master.key config/master.key`

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
- `app/views/og/default.html.erb` + `lib/tasks/og.rake` + `public/og-image.png` + `vendor/fonts/Outfit-Black.ttf` — social preview image. Edit the ERB, then run `bin/rails og:generate` to regenerate the PNG. Commit both.

**Not yet automated:** database backups. High priority.
