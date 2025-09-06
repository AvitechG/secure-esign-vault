\#!/bin/bash

# =============================================

# Secure E-Sign Vault — One-Click Installer

# =============================================

# Supports: Local & VPS deployments

# Deploys to: 192.168.10.194

# =============================================

set -e

# ---------------------------

# CONFIGURATION

# ---------------------------

APP\_NAME="secure-esign-vault"
LOCAL\_IP="192.168.10.194"
DEPLOY\_DIR="\$HOME/\$APP\_NAME"

# ---------------------------

# PREPARE ENVIRONMENT

# ---------------------------

echo "\n🔧 Preparing environment..."
sudo apt update && sudo apt install -y curl git docker.io docker-compose npm nodejs

# Ensure Docker is running

sudo systemctl enable docker
sudo systemctl start docker

# Create non-root Docker group

sudo groupadd docker || true
sudo usermod -aG docker \$USER
newgrp docker <\<EONG

# ---------------------------

# CLONE REPO

# ---------------------------

if \[ ! -d "\$DEPLOY\_DIR" ]; then
echo "\n📥 Cloning repository..."
git clone [https://github.com/AvitechG/secure-esign-vault.git](https://github.com/AvitechG/secure-esign-vault.git) "\$DEPLOY\_DIR"
fi

cd "\$DEPLOY\_DIR"

# ---------------------------

# BUILD FRONTEND LOCALLY

# ---------------------------

echo "\n⚡ Building React web app..."
cd web
npm install
npm run build || { echo "❌ React build failed! Check logs."; exit 1; }
cd ..

# ---------------------------

# START DOCKER COMPOSE

# ---------------------------

echo "\n🐳 Starting Docker stack..."
docker compose down --volumes --remove-orphans
docker compose build --no-cache
docker compose up -d

# ---------------------------

# AUTOMATED DATABASE BACKUPS

# ---------------------------

echo "\n💾 Setting up automated DB backups..."
mkdir -p "\$DEPLOY\_DIR/backups"
(crontab -l 2>/dev/null; echo "0 2 \* \* \* docker exec postgres pg\_dumpall -U postgres > \$DEPLOY\_DIR/backups/db\_\$(date +%F).sql") | crontab -

# ---------------------------

# HEALTH CHECK

# ---------------------------

echo "\n🔍 Running health check..."
sleep 10
curl -s http\://\$LOCAL\_IP:8080/api/health || echo "⚠️ API health check failed"

# ---------------------------

# DONE!

# ---------------------------

echo "\n✅ Deployment complete!"
echo "🌐 Web App:      http\://\$LOCAL\_IP:5173"
echo "📡 API Health:   http\://\$LOCAL\_IP:8080/api/health"
echo "💾 MinIO Panel:  http\://\$LOCAL\_IP:9001"

echo "\n🚀 Use the app locally or configure DNS later."
EONG
