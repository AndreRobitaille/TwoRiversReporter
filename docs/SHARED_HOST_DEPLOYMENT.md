# Shared Hetzner deployment agreement

Agreement: **2026-11-01**. This operator workflow applies to all three apps on
`178.156.250.235`, operated from the workstation project saved as `arch-herdr`.
The workstation and production VPS are different machines. Check the selected
project and host before running commands; a sandbox view does not establish host
permissions or production state.

Keep this document identical in TwoRiversReporter, LegionPostTools and wipost165.
Update the three copies together when the shared workflow changes. Each repo's
[deployment guide](DEPLOYMENT.md) owns its app-specific configuration, secrets,
verification and exceptions. Historical release records and plans are evidence
about their recorded revision, not current deployment instructions.

## App identities

| Repository | Kamal service | Public host | Image workflow |
| --- | --- | --- | --- |
| TwoRiversReporter | `two_rivers_reporter` | `tworiversmatters.com` | `.github/workflows/runtime-image.yml` |
| LegionPostTools | `legion_post_165_wi_tools` | `members.wipost165.org` | `.github/workflows/production_image.yml` |
| wipost165 | `legion_post_165_wi_public` | `wipost165.org`, `www.wipost165.org` | `.github/workflows/production_image.yml` |

Keep service, image, database, volume and proxy identities separate. The public
Post website has no database or worker; do not give it the members app's secrets.

## One operator sequence

1. **Prepare locally.** Preserve unrelated changes. Use a clean reviewed checkout
   of the intended revision, the repository's Ruby/gem setup and its required
   checks. `bin/release check` checks local release configuration and syntax; it
   does not contact production, run application CI or prove release readiness.
2. **Push when authorized and check the exact revision.** `bin/release push`
   pushes the current branch and checks its remote SHA. Confirm successful normal
   CI and the image workflow for the intended full Git SHA. Do not substitute
   green checks from an earlier commit or a PR merge revision for the release
   revision. A push or merge does not publish or deploy.
3. **Build in Actions.** Use the isolated GitHub Actions image workflow. It builds
   linux/amd64, starts the actual production image with synthetic inputs and
   retains evidence. Successful push/manual runs export
   `production-image-<full SHA>`; PR runs are validation only. If the artifact has
   expired, obtain a new successful run at the same reviewed ref. Follow the
   app-specific builder limits; never build on Hetzner or raise a cap to bypass
   a failure.
4. **Publish when authorized.** From that clean exact revision, run
   `CRANE=/path/to/crane bin/publish-image ACTIONS_RUN_ID`. This verifies the
   workflow/artifact evidence, publishes the SHA tag and checks image identity.
   Record the printed `RELEASE_IMAGE_DIGEST=sha256:...`. This is the registry
   manifest digest, not a Git SHA, archive checksum or Actions artifact digest.
5. **Coordinate the production window.** Only one app deployment runs at a time.
   Establish who owns the operation before opening production access. The scripts
   do not provide a cross-repository deployment lock; different tunnel ports do
   not authorize concurrent deployments. Complete local/CI/publication work first.
6. **Open one session for the authorized production operation.** Export that app's
   required secrets without printing them, set the verified digest, then run
   `bin/release session` once. Keep this shell and its owned SSH master from the
   first production inspection through final verification.
7. **Review preflight and deploy.** Inspect the actual running revision and retain
   its image identity as the rollback target. Check memory availability, pressure,
   container stats, proxy routes and the protected cohost/database baseline through
   the same session. Review migration and backup needs, then run `release_deploy`
   only after successful preflight. Image pulls and replacement must use the
   reviewed SHA and verified digest with Kamal's `--skip-push`; no build fallback.
8. **Verify and exit once.** Use `release_verify` plus the app-specific worker,
   migration, access and changed-workflow checks. Verify the running container's
   image identity and all three sites, and compare protected containers with the
   baseline. Keep the session for diagnosis and follow-up. Exit only when the
   operation is finished; close only its owned master, remove temporary transport
   configuration and confirm cleanup.

