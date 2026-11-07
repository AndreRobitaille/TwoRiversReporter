---
name: deploying
description: Use when deploying TwoRiversReporter to production, running commands against the live server, or shipping prompt-template changes. Requires one verified persistent SSH tunnel for all production SSH operations, including read-only checks. Covers Kamal 2 deploy commands, the Hetzner/Docker/pgvector infrastructure, secrets sourcing, recurring jobs, and the mandatory deploy-before-populate ordering for prompt templates.
---

# Production Deployment

**Live at:** `https://tworiversmatters.com`

Read the [shared operator agreement](../../../docs/SHARED_HOST_DEPLOYMENT.md) and
[Two Rivers deployment entry point](../../../docs/DEPLOYMENT.md) first. They align
the operator sequence with LegionPostTools and wipost165 and distinguish automatic
guards from checks still assigned to the operator. This playbook supplies the
Two Rivers details; commands in historical plans do not supersede it.

## Off-server images and manual deployment

The `Runtime image` workflow (`.github/workflows/runtime-image.yml`) builds
linux/amd64 on isolated GitHub Actions runners for production-related pull
requests, every `master` push, and manual workflow dispatches. It never publishes
to the registry or deploys. Checkout credentials are not persisted, and no
production credentials, SSH key, email token, AI key, or production data enter CI.

`script/build_production_image` builds an archived Git revision, checks the pinned
runtimes, and starts the real production entrypoint/Thruster with disposable
PostgreSQL databases on an internal Docker network. All four databases, a primary
write/read, Solid Cache, embedded Solid Queue job completion, health, homepage,
sign-in and compiled stylesheet delivery are checked. Recurring jobs are disabled;
only a synthetic cleanup job runs. The CI builder has a 3 GiB cap; this does not
change the existing shared production builder or its 1,536 MiB cap.

Successful push/manual runs export `production-image-<full SHA>` for three days.
PR runs validate their merge revision but do not export a releasable image.
Build logs, memory evidence and startup checks are retained for seven days. An
expired artifact requires a new successful workflow run at the same reviewed ref.

After explicit authorization to publish, use a clean checkout at that exact
reviewed revision, with its normal required CI checks passing:

```bash
CRANE=/path/to/crane bin/publish-image ACTIONS_RUN_ID
export RELEASE_IMAGE_DIGEST=sha256:THE_PRINTED_REGISTRY_DIGEST
```

