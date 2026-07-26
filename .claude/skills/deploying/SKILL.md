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
- `LOOPS_API_KEY` — in **encrypted credentials** (`config/credentials.yml.enc`),
  under the key `loops_api_key`. It is not an env var and is not in
  `.kamal/secrets`; Kamal already unlocks it in production via
  `RAILS_MASTER_KEY`. `LoopsDelivery.api_key` reads credentials first and falls
  back to `ENV["LOOPS_API_KEY"]` as an escape hatch. Edit with
  `bin/rails credentials:edit`.

`config/master.key` is gitignored, so git worktrees don't get it. Symlink it:
`ln -s /home/andre/Development/TwoRiversReporter/config/master.key config/master.key`

### Passwordless Auth Configuration (deployed)

Passwordless auth is live. Everything below is already set — this section
documents where each value lives and what breaks if it is lost, not a list of
things to do.

Every transactional email is a template created in the Loops dashboard. The app
reads each template's id from an env var, and the five ids plus the WebAuthn
settings, `ADMIN_NOTIFICATION_EMAIL` and `APP_HOST` are all in
`config/deploy.yml` under `env: clear:` — they identify templates and hosts,
they do not authorise anything. Read `config/deploy.yml` for the current
values; do not copy them here, or the two will drift.

| Env var | Where it lives | Sent / used when | If it is wrong or missing |
|---------|----------------|------------------|---------------------------|
| `LOOPS_API_KEY` | `config/credentials.yml.enc` | Every Loops delivery | Container boots healthy, then every sign-in 500s (`LoopsDelivery::MissingApiKey`) |
| `LOOPS_MAGIC_LINK_TRANSACTIONAL_ID` | `deploy.yml` `env: clear:` | Active member requests sign-in; application approved (`sign_in_url`) | Production refuses to boot |
| `LOOPS_APPLICATION_LINK_TRANSACTIONAL_ID` | `deploy.yml` `env: clear:` | Applicant resumes their application (`application_url`) | Production refuses to boot |
| `LOOPS_ADMIN_APPLICATION_NOTIFICATION_TRANSACTIONAL_ID` | `deploy.yml` `env: clear:` | Pending applications need review (`application_count`, `applicant_emails`) | Production refuses to boot |
| `LOOPS_NO_ACCOUNT_TRANSACTIONAL_ID` | `deploy.yml` `env: clear:` | Sign-in requested for an address with no account (`apply_url`) | Production refuses to boot |
| `LOOPS_APPLICATION_PENDING_TRANSACTIONAL_ID` | `deploy.yml` `env: clear:` | Sign-in requested by an applicant still under review (no variables) | Production refuses to boot |
| `ADMIN_NOTIFICATION_EMAIL` | `deploy.yml` `env: clear:` | Recipient of the admin application digest | Boots clean; the admin digest raises at send time |
| `APP_HOST` | `deploy.yml` `env: clear:` | `config.action_mailer.default_url_options` in `config/environments/production.rb` | Boots clean; emailed URLs point at the wrong host or become unclickable |
| `WEBAUTHN_ORIGIN` | `deploy.yml` `env: clear:` | Passkey registration and authentication | Boots clean; every passkey is silently rejected |
| `WEBAUTHN_RP_ID` | `deploy.yml` `env: clear:` | Passkey registration and authentication | Boots clean; every passkey is silently rejected |
| `WEBAUTHN_RP_NAME` | `deploy.yml` `env: clear:` | Passkey registration and authentication | Cosmetic only (name shown in the OS passkey prompt) |

Outside production the transactional ids fall back to literal defaults
(`no_account`, `application_pending`, `sign_in_magic_link`, ...) and
`TransactionalEmail::Message#deliver_now` is a no-op, so local and test runs
never hit Loops.

**The five ids are enforced at boot, and that is deliberate.**
`config/initializers/verify_transactional_email_ids.rb` calls
`TransactionalEmail.verify_transactional_ids!`, which reads all five ids when
`Rails.env.production?`. A missing one raises
`TransactionalEmail::MissingTransactionalId` during boot, the container never
becomes healthy, and Kamal rolls the deploy back.

The reason it fails the deploy rather than degrading is enumeration. Nothing
rescues `MissingTransactionalId` at request time, and
`SessionsController#create` answers every address with the same redirect
precisely so a visitor cannot tell which addresses hold accounts. Drop the
no-account template id and an unknown address 500s while a real one still
302s — a perfect address oracle, and in a small city that exposes the people
who hold accounts. A partial setup must not be reachable, so it is not
allowed to boot.

The guard is skipped when `SECRET_KEY_BASE_DUMMY` is set. `docker build` runs
`assets:precompile` with `RAILS_ENV=production` but none of the real env, so
without that skip the guard would break every image build.

**What the boot guard does *not* cover.** `TRANSACTIONAL_ID_READERS` lists the
five transactional ids and nothing else:

- `LOOPS_API_KEY` is checked only at send time, in `LoopsDelivery.deliver_now`.
  A deploy with all five ids but no key boots healthy and then raises
  `LoopsDelivery::MissingApiKey` on every sign-in attempt. It is uniform across
  all three branches, so it is not an enumeration oracle — but it is the whole
  front door, and sign-in is the only way in. Verify it separately:
  `bin/kamal app exec 'bin/rails runner "puts LoopsDelivery.configured?"'`
  must print `true`.
