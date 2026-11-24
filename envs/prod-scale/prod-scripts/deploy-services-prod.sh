#!/usr/bin/env bash
# Trigger the backend repo's deploy.yml (environment=prod) for all services.
# Requires update-secrets-prod.sh to have run first (so KUBE_CONFIG_PROD +
# PROD_* point at the new cluster). Portable.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/prod.env"

SERVICES=("auth-service" "hospital-service" "payment-service" "notification-service" "user-bff" "websocket-gateway")

echo "=== [PROD] Deploying services to $PROD_CLUSTER via $PROD_BACKEND_REPO deploy.yml ==="
for SVC in "${SERVICES[@]}"; do
  echo "-> $SVC"
  gh workflow run deploy.yml --repo "$PROD_BACKEND_REPO" \
    --field environment=prod --field service="$SVC" --field image_tag=latest
  sleep 2
done

echo "Triggered. Watch: gh run list --repo $PROD_BACKEND_REPO"
echo "Then: kubectl --context $PROD_CONTEXT get pods -n $PROD_NS -w"
