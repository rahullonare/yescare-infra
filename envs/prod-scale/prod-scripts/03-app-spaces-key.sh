#!/usr/bin/env bash
# Stage 03 — create the dedicated app Spaces key and persist it to prod.secrets
# (gitignored). This key is used for app uploads + GitHub secrets + asset seeding.
# Idempotent: skips if prod.secrets already carries APP_SPACES_* creds.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/prod.env"
SECRETS="$DIR/prod.secrets"
echo "=== [03] App Spaces key ==="
if [ -n "${APP_SPACES_ACCESS_KEY:-}" ] && [ -n "${APP_SPACES_SECRET_KEY:-}" ]; then
  echo "  prod.secrets already has APP_SPACES_* — skipping"; exit 0
fi
NAME="$APP_SPACES_KEY_NAME"
if doctl spaces keys list --no-header 2>/dev/null | awk '{print $1}' | grep -qx "$NAME"; then
  # Key exists but we don't hold its secret (DO shows it once). Make a fresh, uniquely named one.
  NAME="${APP_SPACES_KEY_NAME}-$(date +%Y%m%d%H%M%S)"
  echo "  '$APP_SPACES_KEY_NAME' exists; creating '$NAME' to capture a usable secret"
fi
umask 077
TMP="$(mktemp)"
doctl spaces keys create "$NAME" --grants 'bucket=;permission=fullaccess' -o json > "$TMP"
AK=$(python3 -c "import json;d=json.load(open('$TMP'));d=d[0] if isinstance(d,list) else d;print(d['access_key'])")
SK=$(python3 -c "import json;d=json.load(open('$TMP'));d=d[0] if isinstance(d,list) else d;print(d['secret_key'])")
rm -f "$TMP"
{ echo "# App Spaces credentials for prod ($NAME) — DO NOT COMMIT (gitignored)"
  echo "export APP_SPACES_ACCESS_KEY=$AK"
  echo "export APP_SPACES_SECRET_KEY=$SK"; } > "$SECRETS"
chmod 600 "$SECRETS"
echo "  created key '$NAME' (access $AK); secret saved to prod.secrets"
echo "  ⚠️ do NOT revoke this key in future Spaces cleanups — it is the app upload key"
