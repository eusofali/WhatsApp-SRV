#!/usr/bin/env bash
# Run this over SSH/Terminal on your cPanel account BEFORE trying to install anything.
# It tells you whether OpenWA can realistically run there (no root needed).
#   bash preflight.sh
ok=1; warn(){ echo "  [!] $*"; }; pass(){ echo "  [ok] $*"; }; fail(){ echo "  [X] $*"; ok=0; }

echo "== Node.js =="
if command -v node >/dev/null; then
  v=$(node -v | sed 's/v//'); major=${v%%.*}; minor=$(echo "$v" | cut -d. -f2)
  if [ "$major" -gt 22 ] || { [ "$major" -eq 22 ] && [ "$minor" -ge 19 ]; }; then pass "node $v (need >= 22.19)"
  else fail "node $v is too old. OpenWA needs >= 22.19. Check cPanel > Setup Node.js App for 22.x, or ask the host."; fi
else
  fail "node not on PATH. Try: source /home/\$USER/nodevenv/<app>/22/bin/activate  (after creating the app in cPanel)"
fi

echo "== glibc (prebuilt better-sqlite3 needs >= 2.34) =="
g=$(ldd --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+$')
if [ -n "$g" ] && [ "$(printf '%s\n2.34\n' "$g" | sort -V | head -1)" = "2.34" ]; then pass "glibc $g"
else fail "glibc ${g:-unknown} < 2.34 (CloudLinux 7/8 style). The install will fail. Use a VPS."; fi

echo "== Memory / process limits =="
mem=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
echo "  host RAM: ${mem} MB (your per-account LVE limit is usually much lower; see cPanel > Resource Usage)"
[ -r /sys/fs/cgroup/memory.max ] && echo "  cgroup memory.max: $(cat /sys/fs/cgroup/memory.max)"
nproc_lim=$(ulimit -u); echo "  max user processes: $nproc_lim"
[ "$nproc_lim" != "unlimited" ] && [ "$nproc_lim" -lt 200 ] && warn "low process limit; Chromium (whatsapp-web.js) will not run. Use ENGINE_TYPE=baileys."

echo "== Tooling =="
for t in git npm tar; do command -v $t >/dev/null && pass "$t" || warn "$t missing"; done
command -v chromium >/dev/null || command -v google-chrome >/dev/null || warn "no system Chromium: whatsapp-web.js will not work -> must use ENGINE_TYPE=baileys"

echo "== Outbound access to WhatsApp =="
if command -v curl >/dev/null; then
  code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' https://web.whatsapp.com/ || true)
  [ "$code" = "200" ] || [ "$code" = "302" ] && pass "web.whatsapp.com reachable ($code)" || fail "cannot reach web.whatsapp.com (HTTP ${code:-none}); firewall blocks outbound"
fi

echo
if [ $ok = 1 ]; then echo "RESULT: basic requirements met. Continue with docs/deploy/04-cpanel-shared-no-root.md"
else echo "RESULT: NOT suitable. Use a VPS (docs/deploy/01-vps-docker.md) and keep cPanel for your website only (see section 'Hybrid')."; fi
exit $((1-ok))
