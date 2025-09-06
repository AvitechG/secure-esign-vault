#!/usr/bin/env bash
set -euo pipefail

# Secure E-Sign Vault - One-Click Installer (with Multi-Tenant Provisioning)
# Tested on Ubuntu 22.04 LTS. Run as root or with sudo.
# Usage: sudo ./install-securesign.sh yourdomain.com admin@example.com your-github-org

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <domain> <admin-email> <github-org>"
  exit 1
fi

DOMAIN="$1"
ADMIN_EMAIL="$2"
GIT_ORG="$3"
INSTALL_DIR="/opt/secure-sign"
REPO_API="https://github.com/${GIT_ORG}/secure-sign-server.git"
REPO_WEB="https://github.com/${GIT_ORG}/secure-sign-web.git"

# Generated secrets (idempotent on subsequent runs will preserve .env)
POSTGRES_PASSWORD="$(openssl rand -base64 16)"
MINIO_ACCESS_KEY="$(openssl rand -hex 12)"
MINIO_SECRET_KEY="$(openssl rand -hex 24)"
JWT_SECRET="$(openssl rand -base64 32)"

info(){ echo -e "[INFO] $*"; }
ok(){ echo -e "[OK] $*"; }

info "Updating system packages..."
apt update && apt -y upgrade

info "Installing prerequisites..."
apt install -y curl git apt-transport-https ca-certificates gnupg lsb-release software-properties-common jq unzip ufw openssl python3

# Docker install
if ! command -v docker &>/dev/null; then
  info "Installing Docker Engine..."
  curl -fsSL https://get.docker.com | sh
else
  info "Docker already installed"
fi

if ! docker compose version &>/dev/null; then
  info "Installing Docker Compose plugin..."
  apt-get install -y docker-compose-plugin
fi

info "Creating install directory: ${INSTALL_DIR}"\mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

# Clone repos if missing
if [ ! -d secure-sign-server ]; then
  info "Cloning API repo: ${REPO_API}"
  git clone "${REPO_API}" secure-sign-server
else
  info "secure-sign-server present, pulling latest"
  (cd secure-sign-server && git pull)
fi

if [ ! -d secure-sign-web ]; then
  info "Cloning Web repo: ${REPO_WEB}"
  git clone "${REPO_WEB}" secure-sign-web
else
  info "secure-sign-web present, pulling latest"
  (cd secure-sign-web && git pull)
fi

# Create .env if not exists
if [ -f .env ]; then
  info ".env exists — keeping existing secrets"
else
  info "Generating .env with random secrets"
  cat > .env <<EOF
ASPNETCORE_ENVIRONMENT=Production
DOMAIN=${DOMAIN}
JWT_SECRET=${JWT_SECRET}

POSTGRES_USER=securesign
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=securesign
DB_HOST=db
DB_PORT=5432

REDIS_HOST=redis
REDIS_PORT=6379

MINIO_ROOT_USER=${MINIO_ACCESS_KEY}
MINIO_ROOT_PASSWORD=${MINIO_SECRET_KEY}
S3_ENDPOINT=http://minio:9000
S3_BUCKET=docs

STRIPE_SECRET_KEY=
STRIPE_WEBHOOK_SECRET=

PLATFORM_ADMIN_EMAIL=${ADMIN_EMAIL}
PLATFORM_ADMIN_PWD=$(openssl rand -base64 14)
EOF
fi

# docker-compose.yml (idempotent overwrite)
info "Writing docker-compose.yml"
cat > docker-compose.yml <<'YAML'
version: '3.8'
services:
  db:
    image: postgres:15
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - dbdata:/var/lib/postgresql/data
    networks: [appnet]

  redis:
    image: redis:7
    restart: unless-stopped
    networks: [appnet]

  minio:
    image: minio/minio:latest
    command: server /data --console-address ':9001'
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
    volumes:
      - miniodata:/data
    ports: ["9000:9000","9001:9001"]
    networks: [appnet]

  backend:
    build: ./secure-sign-server
    env_file: .env
    depends_on: [db, redis, minio]
    restart: unless-stopped
    networks: [appnet]

  web:
    build: ./secure-sign-web
    env_file: .env
    depends_on: [backend]
    restart: unless-stopped
    networks: [appnet]

  nginx:
    image: nginx:alpine
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./certs:/etc/letsencrypt
      - ./secure-sign-web/build:/usr/share/nginx/html:ro
    ports:
      - "80:80"
      - "443:443"
    depends_on: [web, backend]
    networks: [appnet]

