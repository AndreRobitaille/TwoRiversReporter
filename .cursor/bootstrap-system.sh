#!/usr/bin/env bash
# Root-only, idempotent system setup for the Cursor cloud image.
# Installs the Ruby in .ruby-version (pinned checksum below), PostgreSQL 17,
# pgvector, and native libraries the test suite needs. Does not install gems
# or prepare databases — those depend on the checked-out source.
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "bootstrap-system.sh must run as root (use sudo)." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8

RUBY_VERSION="4.0.7"
RUBY_SHA256="a11b84469b76a38175bce72176f66389fc05b87a3e7545329e8685b01dcb2176"
RUBY_PREFIX="/opt/ruby-${RUBY_VERSION}"
RUBY_TARBALL="ruby-${RUBY_VERSION}-ubuntu-24.04-x64.tar.gz"
RUBY_URL="https://github.com/ruby/ruby-builder/releases/download/ruby-${RUBY_VERSION}/${RUBY_TARBALL}"

. /etc/os-release
if [[ "${VERSION_CODENAME}" != "noble" ]]; then
  echo "This bootstrap expects Ubuntu 24.04 (noble); found ${VERSION_CODENAME:-unknown}." >&2
  exit 1
fi

if ! grep -Rqs "universe" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
  cat >/etc/apt/sources.list.d/ubuntu-universe.sources <<EOF
Types: deb
URIs: http://archive.ubuntu.com/ubuntu
Suites: ${VERSION_CODENAME} ${VERSION_CODENAME}-updates ${VERSION_CODENAME}-security
Components: universe
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
fi

apt-get update
apt-get install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  curl \
  git \
  libffi-dev \
  libgmp10 \
  libreadline-dev \
  libssl-dev \
  libvips42t64 \
  libyaml-dev \
  pkg-config \
  poppler-utils \
  postgresql-common \
  sudo \
  tesseract-ocr \
  zlib1g-dev

install -d /usr/share/postgresql-common/pgdg
if [[ ! -s /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc ]]; then
  curl --fail --show-error --location \
    -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
    https://www.postgresql.org/media/keys/ACCC4CF8.asc
fi

cat >/etc/apt/sources.list.d/pgdg.sources <<EOF
Types: deb
URIs: https://apt.postgresql.org/pub/repos/apt
Suites: ${VERSION_CODENAME}-pgdg
Architectures: amd64
Components: main
Signed-By: /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc
EOF

apt-get update
apt-get install -y --no-install-recommends \
  libpq-dev \
  postgresql-17 \
  postgresql-17-pgvector \
  postgresql-client-17

if [[ ! -x "${RUBY_PREFIX}/bin/ruby" ]] || ! "${RUBY_PREFIX}/bin/ruby" -e "abort unless RUBY_VERSION == '${RUBY_VERSION}'"; then
  tmp="$(mktemp)"
  curl --fail --show-error --location -o "${tmp}" "${RUBY_URL}"
  echo "${RUBY_SHA256}  ${tmp}" | sha256sum --check --strict
  rm -rf "${RUBY_PREFIX}"
  mkdir -p "${RUBY_PREFIX}"
  tar -xzf "${tmp}" -C "${RUBY_PREFIX}" --strip-components=1
  rm -f "${tmp}"
fi

# ruby-builder binstubs keep the GitHub Actions toolcache shebang.
mkdir -p "/opt/hostedtoolcache/Ruby/${RUBY_VERSION}"
ln -sfn "${RUBY_PREFIX}" "/opt/hostedtoolcache/Ruby/${RUBY_VERSION}/x64"

echo "${RUBY_PREFIX}/lib" >/etc/ld.so.conf.d/ruby.conf
ldconfig

for bin in ruby gem bundle bundler irb rake; do
  if [[ -e "${RUBY_PREFIX}/bin/${bin}" ]]; then
    ln -sfn "${RUBY_PREFIX}/bin/${bin}" "/usr/local/bin/${bin}"
  fi
done

gem install bundler -v 4.0.3 --no-document

if ! id ubuntu >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash --uid 1000 --user-group ubuntu
fi
usermod -aG sudo ubuntu
printf 'ubuntu ALL=(ALL) NOPASSWD:ALL\n' >/etc/sudoers.d/ubuntu
chmod 440 /etc/sudoers.d/ubuntu

install -d -o ubuntu -g ubuntu /usr/local/bundle

# Package install leaves the server running. Stop it so image layers and
# later snapshots capture a clean data directory. start.sh brings it back.
if pg_lsclusters --no-header | awk '$1 == "17" && $2 == "main" { found = 1 } END { exit !found }'; then
  pg_ctlcluster 17 main stop || true
fi

rm -rf /var/lib/apt/lists/*
