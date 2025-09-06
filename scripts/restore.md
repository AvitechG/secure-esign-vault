
# Restore Guide

1) Pick a backup file: `backups/backup_YYYY-MM-DD_HH-MM.tar.gz`
2) Extract:
```bash
tar -xzf backups/backup_*.tar.gz -C /tmp/restore/
```
3) Restore Postgres:
```bash
docker exec -i $(docker ps -q -f ancestor=postgres:15) psql -U securesign securesign < /tmp/restore/db.sql
```
4) Restore Redis (optional):
```bash
docker cp /tmp/restore/redis.rdb $(docker ps -q -f ancestor=redis:7):/data/dump.rdb
docker restart $(docker ps -q -f ancestor=redis:7)
```
