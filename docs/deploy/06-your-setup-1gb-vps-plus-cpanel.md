# 06 · Your setup: 1 vCPU / 1 GB / 25 GB Ubuntu 22.04 VPS + cPanel shared hosting

## Decision

| Question | Answer |
|---|---|
| Rebuild the VPS? | **Only if nothing important runs on it.** Its hostname is `panel.…`, so check for a control panel or sites first (`ss -tlnp`, `docker ps`, `ls /var/www`). Ubuntu 22.04 is already the right OS (glibc 2.35), so a rebuild is not required. If it is empty, a clean rebuild to **Ubuntu 22.04 LTS** is the tidiest. Keep 22.04, not 24.04, so these guides match. |
| Engine | **`baileys`**. whatsapp-web.js needs 300–500 MB *per session* of Chromium, which does not fit in 1 GB. |
| Sessions | **1** (`MAX_CONCURRENT_SESSIONS=1`). Two is the practical ceiling with Baileys. |
| Install method | **Docker + swap** (guide 01) with the memory cap below. Bare metal (guide 02) saves ~100 MB RAM if you prefer. |
| cPanel shared hosting | **Do not run OpenWA there.** Use the **Hybrid** setup: your website on cPanel calls the VPS. |
| Should you upgrade? | A 2 GB plan makes the build painless and allows whatsapp-web.js (lower ban risk). Optional, not required. |

## Step 1 · Prepare the VPS (SSH as root)

```bash
apt update && apt -y upgrade
timedatectl set-timezone UTC

# 3 GB swap is REQUIRED: the image build needs ~2 GB, you only have 1 GB
fallocate -l 3G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
sysctl vm.swappiness=20 && echo 'vm.swappiness=20' > /etc/sysctl.d/99-swap.conf

apt -y install ufw
ufw default deny incoming && ufw default allow outgoing
ufw allow OpenSSH && ufw allow 80/tcp && ufw allow 443/tcp && ufw --force enable
```

DNS: create an A record **`wa.yourdomain.com` → your VPS IP** (at your domain's DNS, or in cPanel's Zone Editor if
cPanel manages the domain). Do not point your main website's record here.

## Step 2 · Install with the 1 GB settings

```bash
apt -y install git
git clone <YOUR WhatsApp-SRV REPO URL> /root/WhatsApp-SRV
cd /root/WhatsApp-SRV
OPENWA_MEM_LIMIT=700m bash deploy/install-vps-docker.sh
```

The first build takes **15–30 minutes** because it swaps heavily. If it ends with `Killed` / exit 137, run it again;
layers already built are cached.

Then edit the config:

```bash
nano /opt/openwa/.env
```

```ini
BASE_URL=https://wa.yourdomain.com
CORS_ORIGINS=https://wa.yourdomain.com
ENGINE_TYPE=baileys
MAX_CONCURRENT_SESSIONS=1
```

Make the memory cap permanent for this small server and restart:

```bash
echo 'OPENWA_MEM_LIMIT=700m' >> /opt/openwa/.env
cd /opt/openwa && docker compose up -d
docker stats --no-stream           # openwa-api should sit around 250-450 MB
curl -s http://127.0.0.1:2785/api/health
```

## Step 3 · HTTPS and link a number

Guide 01 **step 6** (Caddy is the lightest and easiest) and **step 7** (scan the QR with a **dedicated** number).

## Step 4 · Connect your cPanel hosting (Hybrid)

1. In the OpenWA dashboard create a **scoped API key** for the website (one session, not the admin key). Put your
   shared hosting's outgoing IP in `allowedIps` (cPanel → *General Information → Shared IP Address*).
2. Put `deploy/php/openwa-client.php` outside `public_html` (e.g. `/home/CPUSER/lib/`) and the key in
   `/home/CPUSER/.openwa_env` (`OPENWA_KEY=...`, `chmod 600`).
3. Send a test message with the snippet in guide 04 → *Hybrid*.
4. Receive messages: add a webhook in the dashboard pointing to `https://yourdomain.com/wa-webhook.php` and verify
   `X-OpenWA-Signature`.

If your cPanel host blocks outbound cURL to non-standard hosts, ask support to allow HTTPS to `wa.yourdomain.com`
(port 443 only; no special ports are needed).

## Step 5 · Operations for a 1 GB box

- Add the daily backup cron from guide 05, and **copy backups off the VPS** (25 GB disk is small).
- `docker system prune -f` monthly; keep `df -h` under 80%.
- Watch memory: `free -m`. If swap use stays above ~1 GB, reduce to one session or upgrade to 2 GB.
- Uptime check on `https://wa.yourdomain.com/api/health` (UptimeRobot, free).

## If you rebuild the VPS first

In the provider panel: **Rebuild → Ubuntu 22.04 LTS (x86_64)**, add your SSH key if offered, wait for ACTIVE, then
`ssh root@YOUR_IP` and start at Step 1. A rebuild erases everything on the disk.
