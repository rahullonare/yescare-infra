#!/usr/bin/env bash
# Stage 08 — upload the vendored static app assets into the prod Spaces bucket so
# the DB's relative image keys resolve (fixes "missing icons"). Assets are versioned
# in the repo at assets/prod-app-bucket/. Uses the app Spaces key from prod.secrets.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/prod.env"
: "${APP_SPACES_ACCESS_KEY:?run 03-app-spaces-key.sh first (or set APP_SPACES_* in prod.secrets)}"
export AWS_ACCESS_KEY_ID="$APP_SPACES_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$APP_SPACES_SECRET_KEY"
echo "=== [08] Upload app assets -> $PROD_SPACES_BUCKET ==="
"$DIR/../scripts/upload-prod-app-assets.sh" --acl private
echo "[08] done"
