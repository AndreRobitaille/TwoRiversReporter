#!/usr/bin/env bash
# Shared by bin/release and an already-open release shell; sourcing opens no SSH.

require_image_digest() {
  [[ "${RELEASE_IMAGE_DIGEST:-}" =~ ^sha256:[a-f0-9]{64}$ ]] || {
    echo "release: RELEASE_IMAGE_DIGEST must be the verified sha256 digest of an off-server image" >&2
    return 1
  }
}

verify_prebuilt_image() {
  require_image_digest || return
  local head="$1" repository="ghcr.io/andrerobitaille/two_rivers_reporter" format reference
  [[ "$head" =~ ^[a-f0-9]{40}$ ]] || return 1
  [[ "${KAMAL_VERSION:-$head}" == "$head" ]] || fail "Kamal version differs from the reviewed checkout"
  reference="${2:-$repository:$head}"
  [[ "$reference" == "$repository:$head" || "$reference" =~ ^sha256:[a-f0-9]{64}$ ]] || return 1
  format='{"digests":{{json .RepoDigests}},"os":{{json .Os}},"architecture":{{json .Architecture}},"labels":{{json .Config.Labels}}}'
  release_ssh "docker image inspect --format '$format' '$reference'" | ruby -rjson -e '
    head, digest, repository = ARGV
    image = JSON.parse(STDIN.read)
    labels = image.fetch("labels") || {}
    abort "Prebuilt image digest mismatch" unless Array(image["digests"]).include?("#{repository}@#{digest}")
    abort "Prebuilt image revision mismatch" unless labels["org.opencontainers.image.revision"] == head
    abort "Prebuilt image service mismatch" unless labels["service"] == "two_rivers_reporter"
    abort "Prebuilt image must be linux/amd64" unless image["os"] == "linux" && image["architecture"] == "amd64"
    puts "Verified prebuilt image #{repository}@#{digest} for #{head}."
  ' "$head" "$RELEASE_IMAGE_DIGEST" "$repository"
}

release_run() (
  set -Eeuo pipefail
  require_image_digest
  [[ "${RELEASE_PREFLIGHT_OK:-}" == "1" ]] || fail "run release_preflight successfully in this session first"
  assert_clean_worktree
  assert_remote_matches_head
  release_ssh true </dev/null
  release_kamal build pull
  verify_prebuilt_image "$(git rev-parse HEAD)"
  release_kamal "$1"
  release_verify
)
