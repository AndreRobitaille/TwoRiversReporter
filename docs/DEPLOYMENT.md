# Two Rivers deployment

Start with the [shared Hetzner deployment agreement](SHARED_HOST_DEPLOYMENT.md).
It defines the common operator sequence for Two Rivers, LegionPostTools and
wipost165. The [deployment playbook](../.claude/skills/deploying/SKILL.md) remains
the detailed Two Rivers reference for transport, secrets, backups, verification
and prompt-template operations. Follow these current references rather than
commands in historical plans or release records.

## Two Rivers configuration

| Setting | Value |
| --- | --- |
| Kamal service | `two_rivers_reporter` |
| Registry image | `ghcr.io/andrerobitaille/two_rivers_reporter` |
| Public hosts | `tworiversmatters.com`, `www.tworiversmatters.com` |
| Normal CI | `.github/workflows/ci.yml` |
| Image workflow | `Runtime image`, `.github/workflows/runtime-image.yml` |
| Image artifact | `production-image-<full SHA>`, retained for three days |
| Build/startup evidence | `production-image-checks-<full SHA>`, retained for seven days |

The isolated CI builder has a 3 GiB limit. This differs from other apps' CI caps
and does not change or authorize use of any production builder. All four
production databases, persisted primary settings, Solid Cache, embedded worker
completion, HTTP and assets are exercised with disposable synthetic data.

## Local prerequisites and session commands

Use the [permanent local Ruby bundle](../README.md#local-ruby-gems).
`bin/release check` performs local shell/configuration checks. Complete normal CI
and the image workflow at the exact release SHA before publication; the release
script does not query normal application CI for you.

Publication needs `gh`, Ruby, gzip, sha256sum and `crane` or `CRANE=/path/to/crane`.
It does not use the local Docker socket. See the playbook's
[publication procedure](../.claude/skills/deploying/SKILL.md#off-server-images-and-manual-deployment).

Before the authorized production session, export
`TWO_RIVERS_REPORTER_DATABASE_PASSWORD` from the ignored local operator environment
and the verified `RELEASE_IMAGE_DIGEST`. Ensure `config/master.key` and the file
key selected by `${RELEASE_SSH_CONFIG:-$HOME/.ssh/config}` are readable. Keep all
secrets out of logs and Git. No production credentials enter Actions.

Inside the one `bin/release session`, use `release_deploy`, `release_preflight`,
`release_verify`, `release_ssh` and `release_kamal`. `trr_kamal` remains an alias
for existing sessions/instructions; new instructions use the shared helper name.
Never invoke `bin/kamal` directly. The wrapper routes Net::SSH and Docker's SSH
through its localhost-only forward and unsets `SSH_AUTH_SOCK` for Kamal. Preserve
an occupied tunnel port; select an unused `RELEASE_TUNNEL_PORT` when needed,
never to enable parallel app deployments.

## Automatic checks and operator checks

The deployment guard requires a clean checkout, exactly pushed HEAD, successful
session preflight and a verified manifest digest. It checks digest, source
revision, service and linux/amd64 before deployment and after Kamal's final pull.
The pre-build hook refuses implicit builds. `release_verify` checks the running
container's image identity, protected members/public app containers, proxy routes,
Two Rivers health/home/sign-in/admin status, members health/sign-in and the public
Post homepage.

Before replacement, use the same session to inspect available memory, pressure,
container stats, the actual live revision/rollback image and both database
containers. Automatic preflight currently records transport, app/proxy state and
protected cohost web containers; it does not assess capacity, enforce a shared
deployment lock or capture all database/worker checks. Keep those explicit in the
release evidence. Verify queue/worker health, recent logs, migration outcomes and
the affected user workflows before exiting.

Review [backup requirements](../.claude/skills/deploying/SKILL.md#database-backups-still-not-automated)
before destructive migrations. Prompt-template updates require deployment before
production population; ordinary deployment does not authorize population, data
repair, email or paid generation. See
[prompt ordering](../.claude/skills/deploying/SKILL.md#prompt-template-deploy-ordering).

### Publishing the November 2026 council profile review

The [source audit](application-map/council-promise-record-audit-2026-11-22.md) identifies the reviewed campaign positions. The three saved reports supply the overview, exact campaign words and citations displayed on the member pages. Deploy the application before syncing changed templates with `prompt_templates:sync_selected`. Inspect the dry run and apply the reviewed changes using the expected current hashes. Run `prompt_templates:validate` afterward.

For this edition, publish the approved reports against each named member’s verified April 16, 2024 service term. Resolve their evidence references against that installation, verify the full position list and source links, and save the three reports together. Preserve any newer assessment. This publication reuses reviewed reporting and requires no provider request. The next Tuesday comparison uses the installed evidence and standing allowance. Check that the production discovery schedule is at 11 p.m. America/Chicago and inspect the current month's allowance without changing its limits.

The half-point rule applies to saved and future reports at render time. The accompanying source corrections require republication of the three reviewed profiles, including the newly retained Bittner position. Sync the changed `summarize_council_term` template after deployment. Verify 12, 9 and 10 distinct positions for Bittner, Brandt and Derby respectively. Check the new evidence before replacing a later assessment.

Verify the public roster links and the three net scores (Bittner 1/12 or 8%, Brandt 4.5/9 or 50%, Derby 2.5/10 or 25%). Follow Brandt’s red −1 to the April 21 hearing and minutes. On Derby’s profile search for Paddlers Park, check the 9–0 result and open item 26-088 on pages 3–4. A meeting member link should retain the selected decision. The April 2024 edition is described in the [election feature guide](ELECTION_FEATURES.md).

The [off-server build evidence](application-map/off-server-builds-2026-11-01.md)
distinguishes implementation tests, transport simulations, real CI image execution
and outstanding production boundaries. A recorded earlier blocker does not
replace checking the current Actions run, registry image and live revision.
