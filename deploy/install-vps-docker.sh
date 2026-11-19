#!/usr/bin/env bash
# One-shot installer: Docker + OpenWA (Docker Compose) on a fresh Ubuntu 22.04/24.04 or Debian 12 VPS.
# Run as root from the folder that contains this file:   sudo bash deploy/install-vps-docker.sh
# It does NOT set up HTTPS - do that afterwards (nginx or Caddy, see docs/deploy/01-vps-docker.md).
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/openwa}"
REPO_URL="${REPO_URL:-https://github.com/rmyndharis/OpenWA.git}"
REPO_REF="${REPO_REF:-}"          # optional tag/branch/commit to pin, e.g. REPO_REF=v0.30.3
HERE="$(cd "$(dirname "$0")" && pwd)"

[ "$(id -u)" = 0 ] || { echo "Run as root (sudo)." >&2; exit 1; }

echo "==> Checking resources"
mem_mb=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
[ "$mem_mb" -ge 1800 ] || echo "WARNING: only ${mem_mb} MB RAM. The image build needs ~2 GB; add swap or use a bigger VPS."

echo "==> Installing Docker (if missing)"
if ! command -v docker >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y ca-certificates curl git openssl
  curl -fsSL https://get.docker.com | sh
fi
apt-get install -y git openssl >/dev/null
docker compose version >/dev/null

echo "==> Fetching OpenWA into $INSTALL_DIR"
if [ ! -d "$INSTALL_DIR/.git" ]; then
  git clone "$REPO_URL" "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"
if [ -n "$REPO_REF" ]; then git fetch --tags origin && git checkout "$REPO_REF"; fi

echo "==> Writing config"
if [ ! -f .env ]; then
  cp "$HERE/.env.production.example" .env
  key=$(openssl rand -base64 48 | tr -d '\n=+/' | cut -c1-40)
  pepper=$(openssl rand -hex 32)
  sed -i "s|^API_MASTER_KEY=.*|API_MASTER_KEY=${key}|; s|^API_KEY_PEPPER=.*|API_KEY_PEPPER=${pepper}|" .env
  # Docker bridge NAT: trust the private ranges for X-Forwarded-For
  sed -i "s|^TRUSTED_PROXIES=.*|TRUSTED_PROXIES=172.16.0.0/12|" .env
  chmod 600 .env
  echo "    Generated API_MASTER_KEY and API_KEY_PEPPER in $INSTALL_DIR/.env"
  echo "    EDIT BASE_URL and CORS_ORIGINS in that file to your domain before going public."
fi
cp "$HERE/docker-compose.override.yml" docker-compose.override.yml

echo "==> Building and starting (first build takes 5-15 minutes)"
docker compose up -d --build

echo "==> Waiting for health"
for i in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:2785/api/health >/dev/null 2>&1; then ok=1; break; fi
  sleep 5
done
[ "${ok:-0}" = 1 ] && echo "OpenWA is up on 127.0.0.1:2785" || { echo "Not healthy yet. Check: docker compose logs -f openwa-api"; exit 1; }

echo
echo "Admin API key is the API_MASTER_KEY value in $INSTALL_DIR/.env  (keep it secret)."
echo "Next: put HTTPS in front (docs/deploy/01-vps-docker.md, step 6)."
