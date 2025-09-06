
#!/usr/bin/env bash
set -euo pipefail

BASE="/opt/secure-esign-vault"
[ -d "$BASE" ] || BASE="$(pwd)"
BACKDIR="$BASE/backups"
mkdir -p "$BACKDIR"

DATE=$(date +%F_%H-%M)
TMP="$BACKDIR/tmp_$DATE"
mkdir -p "$TMP"

# Load .env for DB creds
set -a
. "$BASE/.env"
set +a

echo "[INFO] Dumping Postgres..."
docker exec $(docker ps -q -f ancestor=postgres:15) pg_dump -U ${POSTGRES_USER} ${POSTGRES_DB} > "$TMP/db.sql"

echo "[INFO] Saving Redis snapshot..."
docker exec $(docker ps -q -f ancestor=redis:7) redis-cli save || true
docker cp $(docker ps -q -f ancestor=redis:7):/data/dump.rdb "$TMP/redis.rdb" || true

ARCHIVE="$BACKDIR/backup_$DATE.tar.gz"
tar -C "$TMP" -czf "$ARCHIVE" .
rm -rf "$TMP"

echo "[INFO] Backup at $ARCHIVE"
# retention: keep last 14
ls -1t "$BACKDIR"/backup_*.tar.gz | awk 'NR>14' | xargs -r rm -f
