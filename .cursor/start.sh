#!/usr/bin/env bash
# Per-boot Postgres startup. Safe to run when the cluster is already up.
set -euo pipefail

if ! command -v pg_isready >/dev/null 2>&1 || ! command -v pg_ctlcluster >/dev/null 2>&1; then
  echo "PostgreSQL 17 client tools are missing. Run .cursor/install.sh first." >&2
  exit 1
fi

if ! pg_lsclusters --no-header | awk '$1 == "17" && $2 == "main" { found = 1 } END { exit !found }'; then
  echo "PostgreSQL cluster 17/main is not installed." >&2
  exit 1
fi

if ! pg_isready -q; then
  sudo pg_ctlcluster 17 main start
fi

ready=0
for _ in $(seq 1 30); do
  if pg_isready -q; then
    ready=1
    break
  fi
  sleep 1
done

if [[ "${ready}" -ne 1 ]]; then
  echo "PostgreSQL 17 did not become ready." >&2
  sudo tail -n 40 /var/log/postgresql/postgresql-17-main.log >&2 || true
  exit 1
fi

db_user="$(id -un)"
if [[ ! "${db_user}" =~ ^[a-z_][a-z0-9_]*$ ]]; then
  echo "Unsupported database role name: ${db_user}" >&2
  exit 1
fi

# Peer auth maps the OS user to a role of the same name. database.yml leaves
# username blank, so Rails connects as this user over the local socket.
sudo -u postgres psql -v ON_ERROR_STOP=1 -d postgres <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${db_user}') THEN
    CREATE ROLE ${db_user} WITH LOGIN SUPERUSER CREATEDB;
  ELSE
    ALTER ROLE ${db_user} WITH LOGIN SUPERUSER CREATEDB;
  END IF;
END
\$\$;
SQL