- `ADMIN_NOTIFICATION_EMAIL` is also send-time only, raised from
  `TransactionalEmail.admin_application_notifications`. Its absence breaks the
  admin digest, not sign-in.
- `WEBAUTHN_ORIGIN` / `WEBAUTHN_RP_ID` / `WEBAUTHN_RP_NAME` have development
  defaults in `config/initializers/webauthn.rb` (`http://localhost:3000` /
  `localhost`), so nothing raises at all. A production container running with
  `rp_id: "localhost"` boots clean, serves every page, and silently rejects
  every passkey.

**Loops' sending domain must stay verified.** An unverified domain still
accepts the API call and returns success — the delivery then silently never
arrives. Nothing in the app can detect this. If sign-in emails stop showing up
while `LoopsDelivery.configured?` is `true` and no errors are logged, check
domain verification in the Loops dashboard first.

**The boot guard is a presence check, never a correctness check.** A transposed
or stale id passes it and boots a perfectly healthy container that sends
nothing, or sends the wrong template, on the branch you typo'd. After any
change to the ids, smoke-test all three sign-in branches against production
(unknown address, pending applicant, active member), confirm each receives its
email, then register and use a passkey. That is the only thing that catches it.

No emoji in any template copy — standing project rule for all user-facing text.

### Database Backups (still not automated)

There is no backup cron. Several manual dumps were taken during the
passwordless-auth work and live on the dev machine in `~/backups/tworivers/`,
including a `-preauth-` dump taken before the migration that dropped the
password, TOTP and recovery-code columns.

```bash
ssh root@178.156.250.235 \
  "docker exec two_rivers_reporter-db pg_dump -U two_rivers_reporter two_rivers_reporter_production" \
  | gzip > ~/backups/tworivers/two_rivers_reporter_production-$(date -u +%Y%m%dT%H%M%SZ).sql.gz
```

Take one before any destructive migration. The Postgres data lives in a Docker
volume (`two_rivers_reporter_pgdata`) with nothing else guarding it.

### Recurring Jobs (Solid Queue, `config/recurring.yml`)

| Job | Schedule | Purpose |
|-----|----------|---------|
| `clear_solid_queue_finished_jobs` | Hourly at :12 | Prune completed job records |
| `refresh_topic_descriptions` | Mondays at 3am | Regenerate stale topic descriptions (90-day threshold) |
| `cleanup_expired_auth_records` | Daily at 4am | `ExpiredAuthRecordsCleanupJob` — deletes expired sessions, used/expired magic links, and sign-in attempts past their throttle window |

### Key Files

- `config/deploy.yml` — Kamal configuration (servers, registry, accessories, env)
- `.kamal/secrets` — Secret sourcing (shell expressions, not raw values)
- `.env` — Database password (gitignored, required for deploys)
- `config/initializers/verify_transactional_email_ids.rb` — Boot guard that refuses a production container missing a Loops transactional id
- `config/initializers/webauthn.rb` — Reads the three `WEBAUTHN_*` vars; defaults to localhost when unset
- `config/postgres/init.sql` — Creates cache/queue/cable databases and pgvector extension
- `Dockerfile` — Production image (Ruby 4.0, poppler-utils, tesseract, yt-dlp, jemalloc)
- `app/views/og/default.html.erb` + `lib/tasks/og.rake` + `public/og-image.png` + `vendor/fonts/Outfit-Black.ttf` — social preview image. Edit the ERB, then run `bin/rails og:generate` to regenerate the PNG. Commit both.

**Not yet automated:** database backups. High priority — see *Database Backups*
above for the manual command and where existing dumps live.

## Reauthentication lockout recovery

If the step-up rules misfire, the console is the escape hatch. The magic-link fallback means a
member who can read their email is never fully blocked, so this is for genuine emergencies only.

Grant a session an immediate step-up window:

```bash
bin/kamal app exec "bin/rails runner 'u = User.find_by(email_address: \"andre@xyzmodem.com\"); s = u.sessions.order(:last_seen_at).last; s.update_columns(reauthenticated_at: Time.current); puts s.slice(:id, :ip_prefix, :device_fingerprint, :reauthenticated_at)'"
```

Re-anchor a session to wherever it is now being used, clearing a context mismatch:

```bash
bin/kamal app exec "bin/rails runner 'u = User.find_by(email_address: \"andre@xyzmodem.com\"); s = u.sessions.order(:last_seen_at).last; s.update_columns(ip_prefix: nil, device_fingerprint: nil); puts \"cleared; the next request re-challenges, then adopts the new context\"'"
```

Inspect what a session is anchored to before changing anything:

```bash
bin/kamal app exec "bin/rails runner 'User.find_by(email_address: \"andre@xyzmodem.com\").sessions.order(:last_seen_at).each { |s| puts s.slice(:id, :ip_address, :ip_prefix, :device_fingerprint, :reauthenticated_at, :last_seen_at).inspect }'"
```
