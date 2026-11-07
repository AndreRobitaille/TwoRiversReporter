# November 1, 2026 — shared-host deployment alignment

## Scope and acceptance

Andre requested coordination between agents in TwoRiversReporter, LegionPostTools
and wipost165 so deployment instructions and SSH/Kamal/Docker operation are more
uniform across the three applications sharing Hetzner. This updates **OPS-01**;
it does not authorize image publication, deployment or host-permission changes.

The [shared agreement](../SHARED_HOST_DEPLOYMENT.md) records the common operator
sequence and separates automatic guards from operator duties. Each repo retains
its own service, image, credentials, data and verification requirements. The
[Two Rivers entry point](../DEPLOYMENT.md) links the detailed deployment playbook
and records the local prerequisites and remaining manual checks.

## Two Rivers change

The session now exports `release_kamal`, the common helper name used across the
three repositories. It checks the existing tunnel and selects the generated
session configuration. Internal calls use it; `trr_kamal` remains a compatibility
alias. Existing image/digest guards and pull-only deployment behavior are retained.
The interactive shell disables inherited errexit and command-history persistence,
so failures return to the same session for diagnosis without saving typed secrets.

The new behavioral assertions run the real shell entry point with synthetic
SSH/Kamal transports. The session test opens one session, calls the common helper, checks the
generated configuration path, simulates tunnel loss, proves no second Kamal
invocation occurs, and exits with exactly one owned close operation. This proves
local session behavior, not real SSH multiplexing or a production rollout.
The helper also runs from the app root when the operator changes directory,
isolates a reintroduced signing-agent variable and refuses caller-supplied Kamal
configuration. The tests exercise those boundaries through the exported helper.

## Execution evidence

Base: `f03db83c4f2d1a6b10490606d1485dc65da0469c`, plus this uncommitted change.
Environment: workstation project `arch-herdr`, repository Ruby and permanent
external bundle. No production connection was opened.

```sh
PARALLEL_WORKERS=1 bin/rails test test/release_session_test.rb test/publish_image_test.rb test/production_image_workflow_test.rb test/config/deploy_test.rb
RUBOCOP_CACHE_ROOT=/tmp/trr-shared-deployment-rubocop bin/rubocop
shellcheck bin/release lib/release_image.sh script/build_production_image bin/publish-image .kamal/hooks/pre-build .kamal/hooks/pre-deploy
bin/release check
git diff --check
```

The normal Rails runner executed **20 tests / 149 assertions**, with zero failures,
errors or skips. Full RuboCop inspected **633 files**, with no offenses. ShellCheck,
local release checks and diff checks passed.

Representative defect detection used a temporary copy under
`/tmp/trr-shared-deployment-fault-*` and the normal Rails runner. The selected new
test passed with nine assertions. Removing only `assert_tunnel` from the isolated
helper allowed a second Kamal invocation after simulated connection loss; the
intended count assertion failed (`expected 1, actual 2`). Restoring the helper
returned the same test to green with nine assertions. After the configuration and
environment checks were added, both helper tests passed together with 15
assertions, the isolated tunnel fault failed the same count assertion, and
restoration returned both tests to green. The working checkout was
never faulted. The runner also demonstrated the missing common-helper failure
before implementation.

The shared copies and Markdown links/anchors are checked during reconciliation.
External transport remains simulated in these tests. This change did not run
application browser journeys, GitHub Actions, a real image build, registry
publication or production checks. Existing CI/publication evidence for the base
revision does not validate this uncommitted revision.

## Three-repository reconciliation

The shared agreement was compared byte-for-byte in all three working checkouts.
Its SHA-256 is
`aab8c3077ba38ff0cfd947c404e040c2e06cc93e6211fe52faf52f0d2728c95f`.
All three AGENTS.md files and deployment entry points link it; all three release
scripts expose `release_kamal` and have executable pre-build refusal hooks.
Two Rivers' changed Markdown passed 66 local link/anchor checks.

The public-site agent began on clean `b36bea320d98844d17ee3d7406253c0e90899336`.
It removed current production remote-builder selection, added build refusal and
rollback-version mismatch guards, and corrected active hosting/recovery guidance.
Its normal focused tests passed 16 tests / 134 assertions after the last helper
follow-up. Full local CI passed earlier in this pass (112 Rails tests / 2,300
assertions, adapter tests, lint/security, autoload and assets); that full run
predates the final bounded shell-context changes. Evidence is in wipost165's
`docs/verification/2026-11-01-deployment-alignment.md`.

LegionPostTools began at `846cacfb77bc7590766274c46a7fbbe12ccfc096` with a
substantial pre-existing uncommitted release rewrite. Its committed `check` still
opens production access and its committed wrapper still supports the older
keep-master/remote-build flow. The shared current workflow is in the uncommitted
checkout, not that committed version. The agent preserved those changes and added
the common helper and its regression checks. The normal Rails runner passed 14
tests / 165 assertions with no failures, errors or skips. Its isolated removal of
the session guard exposed an extra simulated Kamal call as expected; lint,
ShellCheck, syntax, links and whitespace checks passed. Its execution evidence and deferred
image/publication, running-container and database-sync transport gaps are recorded
in `docs/deployment/2026-11-01-shared-host-alignment.md` in that repository.

These changes remain local and uncommitted in all three apps. No GitHub checks
for the new revisions, registry writes or production activation are claimed.

## Remaining limits

The shared agreement does not introduce a host-wide deployment lock, automate
capacity judgment or normal-CI approval, install tools, change sudo/Docker access,
or create a new infrastructure service. Cohost/database preservation, rollback
readiness, worker health and affected live workflows still require the explicit
checks listed in the app guides. Separate repo audits record additional image
evidence and recovery gaps; shared wording does not turn them into verified guards.
