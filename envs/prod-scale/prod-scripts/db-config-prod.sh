#!/usr/bin/env bash
# Managed-DB runtime config tuning for prod (idempotent).
#
# Valkey/Redis: disable the idle-connection timeout. Default `valkey_timeout=300`
# makes the managed DB drop idle client connections every 5 min, so every service
# logs Lettuce "Reconnecting/Reconnected" churn when traffic is low. Set it to 0.
#
# Gotchas: the API field is `valkey_timeout` (NOT `timeout`) and the engine is
# `valkey` (NOT `redis`) — wrong values return `422 the mask must be set`.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/prod.env"
echo "=== [db-config] managed DB tuning ==="
: "${PROD_REDIS_ID:?redis id not resolved — is $PROD_REDIS_NAME created yet?}"

cur=$(doctl databases configuration get "$PROD_REDIS_ID" --engine valkey 2>/dev/null | awk '/ValkeyTimeout/{print $2}')
echo "  valkey_timeout currently: ${cur:-unknown}"
if [ "${cur:-}" != "0" ]; then
  doctl databases configuration update "$PROD_REDIS_ID" --engine valkey --config-json '{"valkey_timeout": 0}'
  echo "  set valkey_timeout=0 (no idle disconnect)"
else
  echo "  already 0 — skip"
fi
echo "[db-config] done"
