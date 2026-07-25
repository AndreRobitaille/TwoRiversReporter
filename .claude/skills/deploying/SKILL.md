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
- `LOOPS_API_KEY` — **not defined yet**; required by the first passwordless-auth
  deploy. See the checklist below.

`config/master.key` is gitignored, so git worktrees don't get it. Symlink it:
`ln -s /home/andre/Development/TwoRiversReporter/config/master.key config/master.key`

### Passwordless Auth Environment (BLOCKING pre-deploy checklist)

**Passwordless auth has never been deployed.** Nothing in this section is set in
production today — the deploy config on `master` contains no `LOOPS_*`,
`WEBAUTHN_*`, or `ADMIN_NOTIFICATION_EMAIL` entry, and `.kamal/secrets` defines
only `RAILS_MASTER_KEY`, `KAMAL_REGISTRY_PASSWORD`,
`TWO_RIVERS_REPORTER_DATABASE_PASSWORD`, and `POSTGRES_PASSWORD`. Read the
`Kamal env` column below as the state of the deploy config, not the state of the
Loops dashboard; the two columns are independent and both must be satisfied.

Every transactional email is a template created in the Loops dashboard. The app
reads each template's id from an env var and **fails closed in production**: a
missing id raises `TransactionalEmail::MissingTransactionalId`, which is not
rescued by the controllers. A missing id therefore takes down the flow that
sends it.

| Env var | Loops template | Sent when | Kamal env |
|---------|----------------|-----------|-----------|
| `LOOPS_API_KEY` | — | All delivery | **Not set** |
| `LOOPS_MAGIC_LINK_TRANSACTIONAL_ID` | Exists | Active member requests sign-in; application approved | **Not set** |
| `LOOPS_APPLICATION_LINK_TRANSACTIONAL_ID` | Exists | Applicant resumes their application | **Not set** |
| `LOOPS_ADMIN_APPLICATION_NOTIFICATION_TRANSACTIONAL_ID` | Exists | Pending applications need review | **Not set** |
| `LOOPS_NO_ACCOUNT_TRANSACTIONAL_ID` | **Must be created** | Sign-in requested for an address with no account | **Not set** |
| `LOOPS_APPLICATION_PENDING_TRANSACTIONAL_ID` | **Must be created** | Sign-in requested by an applicant still under review | **Not set** |
| `WEBAUTHN_ORIGIN` | — | Passkey registration and authentication | **Not set** |
| `WEBAUTHN_RP_ID` | — | Passkey registration and authentication | **Not set** |
| `WEBAUTHN_RP_NAME` | — | Passkey registration and authentication | **Not set** |
| `ADMIN_NOTIFICATION_EMAIL` | — | Recipient of the admin application digest | **Not set** |

**The last two Loops templates do not exist in the dashboard yet.** They are
required by the "always answer sign-in attempts by email" change:
`SessionsController#create` now emails a definitive answer on every branch, so
two of the three branches call templates that must exist before this ships. If
either id is unset in production, every sign-in attempt for an unknown or
pending address raises and returns a 500 — which both breaks sign-in and
reintroduces the address enumeration leak the change exists to close.

Pre-deploy checklist:

0. **Confirm the starting state.** `command grep -c LOOPS_ config/deploy.yml`
   returns `0` today. If it still returns `0` when you deploy, the boot guard
   below will refuse the container and Kamal will roll the deploy back.
1. Create the two missing templates in the Loops dashboard (content guidance
   below).
2. **Set all ten vars in the deploy config.** None of them exist there today.
   - The five transactional ids go in `config/deploy.yml` under `env: clear:` —
     they are template identifiers, not credentials:
     `LOOPS_MAGIC_LINK_TRANSACTIONAL_ID`,
     `LOOPS_APPLICATION_LINK_TRANSACTIONAL_ID`,
     `LOOPS_ADMIN_APPLICATION_NOTIFICATION_TRANSACTIONAL_ID`,
     `LOOPS_NO_ACCOUNT_TRANSACTIONAL_ID`,
     `LOOPS_APPLICATION_PENDING_TRANSACTIONAL_ID`.
   - `LOOPS_API_KEY` is a credential: add it to `.kamal/secrets` **and** list it
     under `env: secret:` in `config/deploy.yml`. Kamal needs both — a name in
     `.kamal/secrets` that is not listed in `env: secret:` is never injected.
   - `WEBAUTHN_ORIGIN` (`https://tworiversmatters.com`), `WEBAUTHN_RP_ID`
     (`tworiversmatters.com`), and `WEBAUTHN_RP_NAME` go in `env: clear:`.
     These have development defaults (`http://localhost:3000` / `localhost`),
     so leaving them unset does **not** fail the deploy — it silently ships a
     production site where no passkey can ever be registered or used.
   - `ADMIN_NOTIFICATION_EMAIL` goes in `env: clear:`.
3. Deploy.
4. **Smoke-test all three sign-in branches** (unknown address, pending
   applicant, active member) against production and confirm each receives its
   email — then register and use a passkey. This step is not optional: the boot
   guard checks that the ids are *present*, never that they are *correct*. A
   transposed or stale transactional id boots a perfectly healthy container that
   sends nothing, or sends the wrong template, on the branch you typo'd. The
   smoke test is the only thing that catches that.

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

**Enforced at boot.** `config/initializers/verify_transactional_email_ids.rb`
calls `TransactionalEmail.verify_transactional_ids!`, which reads all five ids
when `Rails.env.production?`. A missing var raises `MissingTransactionalId`
during boot, the container never becomes healthy, and Kamal rolls the deploy
back — so a forgotten id costs you a failed deploy instead of a broken sign-in
form. If a deploy fails with `LOOPS_..._TRANSACTIONAL_ID is required in
production` in `bin/kamal logs`, that is this guard: set the var and redeploy.
The guard is skipped when `SECRET_KEY_BASE_DUMMY` is set, so the Docker build's
`assets:precompile` step is unaffected.

**What the boot guard does *not* cover.** `TRANSACTIONAL_ID_READERS` lists the
five transactional ids and nothing else. Three vars slip past it:

- `LOOPS_API_KEY` — checked only at send time, in `LoopsDelivery.deliver_now`.
  A deploy that sets the five ids but not the key boots healthy and then raises
  `LoopsDelivery::MissingApiKey` on every sign-in attempt. `SessionsController`
  does not rescue it, so that is a 500 on every branch and a total sign-in
  outage. It is uniform across all three branches, so it is not an enumeration
  oracle — but it is the whole front door. Verify it separately:
  `bin/kamal app exec 'bin/rails runner "puts LoopsDelivery.configured?"'`
  must print `true`.
- `ADMIN_NOTIFICATION_EMAIL` — also send-time only, raised from
  `TransactionalEmail.admin_application_notifications`. Its absence breaks the
  admin digest, not sign-in.
- `WEBAUTHN_ORIGIN` / `WEBAUTHN_RP_ID` / `WEBAUTHN_RP_NAME` — these have
  development defaults, so nothing raises at all. A production container
  running with `rp_id: "localhost"` boots clean, serves every page, and
  silently rejects every passkey.

The boot guard is a presence check, never a correctness check. A typo'd or
stale id passes it. Only the production smoke test (checklist step 4) catches
that, which is why step 4 has to actually be run.

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
