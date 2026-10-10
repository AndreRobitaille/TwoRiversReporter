#!/usr/bin/env bash
# Idempotent repository bootstrap. Installs gems and prepares the development
# and test databases. Postgres is started only for that work and then stopped;
# .cursor/start.sh starts it again on each agent boot.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

required="$(tr -d '[:space:]' < .ruby-version)"
required="${required#ruby-}"

if ! command -v ruby >/dev/null 2>&1 || ! command -v psql >/dev/null 2>&1 || ! ruby -e "exit(RUBY_VERSION == '${required}' ? 0 : 1)"; then
  sudo bash "${ROOT}/.cursor/bootstrap-system.sh"
fi

hash -r
actual="$(ruby -e 'print RUBY_VERSION')"
if [[ "${actual}" != "${required}" ]]; then
  echo "Ruby ${actual} does not match .ruby-version (${required})." >&2
  exit 1
fi

if ! bundle _4.0.3_ -v >/dev/null 2>&1; then
  gem install bundler -v 4.0.3 --no-document
fi

if [[ ! -w /usr/local/bundle ]]; then
  sudo install -d -o "$(id -u)" -g "$(id -g)" /usr/local/bundle
fi

bundle config set --global path /usr/local/bundle
bundle config set --global jobs "$(nproc)"
bundle _4.0.3_ check || bundle _4.0.3_ install

bash "${ROOT}/.cursor/start.sh"

for control in pg_trgm vector; do
  if [[ ! -f "/usr/share/postgresql/17/extension/${control}.control" ]]; then
    echo "PostgreSQL extension ${control} is not installed." >&2
    exit 1
  fi
done

bin/rails db:prepare
RAILS_ENV=test bin/rails db:prepare

for db in two_rivers_reporter_development two_rivers_reporter_test; do
  psql -d "${db}" -v ON_ERROR_STOP=1 -c "CREATE EXTENSION IF NOT EXISTS vector;"
  psql -d "${db}" -v ON_ERROR_STOP=1 -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"
done

if pg_isready -q; then
  sudo pg_ctlcluster 17 main stop
fi