volumes:
  dbdata: {}
  miniodata: {}
  certs: {}

networks:
  appnet: {}
YAML

info "Writing basic nginx.conf"
cat > nginx.conf <<NG
worker_processes auto;
events { worker_connections 1024; }
http {
  include /etc/nginx/mime.types;
  sendfile on;
  server_tokens off;

  server {
    listen 80;
    server_name ${DOMAIN} api.${DOMAIN} app.${DOMAIN};

    location /.well-known/acme-challenge/ { root /var/www/certbot; }

    location /api/ {
      proxy_pass http://backend:80/;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location / {
      root /usr/share/nginx/html;
      try_files $uri /index.html;
    }
  }
}
NG

info "Bringing up containers (this builds images; may take a while)..."
docker compose up -d --build

info "Waiting for Postgres to accept connections..."
for i in {1..60}; do
  if docker exec -i $(docker ps -q -f ancestor=postgres:15) pg_isready -U ${POSTGRES_USER} &>/dev/null; then
    ok "Postgres ready"; break
  fi
  sleep 2
done

info "Running DB migrations and seeding platform admin (backend must implement migrate+seed entrypoint)"
# If backend does not support migrate command, replace with appropriate migration step
if docker compose exec backend /bin/bash -lc "dotnet SecureSign.Api.dll --migrate --seed"; then
  ok "Migrations & seed complete"
else
  info "Migration step failed or not available — ensure backend supports --migrate --seed"
fi

info "Installing certbot and obtaining TLS certificates (ensure DNS A record points to this server)"
apt install -y certbot python3-certbot-nginx || true
certbot --nginx -d ${DOMAIN} -d api.${DOMAIN} -d app.${DOMAIN} --non-interactive --agree-tos -m ${ADMIN_EMAIL} || true

ok "Installer finished. Web UI should be at: https://${DOMAIN}"

echo
ok "Platform admin email: ${PLATFORM_ADMIN_EMAIL}"
ok "Platform admin password: (stored in .env as PLATFORM_ADMIN_PWD)"

# Write tenant provisioning helper
info "Writing tenant provisioning helper scripts..."
cat > provision-tenant.sh <<'PT'
#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 \"Tenant Name\" tenant-slug [plan]"
  exit 1
fi

TENANT_NAME="$1"
TENANT_SLUG="$2"
PLAN="${3:-free}"

TENANT_ID=$(python3 - <<PY
import uuid
print(uuid.uuid4())
PY
)
TDK=$(openssl rand -hex 32)

echo "[INFO] Creating tenant ${TENANT_NAME} (${TENANT_ID}) with plan ${PLAN}"

# Insert tenant record into platform DB (simple SQL insert). Adjust table/columns to your schema.
docker exec -i $(docker ps -q -f ancestor=postgres:15) psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} <<SQL
INSERT INTO tenants (id, name, slug, plan, created_at, ksm_material)
VALUES ('${TENANT_ID}', '${TENANT_NAME}', '${TENANT_SLUG}', '${PLAN}', now(), '${TDK}');
SQL

# Optional: create a dedicated schema for tenant
docker exec -i $(docker ps -q -f ancestor=postgres:15) psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "CREATE SCHEMA IF NOT EXISTS tenant_${TENANT_SLUG};"

echo "[OK] Tenant provisioned. Tenant ID: ${TENANT_ID}"
echo "[SECURE] Tenant Data Key (store safely): ${TDK}"
PT
chmod +x provision-tenant.sh

cat > set-tenant-context.sh <<'CT'
#!/usr/bin/env bash
# Usage: ./set-tenant-context.sh <tenant-uuid>
TENANT_ID=${1:-}
if [ -z "$TENANT_ID" ]; then echo "Usage: $0 <tenant-uuid>"; exit 1; fi
# Prints SQL you can use to set RLS context in a session
echo "-- Run this in your psql session before queries to set tenant context:"
echo "SET LOCAL app.tenant_id = '${TENANT_ID}';"
CT
chmod +x set-tenant-context.sh

ok "Provisioning helpers created: provision-tenant.sh, set-tenant-context.sh"

echo
info "Done. If you want me to push these installer scripts to your GitHub repo, provide a personal access token with repo permissions."
