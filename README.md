
# Secure E‑Sign Vault — MVP

This is a minimal, dockerized, multi-tenant SaaS MVP for a secure e-sign + document vault.
Stack:
- Backend: ASP.NET Core (C#) Minimal API
- Web: React + Vite + Tailwind (lite)
- DB: PostgreSQL
- Cache/Jobs: Redis (placeholder)
- Object Storage: MinIO (S3-compatible)
- Reverse Proxy: Nginx
- Install/Backup: scripts/install.sh, scripts/backup.sh

## Quick start (local/dev)
```bash
cp .env.example .env
docker compose up --build -d
```

Web UI: http://localhost:5173  
API: http://localhost:8080/api/health
MinIO: http://localhost:9001 (console)
Postgres: localhost:5432 (user/pass from .env)

## Production (VPS)
Use `scripts/install.sh` (non-root friendly). It installs Docker (if needed), brings up the stack,
obtains Let's Encrypt certs (if domain points to the server), and sets up encrypted backups.