`bin/publish-image` needs `gh`, Ruby, gzip, sha256sum and
[crane](https://github.com/google/go-containerregistry/tree/main/cmd/crane), but
no local Docker daemon. It checks the workflow identity, successful status, exact
revision, allowed trigger and downloaded artifact checksums before registry
access. It decompresses the verified archive, publishes only the SHA tag to
`ghcr.io/andrerobitaille/two_rivers_reporter`, validates its identity, and prints
the registry digest. Maintainer authentication stays in a temporary local directory
removed on exit; it is not sent to CI. Publication is a separate manual action
from deployment.

## Mandatory persistent SSH tunnel

**Before any production SSH operation, including read-only inspection, open
one `bin/release session`.** This entry point owns the persistent tunnel and
exports `release_ssh`, `release_kamal`, `release_deploy`, `release_setup` and
`release_verify` into an interactive `trr-release>` shell. All commands from
first inspection through final verification belong in that same shell.
`bin/release check` is local-only; it does not connect to production.

Finish local checks and any separately authorized commit/push/publication first.
Deploy only from a clean checkout whose HEAD exactly matches its remote branch:

```bash
bin/release check
source .env
export TWO_RIVERS_REPORTER_DATABASE_PASSWORD
export RELEASE_IMAGE_DIGEST=sha256:THE_VERIFIED_REGISTRY_DIGEST
bin/release session
# Inside this shell, only when deployment has been explicitly authorized:
release_deploy
# Follow-up inspection uses this same tunnel:
release_verify
release_kamal app logs --since 5m
exit
```

`config/master.key` must exist. The wrapper reads the identity file from
`${RELEASE_SSH_CONFIG:-$HOME/.ssh/config}` for `178.156.250.235`. Required local
commands include SSH, timeout, socat, Ruby, curl, gh and `bin/kamal`. Run production
commands with host access if the restricted sandbox presents synthetic system
SSH-file ownership; never chown system files based on that sandbox view.

One outer SSH master opens a localhost-only forward on port 22222. Choose
`RELEASE_TUNNEL_PORT` if that port is occupied; never stop an unknown listener.
Both Kamal's Net::SSH and Docker's OpenSSH use this forward through an owned
wrapper and temporary configuration. Merely setting a control socket or
`DOCKER_HOST` is insufficient. No remote builder is configured for this release
path. Every Kamal invocation goes through `release_kamal`, which checks the tunnel and
adds `--skip-push` to deployment commands. The pre-build hook refuses image builds.
`trr_kamal` remains a compatibility alias; use `release_kamal` in new instructions
so the session commands match the other two repositories.

`release_deploy` requires a verified digest, successful session preflight, clean
checkout and an exactly pushed HEAD. It pulls and checks the digest, source
revision, service and linux/amd64 identity. The pre-deploy hook repeats these
checks after Kamal's final pull and before container replacement. A missing digest
or changed tag stops the release; there is no production-build fallback.
Standalone `bin/release deploy`, `setup` and `push-deploy` are disabled.

The preflight records the current Two Rivers image and protected members/public
containers. Preserve the actual prior running revision as the rollback target;
local `master` can lag production. The release verifies the intended container,
image identity, protected-service containers, proxy routes, `/up`, `/`, sign-in,
anonymous admin redirect and the co-hosted sites. Inspect recent logs and any
change-specific workflows in the same session before declaring success. Database
backup requirements below still apply to destructive migrations. Image extraction,
migrations and brief old/new container overlap still require runtime headroom;
coordinate one deployment at a time across the shared host.

### Failure, verification and cleanup

- If establishment, verification, or the tunnel fails, stop remote work and report
  the exact failure and whether production changed. No direct fallback, parallel
  outer connection, automatic reconnect, or retry loop is allowed.
- Failed commands return to the existing shell for inspection. Wait at least five
  minutes before any single further attempt. If the tunnel dies, stop dependent
  work and clean up; after the cooldown, make at most one chosen replacement
  attempt. A second failure leaves remote work blocked.
- Keep the session through final verification, then exit once. Cleanup closes only
  its owned master and removes the temporary directory/configuration/socket.
  Confirm its forward is closed. Preserve unrelated worktree files and sessions.
- Public HTTPS probes do not require SSH. Older optional-tunnel instructions and
  ad hoc remote-builder recipes are superseded by this entry point.

## Deploy Commands

All production commands below run inside the verified `bin/release session`.
Publication, deployment and production mutation each need their existing authority.

| Task | Command |
|------|---------|
| Deploy verified image | `release_deploy` |
| First-time setup with verified image | `release_setup` |
| Rails console | `release_kamal console` |
| Tail logs | `release_kamal logs` |
| Shell into container | `release_kamal shell` |
| DB console | `release_kamal dbc` |
| Reboot app | `release_kamal app boot` |
| Run a job | `release_kamal app exec "bin/rails runner 'JobClass.perform_now(id)'"` |

The database password must be exported before opening the session. `.env` keys are
not automatically exported; non-secret settings belong in `env: clear:`.

## Automated Runtime Maintenance

The `Update runtime dependencies` GitHub Actions workflow runs weekly and can
also be dispatched manually. It opens or refreshes a pull request; it never
merges or deploys.

One repository setting is required before activation: under **Settings →
Actions → General → Workflow permissions**, enable **Allow GitHub Actions to
create and approve pull requests**. GitHub combines creation and approval in
one setting; this workflow requests write access but contains no approval or
merge step.

The updater changes only `Dockerfile` and `.ruby-version`. It keeps the latest
stable Ruby version and amd64 image digest together, including new Ruby release
series, and refreshes the Dockerfile frontend, Deno, and yt-dlp pins from
official release metadata. Missing or malformed SHA-256 digests, mismatched
Ruby files, and version downgrades make the job fail without opening a pull
request. Before pushing the update branch, the job performs a complete
production image build so the new Ruby image, binary checksums, gems, and asset
compilation are verified together.

| Task | Command |
|------|---------|
| Preview available runtime updates | `ruby script/update_runtime_dependencies --dry-run` |
| Apply runtime updates locally | `ruby script/update_runtime_dependencies` |
| Fail if committed pins are stale | `ruby script/update_runtime_dependencies --check` |

Review and merge the maintenance pull request normally, then use the standard
Kamal deploy process above when ready. Dependabot separately maintains Bundler
and GitHub Actions dependencies.

## Prompt Template Deploy Ordering

After editing `lib/prompt_template_data.rb`, production ordering matters:

1. Validate locally with `bin/rubocop` and `bin/rails prompt_templates:validate`
2. Update the local DB with `bin/rails prompt_templates:populate` if needed
3. Commit and push
4. Wait for the exact-revision image checks, publish it manually, then run
   `release_deploy` inside the single authorized release session
5. Then run `release_kamal app exec "bin/rails prompt_templates:populate"`

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
reads each template's id from an env var, and the six ids plus the WebAuthn
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
| `LOOPS_APPLICATION_DENIED_TRANSACTIONAL_ID` | `deploy.yml` `env: clear:` | Admin denies an application (`denial_reason`) | Production refuses to boot |
| `ADMIN_NOTIFICATION_EMAIL` | `deploy.yml` `env: clear:` | Recipient of the admin application digest | Boots clean; the admin digest raises at send time |
| `APP_HOST` | `deploy.yml` `env: clear:` | `config.action_mailer.default_url_options` in `config/environments/production.rb` | Boots clean; emailed URLs point at the wrong host or become unclickable |
| `WEBAUTHN_ORIGIN` | `deploy.yml` `env: clear:` | Passkey registration and authentication | Boots clean; every passkey is silently rejected |
| `WEBAUTHN_RP_ID` | `deploy.yml` `env: clear:` | Passkey registration and authentication | Boots clean; every passkey is silently rejected |
| `WEBAUTHN_RP_NAME` | `deploy.yml` `env: clear:` | Passkey registration and authentication | Cosmetic only (name shown in the OS passkey prompt) |

Outside production the transactional ids fall back to literal defaults
(`no_account`, `application_pending`, `sign_in_magic_link`, ...) and
`TransactionalEmail::Message#deliver_now` is a no-op, so local and test runs
never hit Loops.

**The six ids are enforced at boot, and that is deliberate.**
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
six transactional ids and nothing else:

- `LOOPS_API_KEY` is checked only at send time, in `LoopsDelivery.deliver_now`.
  A deploy with all five ids but no key boots healthy and then raises
  `LoopsDelivery::MissingApiKey` on every sign-in attempt. It is uniform across
  all three branches, so it is not an enumeration oracle — but it is the whole
  front door, and sign-in is the only way in. Verify it separately:
  `release_kamal app exec 'bin/rails runner "puts LoopsDelivery.configured?"'`
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
release_ssh \
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

## Session and reauthentication rules

Sessions are anchored to a context — `ip_prefix` (IPv4 /24, IPv6 /48) and `device_fingerprint`
(browser family and platform) — and two gates read it. The admin boundary passes when the context
matches **or** the session was stepped up within the last 15 minutes. Adding or removing a passkey
requires a strictly matching context *and* a step-up in that window. Full design:
`docs/superpowers/specs/2026-07-25-session-and-reauthentication-hardening-design.md`.

### Pre-deploy check (run before the deploy, not after)

The shortened `INACTIVITY_LIMIT` signs out every session it has already outlived, so count them
first and confirm the owner's is not among them. Run this **against the old image**, which is why
60 days is written out rather than read from `Session::INACTIVITY_LIMIT` — that constant is still
180 days in the container you are about to replace:

```bash
release_kamal app exec "bin/rails runner 'doomed = Session.where(\"last_seen_at IS NULL OR last_seen_at < ?\", 60.days.ago); owner = User.find_by(email_address: \"andre@xyzmodem.com\"); puts \"sessions total: \" + Session.count.to_s; puts \"invalidated by the 60-day rule: \" + doomed.count.to_s; puts \"owner sessions invalidated: \" + doomed.where(user_id: owner.id).count.to_s'"
```

If the owner's count is anything but `0`, sign in again from the browser you intend to deploy from
before continuing — that refreshes `last_seen_at` and takes the session out of the doomed set.

Then take a database backup (see *Database Backups* above). The context migration backfills every
existing session, and a backfill is not something to run without a dump behind it.

### Post-deploy verification walk

Confirm the backfill first. Both counts must be `0`; a session missing `ip_prefix` while holding an
`ip_address` means the backfill did not run, and every live member would be challenged at once:

```bash
release_kamal app exec "bin/rails runner 'puts \"sessions: \" + Session.count.to_s; puts \"missing ip_prefix: \" + Session.where(ip_prefix: nil).where.not(ip_address: nil).count.to_s; puts \"missing reauthenticated_at: \" + Session.where(reauthenticated_at: nil).count.to_s'"
```

Then walk it in a browser, on `https://tworiversmatters.com`:

1. Sign in with a magic link. Confirm you land on the page you asked for, not the home page.
2. Open `/admin`. Expect either the dashboard (the backfilled context matched) or the step-up page
   at `/reauthentication` — both are correct outcomes.
3. If challenged, complete the step-up with a passkey. Expect to land on `/admin`, and expect the
   next few admin pages to load without challenging again.
4. Open `/settings/security`, add a passkey, then remove it. That surface requires a strictly
   matching context, so it is the one that proves the anchor is right rather than merely tolerated.
5. Open `/admin/audit_events` and confirm the actions from step 4 onwards are recorded.

Recipe 3 is the one that catches a broken anchor, because the grace window can hide one at the admin
boundary for 15 minutes.

### Reauthentication lockout recovery

The console is the escape hatch when the step-up rules misfire. The magic-link fallback means a
member who can read their email is never fully blocked — signing in again mints a fresh session with
a correct context and a fresh step-up — so this is for the case where email delivery is also broken.

| Symptom | Recipe |
|---|---|
| Not sure what is wrong | *Inspect*, always first |
| `/admin` challenges, the step-up succeeds, and the next page challenges again | *Re-anchor*. A rotating egress needs the recorded prefix rewritten, not another step-up |
| Locked out of `/admin` and need 15 minutes to work | *Stamp a step-up window* |
| `/settings/security` refuses to add or remove a passkey | *Re-anchor*. That gate is strict; a stamped window alone does not satisfy it |

**Inspect** what a session is anchored to before changing anything. Note the `id` you mean to act
on — the recipes below target the most recently seen session, which is the wrong one if you have
several:

```bash
release_kamal app exec "bin/rails runner 'User.find_by(email_address: \"andre@xyzmodem.com\").sessions.order(:last_seen_at).each { |s| puts s.slice(:id, :ip_address, :ip_prefix, :device_fingerprint, :reauthenticated_at, :last_seen_at).inspect }'"
```

**Re-anchor** a session to the network and browser the next request will actually come from. This is
the durable fix: it writes the values the app will compute on arrival, so both gates pass. Get the
egress address from the machine you will browse from — not from the server, and not from the
session's stored `ip_address`, which is where it used to be:

```bash
curl -s https://api.ipify.org; echo
```

```bash
release_kamal app exec "bin/rails runner 'ip = \"203.0.113.45\"; s = User.find_by(email_address: \"andre@xyzmodem.com\").sessions.order(:last_seen_at).last; s.update_columns(ip_prefix: NetworkPrefix.for(ip), device_fingerprint: DeviceFingerprint.for(s.user_agent), reauthenticated_at: Time.current); puts s.slice(:id, :ip_prefix, :device_fingerprint, :reauthenticated_at).inspect'"
```

Substitute the real address for `203.0.113.45`. That command keeps the browser half of the anchor,
derived from the session's own recorded `user_agent`, which is correct whenever only the network
changed. If you are moving the session to a **different browser**, paste that browser's User-Agent
string in as well:

```bash
release_kamal app exec "bin/rails runner 'ip = \"203.0.113.45\"; ua = \"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36\"; s = User.find_by(email_address: \"andre@xyzmodem.com\").sessions.order(:last_seen_at).last; s.update_columns(ip_prefix: NetworkPrefix.for(ip), device_fingerprint: DeviceFingerprint.for(ua), reauthenticated_at: Time.current); puts s.slice(:id, :ip_prefix, :device_fingerprint, :reauthenticated_at).inspect'"
```

The User-Agent goes inside the Ruby script, which is itself inside single quotes inside the shell's
double quotes. No mainstream browser's User-Agent contains a single quote; if one ever does, write
the script to a file on the server and run that instead of fighting the quoting.

Do **not** set the context columns to `nil` to "clear" a mismatch. `SessionContext#matches?` is
strict equality including `nil`, so a nil-context row matches no real request: mismatched before,
mismatched after.

**Stamp a step-up window** to get into `/admin` for 15 minutes without touching the anchor. The
admin gate honours a recent step-up as well as a matching context, which is what makes this work —
but it expires, and it does **not** open passkey add or remove, which require the context to match:

```bash
release_kamal app exec "bin/rails runner 's = User.find_by(email_address: \"andre@xyzmodem.com\").sessions.order(:last_seen_at).last; s.update_columns(reauthenticated_at: Time.current); puts s.slice(:id, :ip_prefix, :device_fingerprint, :reauthenticated_at).inspect'"
```

**Last resort**, if a session is beyond saving: destroy it and sign in again. A new session records
the correct context on arrival, and `start_new_session_for` stamps `reauthenticated_at`, so first
passkey setup works immediately:

```bash
release_kamal app exec "bin/rails runner 'User.find_by(email_address: \"andre@xyzmodem.com\").sessions.destroy_all; puts \"sessions destroyed; sign in again\"'"
```
