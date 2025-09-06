
#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 "Tenant Name" tenant-slug [plan]"
  exit 1
fi
TENANT_NAME="$1"
TENANT_SLUG="$2"
PLAN="${3:-free}"

TENANT_ID=$(python3 - <<PY
import uuid; print(uuid.uuid4())
PY
)
TDK=$(openssl rand -hex 32)

# Pull DB creds from .env
set -a
. .env
set +a

echo "[INFO] Creating tenant $TENANT_NAME ($TENANT_ID), plan=$PLAN"
docker exec -i $(docker ps -q -f ancestor=postgres:15) psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} <<SQL
INSERT INTO tenants (id, name, slug, plan, created_at, ksm_material)
VALUES ('${TENANT_ID}', '${TENANT_NAME}', '${TENANT_SLUG}', '${PLAN}', now(), '${TDK}');
SQL

echo "[OK] Tenant created. TENANT_ID=$TENANT_ID"
echo "[SECURE] Tenant Data Key (TDK) = $TDK"
