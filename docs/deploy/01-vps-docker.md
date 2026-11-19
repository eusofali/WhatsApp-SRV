# 01 · VPS with Docker (recommended)

Tested path: Ubuntu 22.04/24.04 or Debian 12, root or sudo. About 20 minutes plus build time.
OpenWA's own image already bundles Node 22, Chromium and all patches, so this avoids every version problem.

## Step 1 · Prepare the server

```bash
ssh root@YOUR_SERVER_IP
apt update && apt -y upgrade
timedatectl set-timezone UTC
```

**Add swap if RAM ≤ 2 GB** (the image build is memory hungry):

```bash
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

**Firewall**: only SSH, HTTP, HTTPS. OpenWA's port 2785 is bound to `127.0.0.1` and must never be public.

```bash
apt -y install ufw
ufw default deny incoming && ufw default allow outgoing
ufw allow OpenSSH && ufw allow 80/tcp && ufw allow 443/tcp
ufw --force enable
```

(Optional but wise: a non-root sudo user, SSH keys only, `fail2ban`.)

## Step 2 · Point your domain

Create a DNS **A record** `wa.example.com → YOUR_SERVER_IP`. Wait until `dig +short wa.example.com` shows the IP.

## Step 3 · Get this repo on the server and run the installer

```bash
apt -y install git
git clone <YOUR WhatsApp-SRV REPO URL> /root/WhatsApp-SRV
cd /root/WhatsApp-SRV
sudo bash deploy/install-vps-docker.sh
```

What it does: installs Docker, clones OpenWA to `/opt/openwa`, writes `/opt/openwa/.env` with a **random admin key and
pepper**, installs the compose override (disables the Docker socket proxy), builds, starts, and waits for health.

Pin a specific release instead of the latest main:

```bash
cd /opt/openwa && git tag --list | tail      # pick a tag you have read the changelog for
REPO_REF=<tag> sudo -E bash /root/WhatsApp-SRV/deploy/install-vps-docker.sh
```

## Step 4 · Edit the configuration

```bash
nano /opt/openwa/.env
```

Set at least:

| Key | Value |
|---|---|
| `BASE_URL` | `https://wa.example.com` |
| `CORS_ORIGINS` | `https://wa.example.com` (plus any browser app that calls the API) |
| `ENGINE_TYPE` | `whatsapp-web.js` (lower ban risk) or `baileys` (light on RAM) |
| `MAX_CONCURRENT_SESSIONS` | `2` on a 2 GB server |

Apply: `cd /opt/openwa && docker compose up -d`.

> Never edit `API_MASTER_KEY` or `API_KEY_PEPPER` after the first boot. They are read only when the key table is
> empty; changing the pepper later locks out every key.

## Step 5 · Check it locally

```bash
docker compose -f /opt/openwa/docker-compose.yml ps
curl -s http://127.0.0.1:2785/api/health
docker compose -f /opt/openwa/docker-compose.yml logs --tail=50 openwa-api
```

## Step 6 · HTTPS reverse proxy

Pick **one**.

### Option A: Caddy (easiest, automatic certificates)

```bash
apt -y install debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy.list
apt update && apt -y install caddy
cp /root/WhatsApp-SRV/deploy/caddy/Caddyfile /etc/caddy/Caddyfile
nano /etc/caddy/Caddyfile            # replace wa.example.com
systemctl reload caddy
```

### Option B: nginx + Certbot

```bash
apt -y install nginx certbot python3-certbot-nginx
cp /root/WhatsApp-SRV/deploy/nginx/openwa.conf /etc/nginx/sites-available/openwa.conf
sed -i 's/wa.example.com/YOUR.DOMAIN/g' /etc/nginx/sites-available/openwa.conf
ln -s /etc/nginx/sites-available/openwa.conf /etc/nginx/sites-enabled/
# first get the certificate (the config references it, so temporarily comment the 443 block or run):
certbot certonly --nginx -d YOUR.DOMAIN
nginx -t && systemctl reload nginx
```

Since the reverse proxy reaches Docker through the bridge NAT, the installer already set
`TRUSTED_PROXIES=172.16.0.0/12` so client IPs are read correctly.

Verify from your laptop: `curl https://wa.example.com/api/health`.

## Step 7 · Link a WhatsApp number

1. Open `https://wa.example.com`, log in with the key (`grep API_MASTER_KEY /opt/openwa/.env`).
2. **Sessions → New session**, start it, scan the QR in WhatsApp → *Linked devices*.
3. Within 5 minutes, open the session in the dashboard and acknowledge any "What's new" prompt (the
   whatsapp-web.js engine clicks it automatically).
4. Send a test message from the dashboard, or by API:

```bash
curl -X POST https://wa.example.com/api/sessions/SESSION_ID/messages/send-text \
  -H "X-API-Key: YOUR_KEY" -H "Content-Type: application/json" \
  -d '{"chatId":"15551234567@c.us","text":"hello"}'
```

## Step 8 · Survive reboots, then lock it down

`restart: unless-stopped` and Docker's systemd unit already restart it. Test once: `reboot`, wait 2 minutes, run the
health check. Then read [05 · Operations](05-operations-backup-update-security.md): backups, updates, key rotation,
monitoring.

## Troubleshooting (quick)

| Symptom | Fix |
|---|---|
| Build killed / `exit 137` | Out of memory: add swap, or build elsewhere |
| 502 from proxy | `docker compose logs openwa-api`; is it healthy? Is the proxy pointing at `127.0.0.1:2785`? |
| 413 on media | Proxy `client_max_body_size` smaller than 25 MB |
| `Code: null` / Chromium dies with many sessions | Raise `OPENWA_PIDS_LIMIT`, `OPENWA_MEM_LIMIT` |
| Session asks for QR again after restart | Data volume lost; never `docker compose down -v` |
| `401 Invalid API key` | Pasted extra characters, or pepper changed after first boot |