The common command sequence is:

```bash
bin/release check
# When push is authorized, and after the intended source is committed:
bin/release push
# Wait for successful normal CI and image checks at this exact HEAD.
# When publication is authorized:
CRANE=/path/to/crane bin/publish-image ACTIONS_RUN_ID
export RELEASE_IMAGE_DIGEST=sha256:THE_PRINTED_REGISTRY_MANIFEST_DIGEST
# Export only this app's required release secrets, as its guide describes.
# When the production operation is authorized:
bin/release session
# Inside this same shell, after successful preflight and capacity review:
release_deploy
release_verify
# Complete app-specific checks here, then:
exit
```

Commit, push, image publication, deployment, DNS changes, production data copying,
real email and paid provider calls keep their separate authorization boundaries.
An instruction may explicitly authorize several steps together; do not ask again
for authority already provided. None of the commands above grants authority by
itself. Routine application deployment does not authorize global proxy changes,
cohost restarts, pruning shared Docker resources or changing host permissions.

## SSH, Kamal and Docker

- `release_ssh 'COMMAND'` runs authorized host commands through the current
  session. `release_preflight` repeats preflight in that same session;
  `release_verify` performs the repository's automatic verification. Review which
  additional checks the app guide still assigns to the operator.
- The wrapper must route every SSH, Kamal Net::SSH and Docker SSH operation
  through its one outer master. A control socket or `DOCKER_HOST` alone is not
  proof that every client uses it. App-local transport implementations may differ;
  they must fail closed when that master disappears.
- Do not run bare `ssh` or `bin/kamal` against production. Use the session's
  `release_kamal` helper for any additional Kamal command; `release_deploy` handles normal
  deployment. Standalone `bin/release deploy`, `setup` and `push-deploy` are disabled.
  First provisioning is app-specific and is not part of a routine release.
- The workstation needs the documented CLI tools and file key. Publication uses
  `gh` and `crane` without a local Docker daemon. Production Docker commands run
  remotely through the session. A denied workstation Docker socket or missing
  passwordless sudo does not require adding Docker-group access, loosening socket
  permissions or changing sudo policy for this release path.
- Codex's restricted sandbox can show root-owned system files as `nobody:nobody`
  and cause misleading SSH ownership failures. Verify with read-only host access
  before diagnosing permissions. Never chown system files based on the sandbox
  view. Host access does not authorize publication or deployment.

## Failure and rollback

A failed production command returns to the existing session for diagnosis.
Do not automatically retry or reconnect. Wait at least five minutes before a
single deliberate retry. If the outer master fails, stop dependent remote work;
there is no direct fallback or parallel connection. Clean up that failed session
and, after the cooldown, make at most one chosen replacement attempt. A second
failure leaves remote work blocked.

Record whether replacement or migrations occurred before reporting a failure.
Rollback affects only the target app and still requires reviewed image evidence
and the same transport rules. Legacy images may lack required identity metadata;
prepare a compatible reviewed rollback through CI/publication when necessary,
rather than bypassing image checks. Follow the app's backup/restore requirements
before destructive migrations. An image rollback does not undo a database change.

## Evidence and remaining operator duties

Keep these claims separate: local checks, application/browser CI, image build and
synthetic startup, registry publication, actual running production image, live
workflow checks and real provider delivery. A green health endpoint does not prove
worker health or that every user workflow works. A historical failure or success
is not the status of the current revision.

Normal CI approval, cross-app serialization, capacity assessment, rollback
readiness, migration backups and app-specific live checks remain operator duties
unless the app guide points to an implemented guard and current execution
evidence. Do not describe an intended safeguard as automatic enforcement.
Record the revision, Actions run, manifest digest, actual live baseline,
commands/results, remaining gaps and cleanup disposition in the app's release
evidence. Keep secrets and production personal data out of that record.
