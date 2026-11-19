# WhatsApp-SRV

Deployment kit for a self-hosted WhatsApp API gateway based on [OpenWA](https://github.com/rmyndharis/OpenWA) (MIT).
This repo does **not** vendor OpenWA; the installers fetch it from upstream, so you can update by pulling a new tag.

> OpenWA uses unofficial WhatsApp protocols. Use a dedicated number, expect a non-zero ban risk, and use Meta's
> Cloud API for regulated or business-critical messaging.

## Pick your path

| Where | Guide |
|---|---|
| Decide first | [docs/deploy/00-choose-your-path.md](docs/deploy/00-choose-your-path.md) |
| **VPS, Docker (recommended)** | [docs/deploy/01-vps-docker.md](docs/deploy/01-vps-docker.md) |
| VPS, no Docker (systemd) | [docs/deploy/02-vps-bare-metal-systemd.md](docs/deploy/02-vps-bare-metal-systemd.md) |
| cPanel/WHM **with root** | [docs/deploy/03-cpanel-whm-root.md](docs/deploy/03-cpanel-whm-root.md) |
| cPanel shared, **no root** (+ Hybrid) | [docs/deploy/04-cpanel-shared-no-root.md](docs/deploy/04-cpanel-shared-no-root.md) |
| Backups, updates, security | [docs/deploy/05-operations-backup-update-security.md](docs/deploy/05-operations-backup-update-security.md) |

## Quick start (fresh Ubuntu/Debian VPS)

```bash
git clone <this repo> /root/WhatsApp-SRV && cd /root/WhatsApp-SRV
sudo bash deploy/install-vps-docker.sh
```

Then add HTTPS (guide 01, step 6) and link a number (step 7).

## Contents of `deploy/`

| File | Purpose |
|---|---|
| `.env.production.example` | Hardened production settings with secrets to generate |
| `docker-compose.override.yml` | Disables Docker socket proxy, sets memory limit |
| `install-vps-docker.sh` | One-shot Docker installer |
| `systemd/openwa.service` | Bare-metal service unit |
| `nginx/openwa.conf`, `caddy/Caddyfile` | HTTPS reverse proxy |
| `cpanel/apache-openwa-ssl.conf` | WHM Apache proxy include (root) |
| `cpanel/preflight.sh`, `app.js`, `keepalive.sh` | Shared-hosting feasibility check and Passenger entry (no root) |
| `php/openwa-client.php` | cURL client for sites on cPanel calling OpenWA remotely |
