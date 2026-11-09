#!/usr/bin/env bash
# Deploy backend/ to the VPS, restart petsy-api, verify health, roll back on failure.
# Usage: deploy/deploy-backend.sh [--dry-run]
set -euo pipefail

HOST="${PETSY_HOST:-petsy-vps}"
APP_DIR=/opt/petsy/backend
PREV_DIR=/opt/petsy/backend.prev
VENV=/opt/petsy/venv
SERVICE=petsy-api
LOCAL_HEALTH=http://127.0.0.1:8077/api/health
PUBLIC_HEALTH="${PETSY_PUBLIC_HEALTH:-https://petsy.company/api/health}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH=(ssh -o BatchMode=yes "$HOST")
RSYNC_OPTS=(-az --delete --exclude __pycache__ --exclude uploads --exclude .env --exclude .venv --exclude venv -e "ssh -o BatchMode=yes")

step() { printf '\n==> %s\n' "$*"; }

step "Checking backend code"
python3 -m py_compile "$ROOT/backend/server.py"

if [ "${1:-}" = "--dry-run" ]; then
  step "Files that would change on $HOST"
  rsync "${RSYNC_OPTS[@]}" --dry-run --itemize-changes "$ROOT/backend/" "$HOST:$APP_DIR/"
  exit 0
fi

step "Saving current release to $PREV_DIR"
"${SSH[@]}" "rm -rf $PREV_DIR && rsync -a --exclude uploads $APP_DIR/ $PREV_DIR/"
old_req=$("${SSH[@]}" "sha256sum $APP_DIR/requirements.txt | cut -d' ' -f1")

step "Uploading backend"
rsync "${RSYNC_OPTS[@]}" --itemize-changes "$ROOT/backend/" "$HOST:$APP_DIR/"

new_req=$("${SSH[@]}" "sha256sum $APP_DIR/requirements.txt | cut -d' ' -f1")
if [ "$old_req" != "$new_req" ]; then
  step "requirements.txt changed, installing dependencies"
  "${SSH[@]}" "$VENV/bin/pip install -q -r $APP_DIR/requirements.txt"
fi

wait_healthy() {
  "${SSH[@]}" "sudo systemctl restart $SERVICE && for i in \$(seq 1 30); do
      curl -fsS $LOCAL_HEALTH 2>/dev/null | grep -q '\"status\":\"healthy\"' && exit 0; sleep 1; done; exit 1"
}

step "Restarting $SERVICE"
if ! wait_healthy; then
  echo "!! $SERVICE is not healthy after deploy; recent logs:" >&2
  "${SSH[@]}" "sudo journalctl -u $SERVICE -n 30 --no-pager -o cat" >&2 || true
  step "Rolling back to previous release"
  "${SSH[@]}" "rsync -a --delete --exclude uploads $PREV_DIR/ $APP_DIR/"
  [ "$old_req" != "$new_req" ] && "${SSH[@]}" "$VENV/bin/pip install -q -r $APP_DIR/requirements.txt"
  if wait_healthy; then
    echo "!! Rolled back; previous release is running." >&2
  else
    echo "!! Rollback also unhealthy; check the server now." >&2
  fi
  exit 1
fi

step "Checking $PUBLIC_HEALTH"
curl -fsS "$PUBLIC_HEALTH"
echo
step "Deploy OK"
