# 00 · Choose your hosting path

WhatsApp-SRV is [OpenWA](https://github.com/rmyndharis/OpenWA) (Node 22, NestJS, SQLite/Postgres) deployed as a
**long-running server**. That one fact decides which hosting types work.

## Why hosting type matters

OpenWA must stay running 24/7 to keep a WhatsApp session connected, hold a WebSocket open, and (with the default
engine) run a headless Chromium of ~300–500 MB per session. Classic shared hosting is built for short PHP requests,
not this.

## Decision table

| Your hosting | Works? | Engine | Use this guide |
|---|---|---|---|
| **VPS / cloud server** (Ubuntu/Debian), you have root | ✅ Best | whatsapp-web.js or Baileys | [01 Docker](01-vps-docker.md) (recommended) or [02 systemd](02-vps-bare-metal-systemd.md) |
| **cPanel/WHM on a VPS or dedicated**, you have root | ✅ Good | either | [03 cPanel with root](03-cpanel-whm-root.md) |
| **cPanel shared hosting**, no root | ⚠️ Only if a pre-flight check passes | Baileys only | [04 cPanel no root](04-cpanel-shared-no-root.md) |
| **cPanel shared, check fails** (most do) | ❌ for OpenWA itself | n/a | [04 → Hybrid](04-cpanel-shared-no-root.md#hybrid-recommended-for-shared-hosting): OpenWA on a cheap VPS, your site stays on cPanel |

> **Be realistic about shared hosting.** Most shared hosts cap memory (~1 GB), processes, run Node under Passenger
> (idles out), run an old glibc (< 2.34, which breaks OpenWA's SQLite binary), and offer no Docker. A cheap VPS
> (1 vCPU / 2 GB RAM, ~$4–6/month) is the reliable answer. Section 04 starts with a 1-minute check so you do not
> waste an afternoon.

## Sizing

| Sessions (WhatsApp numbers) | Engine | RAM | Disk |
|---|---|---|---|
| 1–2 | Baileys | 1 GB | 10 GB |
| 1–2 | whatsapp-web.js | 2 GB (+ swap) | 20 GB |
| 3–5 | whatsapp-web.js | 4 GB | 30 GB |
| 10+ | whatsapp-web.js | 8 GB+, set `OPENWA_PIDS_LIMIT` higher | 50 GB |

The Docker image **build** needs ~2 GB RAM. On a 1 GB VPS add swap first (guide 01, step 1).

## Before you start (all paths)

1. A **domain/subdomain** (e.g. `wa.example.com`) with an A record to the server IP (VPS paths) or created in cPanel.
2. A **dedicated WhatsApp number**. OpenWA uses unofficial protocols, so accounts can be restricted. Never link your
   primary number. Do not send bulk or unsolicited messages.
3. A password manager to store the admin API key.
4. If the data is regulated (health, finance, EU personal data), use Meta's official WhatsApp Cloud API instead.

## What "done" looks like

- `https://wa.example.com/api/health` returns OK.
- You can open the dashboard, log in with the admin API key, create a session, scan the QR with your WhatsApp
  (Linked devices), and send a test message.
- It survives a server reboot.
