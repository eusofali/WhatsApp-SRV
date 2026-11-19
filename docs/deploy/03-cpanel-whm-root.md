# 03 · cPanel/WHM server where you have root

You run a VPS or dedicated server with WHM/cPanel (AlmaLinux/Rocky 8 or 9, or CloudLinux). Apache serves your sites
on 80/443, so OpenWA must sit **behind Apache** as a reverse proxy on a subdomain such as `wa.example.com`.
The plan: run OpenWA on `127.0.0.1:2785`, let cPanel own the domain and its free AutoSSL certificate, and have Apache
forward traffic to OpenWA.

> **Strong advice:** if the server hosts production websites, give OpenWA its own small VPS instead (guide 01).
> Chromium + a database can starve the cPanel server (OOM kills MySQL/Apache). If you proceed, set strict memory
> limits and keep `MAX_CONCURRENT_SESSIONS` low.

## Step 1 · Check the server (SSH as root)

```bash
cat /etc/os-release | head -2       # AlmaLinux/Rocky 8 or 9 (glibc: ldd --version -> need 2.34+ for no-Docker; 9 is ok)
free -m                              # need >= 2 GB free for the build, then ~1 GB steady
df -h /                              # >= 10 GB free
```

## Step 2 · Create the subdomain in cPanel

1. Log in to the cPanel account that owns `example.com`.
2. **Domains → Create A New Domain**: `wa.example.com`. **Untick** "Share document root" and keep the default folder
   (it only holds the AutoSSL validation file).
3. **SSL/TLS Status → Run AutoSSL** and confirm `wa.example.com` has a valid certificate.

## Step 3 · Choose how to run OpenWA

### Option A: Docker (recommended)

AlmaLinux/Rocky ships Docker CE from Docker's repo:

```bash
dnf -y install dnf-plugins-core git openssl
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker
```

**CSF/Imunify firewall note.** If you use ConfigServer Firewall, Docker's iptables rules can conflict with it.
Because OpenWA only publishes to `127.0.0.1` and needs only *outbound* traffic, the usual symptom is no outbound
connectivity from the container. Fix: in `/etc/csf/csf.conf` set `DOCKER = "1"` (and `DOCKER_NETWORK4 = "172.16.0.0/12"`
in newer CSF versions), then `csf -ra`. Test with:
`docker run --rm curlimages/curl -sI https://web.whatsapp.com | head -1`.

Then follow guide 01 **steps 3–5** (installer, `.env`, local check). Skip 01 step 6 and use Step 4 below instead. In `.env` keep
`TRUSTED_PROXIES=172.16.0.0/12` (Docker NAT) — or `127.0.0.1` for Option B.

### Option B: Without Docker

Follow guide 02 **steps 2–7** (Node 22, user `openwa`, build, systemd). Use `dnf` instead of `apt`:

```bash
dnf -y install gcc-c++ make python3 git openssl
curl -fsSL https://rpm.nodesource.com/setup_22.x | bash - && dnf -y install nodejs
# Chromium libs (whatsapp-web.js only):
dnf -y install nss atk at-spi2-atk cups-libs libdrm libxkbcommon libXcomposite libXdamage libXrandr mesa-libgbm alsa-lib pango gtk3
```

Check `curl -s http://127.0.0.1:2785/api/health` works before continuing.

## Step 4 · Apache reverse proxy (survives cPanel updates)

1. Enable modules: **WHM → Software → EasyApache 4 → Customize Profile → Apache Modules**. Tick
   `mod_proxy`, `mod_proxy_http`, `mod_proxy_wstunnel`, `mod_headers` (mod_rewrite is on by default). Review → Provision.
2. Find the cPanel username that owns the domain (`/scripts/whoowns wa.example.com`), then:

```bash
CPUSER=cpaneluser; DOM=wa.example.com
for d in ssl std; do mkdir -p /etc/apache2/conf.d/userdata/$d/2_4/$CPUSER/$DOM; done
cp /root/WhatsApp-SRV/deploy/cpanel/apache-openwa-ssl.conf /etc/apache2/conf.d/userdata/ssl/2_4/$CPUSER/$DOM/openwa.conf
cp /root/WhatsApp-SRV/deploy/cpanel/apache-openwa-ssl.conf /etc/apache2/conf.d/userdata/std/2_4/$CPUSER/$DOM/openwa.conf
/usr/local/cpanel/scripts/rebuildhttpdconf
apachectl -t && /usr/local/cpanel/scripts/restartsrv_httpd
```

(Optionally keep only the `ssl` copy and force HTTPS redirect in cPanel: **Domains → Force HTTPS Redirect**.)

3. Test: `curl -s https://wa.example.com/api/health`.

## Step 5 · Protect the server

- **Never** expose `2785` publicly. CSF default-deny already blocks it. Do not add it to `TCP_IN`.
- In WHM → **Security Center**, leave ModSecurity on, but if it blocks large JSON/base64 media posts, whitelist
  the rule for that domain only (WHM → ModSecurity Tools → Rules List).
- cPanel's CageFS/jails do not apply to the service you installed, so run it as the unprivileged `openwa` user, and
  limit RAM (`MemoryMax` in the unit for Option B, `OPENWA_MEM_LIMIT` for Docker).

## Step 6 · Link a number and test

Same as guide 01 **step 7**. Dashboard: `https://wa.example.com`.

## Step 7 · Keep it healthy

- Docker: `restart: unless-stopped` plus `systemctl enable docker` already survive reboots.
- cPanel updates rebuild Apache config; the files under `/etc/apache2/conf.d/userdata/...` are preserved by design.
- Backups: see [05](05-operations-backup-update-security.md). Back up `/opt/openwa/data` (Docker volume or folder);
  cPanel's backup does **not** include it unless you add it to the server backup path.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `AH01114 / 503` from Apache | OpenWA not listening: check health on 127.0.0.1:2785, SELinux (`setsebool -P httpd_can_network_connect 1`) |
| Dashboard loads but live updates fail | `mod_proxy_wstunnel` missing, or the rewrite rule did not load; check `apachectl -M | grep -E 'proxy|rewrite'` |
| Container cannot reach WhatsApp | CSF/Docker iptables conflict, see Step 3 |
| 413 / upload fails | `LimitRequestBody` in the conf; ModSecurity body limit |
| Memory spikes kill MySQL | Cap OpenWA memory, `MAX_CONCURRENT_SESSIONS=1–2`, or move OpenWA to its own VPS |
