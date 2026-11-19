#!/usr/bin/env bash
# LAST-RESORT supervisor for shared hosting where Passenger idles the app out.
# Add in cPanel > Cron Jobs (every minute):
#   * * * * * /home/CPANELUSER/openwa/keepalive.sh >/dev/null 2>&1
# Many hosts forbid long-running background processes. Check your terms of service first;
# if they kill it, move to a VPS.
APP_DIR="${APP_DIR:-$HOME/openwa}"
PIDFILE="$APP_DIR/data/openwa.pid"
LOG="$APP_DIR/data/openwa.log"
NODE_BIN="${NODE_BIN:-$(ls -d $HOME/nodevenv/*/22/bin/node 2>/dev/null | head -1)}"
NODE_BIN="${NODE_BIN:-$(command -v node)}"

mkdir -p "$APP_DIR/data"
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then exit 0; fi   # already running

cd "$APP_DIR" || exit 1
set -a; [ -f .env ] && . ./.env; set +a
export PORT="${PORT:-2785}" ENGINE_TYPE="${ENGINE_TYPE:-baileys}" NODE_ENV=production
nohup "$NODE_BIN" dist/main >>"$LOG" 2>&1 &
echo $! > "$PIDFILE"
# trim log to last ~5 MB
[ "$(stat -c%s "$LOG" 2>/dev/null || echo 0)" -gt 5242880 ] && tail -c 2097152 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
