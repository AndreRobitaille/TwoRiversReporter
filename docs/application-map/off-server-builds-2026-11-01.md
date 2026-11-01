# November 1, 2026 — off-server build and manual release preparation

## Scope and acceptance

Andre requested the public site's off-server image pattern for Two Rivers and
the members application, with deployments kept manual. The members-app work was
handed off as a prompt for its repository agent; this checkout changes only
Two Rivers. Operational workflow **OPS-01: build, publish and deploy an exact
reviewed image** supplements the original 57 application workflows.

The user request and [deployment playbook](../../.claude/skills/deploying/SKILL.md)
define acceptance: compile on isolated Actions runners without production
credentials/data; export the tested image; require separate manual publication
and deployment. Missing evidence or identity mismatches stop replacement without
a production-build fallback. One tunnel covers the entire authorized production
operation, from inspection through verification.

## Implementation observations

- [Runtime image](../../.github/workflows/runtime-image.yml) builds for production
  inputs in PRs, every master push and manual dispatches. Permissions are read-only;
  there is no publishing or deployment step. PR images cannot be released.
- [Build script](../../script/build_production_image) archives a Git revision,
  uses a local CI Docker socket, records memory evidence and labels the amd64 image
  with revision/service. It checks runtimes, then starts the real entrypoint with
  four disposable PostgreSQL databases on an internal network. Production clear
  settings use synthetic secrets and database host; recurring jobs are disabled.
- [Image smoke script](../../script/production_image_smoke.rb) checks the actual
  primary/cache/queue/cable connections, persisted settings, a cache round trip
  and embedded-worker cleanup-job completion. Build-script requests check health,
  homepage, sign-in and compiled CSS. These are configured CI assertions, not
  locally observed container outcomes.
- [Manual publisher](../../bin/publish-image) checks workflow, success, trigger,
  exact revision and both checksums before registry access. It decompresses the
  image, uses temporary local credentials, and validates the published identity.
- [Release entry point](../../bin/release) owns one tunnel and adds `--skip-push`
  through `trr_kamal`. [Image checks](../../lib/release_image.sh) validate digest,
  revision, service and architecture before replacement. The
  [pre-deploy hook](../../.kamal/hooks/pre-deploy) repeats validation after the
  final pull; final verification checks the actual running container's image ID.
  The [pre-build hook](../../.kamal/hooks/pre-build) refuses Kamal image builds.

Application behavior, schema and service/database/volume identities are unchanged.
The Dockerfile uses serial gem installation. CI's 3 GiB build cap does not change
the shared production builder's limits.

## Local verification

Base: `c497838b091f2ed83e0c451637f4bcf4f945e9ef`, plus uncommitted changes.
Environment: `arch-herdr`, Ruby 4.0.9 and the permanent external application bundle.
The normal Rails runner discovers the operational tests:

```sh
PARALLEL_WORKERS=1 bin/rails test test/publish_image_test.rb test/release_session_test.rb test/production_image_workflow_test.rb test/config/deploy_test.rb
RUBOCOP_CACHE_ROOT=/tmp/trr-release-rubocop bin/rubocop
bin/release check
shellcheck bin/release lib/release_image.sh script/build_production_image bin/publish-image .kamal/hooks/pre-build .kamal/hooks/pre-deploy
ruby -c script/production_image_smoke.rb
git diff --check
```

Results: **18 tests / 134 assertions**, zero failures, errors or skips. Full
RuboCop inspected **631 files**, with no offenses. ShellCheck, local release
checks, Ruby syntax and diff checks passed; **107 local documentation link
targets** were checked and exist. No additional browser suite was run because
application UI behavior was not changed.

Tests execute the real shell scripts, JSON validation, checksums, decompression,
temporary-credential cleanup and hook in isolated temporary checkouts. GitHub,
registry, SSH, HTTP and Kamal transports are synthetic. Success proves a single
session and `--skip-push` replacement. Refusals cover invalid workflow evidence,
corrupt/incompletely checksummed archives, invalid compression, missing/invalid
digests, wrong identities, changed final pulls, dirty/unpushed checkouts, lost
tunnels, out-of-session verification and default Kamal builds. Failed deployments
leave the session available for inspection without automatic retries.

Representative defect detection used temporary copies:

1. The final-pull test passed. Replacing the hook with `exit 0` allowed simulated
   `BOOT` and failed the intended `refute_includes ... "BOOT"` assertion.
   Restoring the hook returned it to green.
2. The invalid-workflow test passed. Removing only its source-revision guard
   allowed a synthetic wrong-revision publication and failed
   `refute status.success?`. Restoration returned it to green.

These prove local guard effectiveness, not actual Docker/SSH/registry/provider
behavior or resident/browser workflow coverage.

## Unverified boundaries and activation

The local Docker socket is inaccessible. No production image was built here,
Actions run started, artifact published or production connection opened.
Real container startup, migrations and worker completion still require the first
successful exact-revision Actions run. No application data was copied.

Changes remain uncommitted; no push, merge or deployment occurred. After separate
commit/push authorization, CI can build automatically. Publication and deployment
remain manual. Before the first rollout, record the actual live revision and
review its rollback: legacy images may lack the new revision label. Do not waive
identity checks or rebuild on production to work around missing evidence.
