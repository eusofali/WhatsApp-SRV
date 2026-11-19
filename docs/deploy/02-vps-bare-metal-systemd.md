# 02 · VPS without Docker (Node + systemd)

Use this if Docker is not allowed or you want the smallest footprint. Ubuntu 22.04+/Debian 12+ (glibc ≥ 2.34 is
required by the bundled SQLite binary). Docker (guide 01) is simpler and gets Chromium patched for you; choose this
only with a reason.

## Step 1 · Server basics

Do guide 01 **steps 1–2** (updates, swap, firewall, DNS).

## Step 2 · Install Node 22 and build tools

```bash
apt -y install curl git build-essential python3 openssl ca-certificates
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt -y install nodejs
node -v          # must be >= 22.19
```

## Step 3 · Chromium libraries (only for `whatsapp-web.js`; skip for Baileys)

```bash
apt -y install fonts-liberation libasound2t64 libatk-bridge2.0-0 libatk1.0-0 libcups2 libdrm2 libgbm1 \
  libgtk-3-0 libnspr4 libnss3 libxcomposite1 libxdamage1 libxfixes3 libxkbcommon0 libxrandr2 xdg-utils
# On Debian 12 / Ubuntu 22.04 the package is libasound2 (not libasound2t64).
```

The Puppeteer-bundled Chrome is downloaded during `npm ci`. If your CPU is ARM, install `chromium` from apt and set
`PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium` in `.env`.

## Step 4 · Create a service user and fetch OpenWA

```bash
useradd --system --create-home --shell /usr/sbin/nologin openwa
git clone https://github.com/rmyndharis/OpenWA.git /opt/openwa
cd /opt/openwa && git tag --list | tail      # optionally: git checkout <tag>
```

## Step 5 · Configure

```bash
cp /root/WhatsApp-SRV/deploy/.env.production.example /opt/openwa/.env
# generate secrets
sed -i "s|^API_MASTER_KEY=.*|API_MASTER_KEY=$(openssl rand -base64 48 | tr -d '\n=+/' | cut -c1-40)|" /opt/openwa/.env
sed -i "s|^API_KEY_PEPPER=.*|API_KEY_PEPPER=$(openssl rand -hex 32)|" /opt/openwa/.env
nano /opt/openwa/.env       # BASE_URL, CORS_ORIGINS, ENGINE_TYPE
chmod 600 /opt/openwa/.env
```

`TRUSTED_PROXIES=127.0.0.1` (already the default in the example) is right here because the proxy is on the same host.

## Step 6 · Build (5–10 min, needs ~2 GB RAM)

```bash
cd /opt/openwa
npm ci                 # also runs OpenWA's postinstall patches + installs dashboard deps
npm run build:all      # builds API (dist/) and dashboard
mkdir -p data && chown -R openwa:openwa /opt/openwa
```

## Step 7 · systemd service

```bash
cp /root/WhatsApp-SRV/deploy/systemd/openwa.service /etc/systemd/system/openwa.service
systemctl daemon-reload
systemctl enable --now openwa
systemctl status openwa --no-pager
journalctl -u openwa -f          # live logs, Ctrl+C to exit
curl -s http://127.0.0.1:2785/api/health
```

## Step 8 · HTTPS and linking

Continue with guide 01 **step 6** (Caddy or nginx), then **step 7** (link a number).

## Updating

```bash
cd /opt/openwa && sudo -u openwa git fetch --tags && sudo -u openwa git checkout <new-tag>
sudo -u openwa npm ci && sudo -u openwa npm run build:all
systemctl restart openwa
```

Always back up first ([05](05-operations-backup-update-security.md#backups)).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `GLIBC_2.34 not found` | OS too old. Upgrade OS or use Docker |
| `nest: not found` | Dev deps skipped: run `NODE_ENV=development npm ci` then `build:all` |
| Chromium "No usable sandbox" / launch fail | Install libs in step 3; the app already passes `--no-sandbox` |
| Service flaps | `journalctl -u openwa -n 100`; check `MemoryMax` in the unit (raise for many sessions) |
