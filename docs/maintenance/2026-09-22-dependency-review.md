# Dependency maintenance review — 2026-09-22

The combined update incorporates the 13 open dependency/runtime PRs against
local master `458ca74`. It regenerates one valid lockfile with its `CHECKSUMS`
section intact. Five original PR diffs removed that section header, causing
Bundler to interpret checksum entries as direct dependencies.

## Reviewed PRs

| PR | Dependency | Combined target |
| --- | --- | --- |
| #128 | Ruby / Deno / yt-dlp | 4.0.7 / 2.9.7 / 2026.08.19, including pinned checksums |
| #127 | actions/cache | v6 |
| #126 | Kamal | 2.12.0 |
| #125 | actions/checkout | v7, including the pinned runtime-updater reference |
| #124 | Brakeman | 8.0.6; 8.0.5 was already on master and fails `--ensure-latest` |
| #123 | Pagy | 43.5.6 |
| #122 | image_processing | 2.0.3, with explicit ruby-vips 2.3.0 dependency |
| #121 | Bootsnap | 1.24.6 |
| #120 | Jbuilder | 2.15.1 |
| #119 | Solid Cable | 4.0.0 |
| #118 | Puma | 8.0.2 |
| #115 | Thruster | 0.1.21 |
| #104 | Propshaft | 1.3.2 |

The image_processing 2 upgrade makes image backends optional. Explicitly
retaining ruby-vips preserves the application's existing Active Storage backend.
A new test processes an attached PNG into a resized WebP and verifies its actual
pixel dimensions and content type. Solid Cable's supplied schema matches the
existing cable schema; no migration is needed for this upgrade.

## Additional security patches

A fresh ruby-advisory-db checkout at
`44784c295391577f25d198a9205eae4ba73ec4da` identified vulnerable versions still
present after applying the old PR targets. The combined lockfile includes the
minimum corrective versions below, rather than unrestricted bundle updates:

- Rails and its components 8.1.3.1; addressable 2.9.0; crass 1.0.7.
- Faraday 2.14.3; loofah 2.25.2; mail 2.9.1; MCP 0.23.0.
- msgpack 1.8.2; net-imap 0.6.4.1; Nokogiri 1.19.4.
- rails-html-sanitizer 1.7.1; websocket-driver 0.8.2.
- image_processing 2.0.3 instead of the PR's 2.0.2 target.

The Rails patch addresses the
[Active Storage variant advisory](https://github.com/rails/rails/security/advisories/GHSA-xr9x-r78c-5hrm).
The container supplies libvips 8.16.1, exceeding the patched Rails minimum 8.13.
MCP is a RuboCop development dependency here; the app has no MCP transport setup.
Its new transitive dependencies are recorded normally in the lockfile.

## Validation

Commands used Ruby 4.0.7 explicitly through `mise exec ruby@4.0.7 --`.

- `bin/rails test`: 1,748 tests, 6,830 assertions, no failures/errors, one existing
  skip for a missing meeting fixture. Passed both in the working checkout and
  in a tracked-source checkout without local credentials or environment files.
- `RAILS_ENV=test bin/rails db:prepare`: passed in the clean checkout.
- `bin/rubocop`: 508 files, no offenses.
- `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error`: no errors or
  security warnings; the latest-version guard remains enabled.
- `bin/bundler-audit check --database ...`: no known vulnerabilities against the
  refreshed advisory database above. `bin/importmap audit`: no vulnerabilities.
- Workflow YAML parsed successfully; `git diff --check` passed.
- Full amd64 Docker build passed, including frozen bundle installation, binary
  checksum verification, Bootsnap compilation, and production asset compilation.
- Built-container checks passed for Ruby 4.0.7, Deno 2.9.7, yt-dlp 2026.08.19,
  and an actual PNG-to-WebP resize using libvips.
- Local Thruster → Puma → Rails checks returned HTTP 200 for `/up` and
  `/session/new`. The two-worker configuration also passed with the in-process
  Solid Queue supervisor and worker registered in an isolated disposable database.

The build used only tracked source plus the intended edits, with no local
credentials. Every remote operation used the verified persistent SSH tunnel and
explicit remote buildx builder. The temporary image tag, tunnel, and transport
configuration were removed afterward. No production deployment occurred.

## CI coverage

Both `bin/ci` and GitHub CI now run application tests. The GitHub test job provides
PostgreSQL 17 and native image/PDF/OCR dependencies, without application secrets.
The GitHub-hosted workflow has not yet run on these unpushed changes; local
validation does not establish a green GitHub check.

PR merges, branch cleanup, and deployment remain separate from this prepared
update. Superseded PRs should only be closed after the combined update lands.
