
#!/usr/bin/env bash
set -euo pipefail

# Non-root friendly installer for Secure E‑Sign Vault MVP
# Usage: ./scripts/install.sh yourdomain.com admin@yourdomain.com

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <domain> <admin-email>"
  exit 1
fi

DOMAIN="$1"
ADMIN_EMAIL="$2"

# Ensure docker & compose plugin
if ! command -v docker &>/dev/null; then
  echo "[INFO] Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER" || true
fi
if ! docker compose version &>/dev/null; then
  echo "[INFO] Installing docker compose plugin..."
  sudo apt-get update && sudo apt-get install -y docker-compose-plugin
fi

# Create .env if missing
if [ ! -f .env ]; then
  echo "[INFO] Creating .env from example"
  cp .env.example .env
  sed -i "s/yourdomain.com/$DOMAIN/g" .env
  # generate secrets
  JWT=$(openssl rand -base64 32)
  PGPASS=$(openssl rand -base64 16)
  sed -i "s/JWT_SECRET=.*/JWT_SECRET=$JWT/" .env
  sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$PGPASS/" .env
  sed -i "s/PLATFORM_ADMIN_EMAIL=.*/PLATFORM_ADMIN_EMAIL=$ADMIN_EMAIL/" .env
  sed -i "s/PLATFORM_ADMIN_PWD=.*/PLATFORM_ADMIN_PWD=$(openssl rand -base64 14)/" .env
fi

echo "[INFO] Building and starting containers..."
docker compose up -d --build

# Basic wait for Postgres
echo "[INFO] Waiting for Postgres..."
for i in {1..60}; do
  if docker exec -i $(docker ps -q -f ancestor=postgres:15) pg_isready -U $(grep POSTGRES_USER .env | cut -d= -f2) &>/dev/null; then
    echo "[OK] Postgres ready"; break
  fi
  sleep 2
done

# Run backend migrations (the API supports --migrate --seed in Program.cs)
echo "[INFO] Running migrations & seed ..."
docker compose exec api /bin/sh -lc "dotnet SecureSign.Api.dll --migrate --seed" || true

# TLS via certbot (optional; requires DNS ready)
echo "[INFO] Installing certbot (optional TLS)"
sudo apt-get update && sudo apt-get install -y certbot python3-certbot-nginx || true
sudo certbot --nginx -d $DOMAIN -d api.$DOMAIN -d app.$DOMAIN --non-interactive --agree-tos -m $ADMIN_EMAIL || true

echo "[OK] Install complete. Web on https://$DOMAIN (after DNS/SSL), API /api/health"
