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

### Loops Transactional Templates (BLOCKING pre-deploy checklist)

Every transactional email is a template created in the Loops dashboard. The app
reads each template's id from an env var and **fails closed in production**: a
missing id raises `TransactionalEmail::MissingTransactionalId`, which is not
rescued by the controllers. A missing id therefore takes down the flow that
sends it. Set all of these in the Kamal env (`config/deploy.yml`) before deploy.

| Env var | Loops template | Sent when | Status |
|---------|----------------|-----------|--------|
| `LOOPS_API_KEY` | — | All delivery | Live |
| `LOOPS_MAGIC_LINK_TRANSACTIONAL_ID` | Sign-in magic link | Active member requests sign-in; application approved | Live |
| `LOOPS_APPLICATION_LINK_TRANSACTIONAL_ID` | Application magic link | Applicant resumes their application | Live |
| `LOOPS_ADMIN_APPLICATION_NOTIFICATION_TRANSACTIONAL_ID` | Admin application digest | Pending applications need review | Live |
| `LOOPS_NO_ACCOUNT_TRANSACTIONAL_ID` | No account | Sign-in requested for an address with no account | **Must be created** |
| `LOOPS_APPLICATION_PENDING_TRANSACTIONAL_ID` | Application pending | Sign-in requested by an applicant still under review | **Must be created** |

**The last two templates do not exist in Loops yet.** They are required by the
"always answer sign-in attempts by email" change: `SessionsController#create`
now emails a definitive answer on every branch, so two of the three branches
call templates that must exist before this ships. If either id is unset in
production, every sign-in attempt for an unknown or pending address raises and
returns a 500 — which both breaks sign-in and reintroduces the address
enumeration leak the change exists to close.

Pre-deploy checklist for these two:

1. Create both templates in the Loops dashboard.
2. Copy their transactional ids into the Kamal env as
   `LOOPS_NO_ACCOUNT_TRANSACTIONAL_ID` and
   `LOOPS_APPLICATION_PENDING_TRANSACTIONAL_ID`.
3. Deploy.
4. Smoke-test all three sign-in branches (unknown address, pending applicant,
   active member) against production and confirm each receives its email.

Content guidance for whoever writes the templates. No emoji — standing project
rule for all user-facing copy.

- **No account** (data variable: `apply_url`) — "Someone asked for a sign-in
  link for this address. There's no account here. If that was you, here's how to
  request one: `{{apply_url}}`."
- **Application pending** (no data variables) — "Your application is still under
  review. We'll email you as soon as it's decided."

Outside production these ids fall back to literal defaults (`no_account`,
`application_pending`, `sign_in_magic_link`, ...) and `Message#deliver_now` is a
no-op, so local and test runs never hit Loops.

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
