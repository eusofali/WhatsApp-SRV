# 04 · cPanel shared hosting (no root)

**Read this first.** OpenWA was not designed for shared hosting. This guide gives you (1) a one-minute test that
tells you whether it can run, (2) the best-effort install if the test passes, and (3) the **Hybrid** setup that
works on any cPanel account and is what we recommend.

## Step 1 · Pre-flight check (1 minute)

In cPanel open **Terminal** (or SSH, if the host enables it), then:

```bash
git clone <YOUR WhatsApp-SRV REPO URL> ~/WhatsApp-SRV
bash ~/WhatsApp-SRV/deploy/cpanel/preflight.sh
```

It checks: Node ≥ 22.19, glibc ≥ 2.34, process/memory limits, and outbound access to WhatsApp.

- **Any `[X]`** → go straight to [Hybrid](#hybrid-recommended-for-shared-hosting).
- **All `[ok]`** → continue to Step 2. Expect it to be fragile (see "Limits" at the end).

No Terminal at all? You cannot build or run OpenWA; use Hybrid.

## Step 2 · Install Node 22 via cPanel

1. cPanel → **Setup Node.js App** (CloudLinux Node.js Selector). Not shown → your host does not offer it → Hybrid.
2. **Create Application**: Node.js version **22.x** (anything < 22.19 will not work), mode **Production**,
   application root `openwa`, application URL `wa.example.com` (create this subdomain first under *Domains*),
   startup file `app.js`.
3. Copy the "Enter to the virtual environment" command shown on that page and run it in Terminal. It looks like
   `source /home/USER/nodevenv/openwa/22/bin/activate && cd /home/USER/openwa`. Check `node -v`.

## Step 3 · Build OpenWA (do this on your own computer if the host is small)

Building needs ~2 GB RAM, which shared accounts rarely allow. **Build locally** on Linux x64 (WSL2 on Windows is fine)
with the same Node 22, then upload the result:

```bash
git clone https://github.com/rmyndharis/OpenWA.git && cd OpenWA
PUPPETEER_SKIP_DOWNLOAD=true npm ci
npm run build:all
npm prune --omit=dev
tar czf openwa-build.tgz dist dashboard/dist node_modules package.json package-lock.json scripts
```

Upload `openwa-build.tgz` with **File Manager** into `~/openwa`, extract it (right-click → Extract), then copy
`deploy/cpanel/app.js` from this repo into `~/openwa/app.js`.

> `node_modules` contains compiled binaries (SQLite). It only runs on a host with the same OS family/glibc as the
> machine that built it. If you get `invalid ELF header` or `GLIBC_x not found`, build on the host itself
> (`npm ci` inside the Node.js Selector virtualenv) or use Hybrid.

## Step 4 · Configure

In **Setup Node.js App → Environment variables** add the values from `deploy/.env.production.example`. Minimum:

| Name | Value |
|---|---|
| `NODE_ENV` | `production` |
| `ENGINE_TYPE` | `baileys` (**required**: no Chromium on shared hosting) |
| `API_MASTER_KEY` | 32+ random chars (`openssl rand -base64 48`) |
| `API_KEY_PEPPER` | random hex (set before first start) |
| `BASE_URL` | `https://wa.example.com` |
| `CORS_ORIGINS` | `https://wa.example.com` |
| `MAX_CONCURRENT_SESSIONS` | `1` |
| `TRUSTED_PROXIES` | leave empty until you know your proxy IP |

Keep `data/` **outside** `public_html` (the app root `~/openwa` is outside it, which is right).

## Step 5 · Start and enable HTTPS

1. Click **Run JS install** is *not* needed (we uploaded `node_modules`); click **Restart** instead.
2. cPanel → **SSL/TLS Status → Run AutoSSL** so `wa.example.com` has HTTPS.
3. Test: `https://wa.example.com/api/health`. Check `~/openwa/data/` is created and the log in Setup Node.js App.

## Step 6 · Keep it alive (the hard part)

Passenger stops idle apps, which **disconnects WhatsApp**. Options, from best to worst:

1. **Ask the host** to keep the app "always on" (some LiteSpeed/CloudLinux plans have it).
2. **Wake-up cron** that pings the site every minute, which keeps Passenger from idling it:
   cPanel → **Cron Jobs** → `* * * * *` → `curl -fsS https://wa.example.com/api/health >/dev/null 2>&1`
3. **Self-supervising cron** (only if your terms allow background processes): `deploy/cpanel/keepalive.sh`
   starts Node with `nohup` when it is not running. Copy it to `~/openwa/keepalive.sh`, `chmod +x`, and add
   `* * * * * /home/USER/openwa/keepalive.sh >/dev/null 2>&1`. Do **not** combine with Passenger on the same port.

If the host kills the process or suspends the account for CPU/RAM, stop and use Hybrid.

## Step 7 · Link a number

Open `https://wa.example.com` → log in with `API_MASTER_KEY` → new session → scan QR.

## Hybrid (recommended for shared hosting)

Keep **your website/WordPress/PHP app on cPanel** and run **OpenWA on a small VPS** (guide 01). The cPanel side only
makes HTTPS calls.

```
Visitors ─▶ example.com (cPanel/PHP)  ──HTTPS + X-API-Key──▶  wa.example.com (VPS, OpenWA)  ─▶ WhatsApp
                      ▲                                              │
                      └────────── webhook (signed) ◀────────────────┘
```

1. Deploy OpenWA with [guide 01](01-vps-docker.md).
2. In the OpenWA dashboard create a **scoped API key** for the website (not the admin key): only the session it needs,
   and in `allowedIps` put your cPanel server's outgoing IP (cPanel → *Server Information* shows it).
3. Copy `deploy/php/openwa-client.php` to your site **outside `public_html`** (e.g. `~/lib/openwa-client.php`).
4. Store the key outside the web root: `~/.openwa_env` containing `OPENWA_KEY=...`, load it in PHP with
   `parse_ini_file`, or use cPanel's PHP-FPM `env` settings.
5. Send:

```php
require '/home/USER/lib/openwa-client.php';
$wa = new OpenWA('https://wa.example.com', trim(parse_ini_file('/home/USER/.openwa_env')['OPENWA_KEY']));
$wa->sendText('SESSION_ID', '15551234567@c.us', 'Order #123 shipped');
```

6. Receive: in OpenWA dashboard add a webhook `https://example.com/wa-webhook.php`; verify the
   `X-OpenWA-Signature` header (HMAC) before trusting the body (skeleton at the bottom of the PHP file).
   Return `200` quickly; do slow work in a queue/cron.
7. Test: run the snippet from a cPanel **Cron Job** or a one-off PHP file, then delete the file.

## Limits you accept on shared hosting

- Baileys only (higher ban risk than whatsapp-web.js), one session, no Redis/Postgres.
- Shared CPU/RAM limits can kill the process; sessions then re-link or drop.
- No Docker, no systemd, no custom ports. Passenger may not support the WebSocket channel the dashboard uses; the
  REST API still works.
- Upgrades are manual rebuilds. Back up `~/openwa/data` ([05](05-operations-backup-update-security.md)).
- Hosting terms of service may forbid running chat gateways. Check before relying on it for business use.
