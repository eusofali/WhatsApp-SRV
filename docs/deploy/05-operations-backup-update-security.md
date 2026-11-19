# 05 · Operations: backups, updates, security, monitoring

Applies to every path. Replace `/opt/openwa` with your install folder (`~/openwa` on shared hosting).

## Backups

What to protect: the whole `data/` directory (`main.sqlite`, session credentials, media, `.api-key`) and your `.env`.
**Losing session data means re-scanning the QR.** Losing `API_KEY_PEPPER` means no key works.

OpenWA ships `scripts/backup.sh` and `scripts/restore.sh` (covers SQLite, session state, media, generated secrets).

```bash
cd /opt/openwa && BACKUP_DIR=/var/backups/openwa ./scripts/backup.sh     # run once, check the archive
```

Daily at 03:00, keep 14 days, then copy off-server (rclone/S3/another VPS):

```bash
# crontab -e
0 3 * * * cd /opt/openwa && BACKUP_DIR=/var/backups/openwa ./scripts/backup.sh && find /var/backups/openwa -type f -mtime +14 -delete
```

Also save `.env` in your password manager (it holds the pepper). **Test a restore** on a spare machine once.
Docker note: the script is meant to run against the compose deployment; read its header before first use, and never
run `docker compose down -v` (deletes volumes).

## Updating

1. Read `CHANGELOG.md` for the version range (OpenWA is pre-1.0, so schema/API changes happen).
2. Back up.
3. Docker: `cd /opt/openwa && git fetch --tags && git checkout <tag> && docker compose up -d --build`
   Bare metal: see guide 02 "Updating".
4. Check `curl https://wa.example.com/api/health` and a test message.
5. Roll back = checkout the previous tag + restore the backup (migrations may not reverse automatically).

Update the OS monthly (`apt upgrade` / `dnf update`) and reboot when the kernel changes.

## Security checklist

- [ ] Port 2785 reachable only from `127.0.0.1` (`ss -tlnp | grep 2785`).
- [ ] HTTPS only; HSTS if you are sure.
- [ ] Docker socket proxy disabled (override file) unless you use built-in datastores.
- [ ] Admin key stored in a password manager; **apps get scoped keys**, not the admin key; add `allowedIps`.
- [ ] `CORS_ORIGINS` lists explicit origins, no `*`.
- [ ] MCP endpoint (if enabled) is not public without an auth proxy.
- [ ] SSH keys only, `fail2ban`, firewall on, non-root user for daily work.
- [ ] Swagger off in production (default). Enable temporarily with `ENABLE_SWAGGER=true` only when needed.
- [ ] Webhook receivers verify `X-OpenWA-Signature`.
- [ ] Rotate the admin key if exposed: create a new ADMIN key via `POST /api/auth/api-keys`, then revoke the old one.
  Lost key: see OpenWA docs `04-security-design.md` ("Recovering a lost admin key").

## WhatsApp account safety

Dedicated number; warm it up (normal use for days before automation); send only to people who expect messages; throttle
bulk sends; do not run the same session on two servers (set `AUTO_START_SESSIONS` on one instance only); if restricted,
OpenWA cannot undo it.

## Monitoring

- Uptime: free UptimeRobot/Better Stack check on `https://wa.example.com/api/health` (alert by email/Telegram).
- Logs: `docker compose logs -f openwa-api` or `journalctl -u openwa -f`.
- Resources: `docker stats`, `free -m`, `df -h`. Alert at 85% disk.
- Metrics: OpenWA exposes a metrics module; scrape with Prometheus if you have one (see its docs `10-devops-infrastructure.md`).
- Also set up a **webhook for session status events** so your app learns when a number disconnects.

## Day-2 troubleshooting

| Symptom | First thing to try |
|---|---|
| Session `DISCONNECTED` after restart | `AUTO_START_SESSIONS=true`; start it from the dashboard; re-scan if logged out |
| Chromium zombie / `SingletonLock` | `docker compose restart openwa-api` (entrypoint clears locks) |
| Disk filling | Media in `data/media`; prune old backups; enable media retention settings in dashboard |
| High RAM | Fewer sessions, switch to Baileys, bigger VPS |
| Messages not sent, 503 | Session not READY; check status and logs |
