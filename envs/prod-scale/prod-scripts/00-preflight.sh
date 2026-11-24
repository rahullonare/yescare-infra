#!/usr/bin/env bash
# Stage 00 — preflight: verify required tools, auth, and secrets are present.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/prod.env"
echo "=== [00] Preflight ==="
fail=0
for t in doctl kubectl gh helm psql aws terraform python3; do
  if command -v "$t" >/dev/null; then echo "  ok  : $t"; else echo "  MISS: $t"; fail=1; fi
done
doctl account get      >/dev/null 2>&1 && echo "  ok  : doctl auth" || { echo "  MISS: doctl auth (doctl auth init)"; fail=1; }
gh   auth status       >/dev/null 2>&1 && echo "  ok  : gh auth"    || { echo "  MISS: gh auth (gh auth login)";    fail=1; }
for v in TF_VAR_do_token TF_VAR_spaces_access_id TF_VAR_spaces_secret_key; do
  [ -n "${!v:-}" ] && echo "  ok  : \$$v" || { echo "  MISS: export $v"; fail=1; }
done
[ "$fail" = 0 ] && echo "[00] preflight PASSED" || { echo "[00] preflight FAILED — fix the above and re-run"; exit 1; }
