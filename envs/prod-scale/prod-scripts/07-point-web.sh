#!/usr/bin/env bash
# Stage 07 — point the website (App Platform "king-prawn-app") at the prod backend
# by setting the build-time env VITE_API_BASE_URL, which triggers a zero-downtime
# rebuild. A repo edit alone will NOT change it — the App Platform env overrides.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/prod.env"
echo "=== [07] Point website -> $WEB_API_BASE_URL ==="
APPID=$(doctl apps list --no-header --format ID,Spec.Name | awk -v n="$WEB_APP_NAME" '$2==n{print $1}')
[ -n "$APPID" ] || { echo "  ERROR: App Platform app '$WEB_APP_NAME' not found"; exit 1; }
SPEC="$(mktemp)"; doctl apps spec get "$APPID" > "$SPEC"
# swap only the API-base value (the line ending in bff/api/v1); leave everything else intact
sed -i.bak -E "s#value: https?://[^[:space:]]*/bff/api/v1#value: $WEB_API_BASE_URL#" "$SPEC"
grep -q "value: $WEB_API_BASE_URL" "$SPEC" || { echo "  ERROR: could not set VITE_API_BASE_URL in spec"; rm -f "$SPEC" "$SPEC.bak"; exit 1; }
doctl apps update "$APPID" --spec "$SPEC" >/dev/null
rm -f "$SPEC" "$SPEC.bak"
echo "[07] done — App Platform is rebuilding $WEB_APP_NAME (zero-downtime)"
