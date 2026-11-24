#!/usr/bin/env bash
# Verify the PROD environment. Read-only. Portable.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/prod.env"

echo "=== [PROD] Verification: $PROD_CLUSTER ==="
doctl kubernetes cluster kubeconfig save "$PROD_CLUSTER" --set-current-context >/dev/null

echo "--- nodes ---";    kubectl --context "$PROD_CONTEXT" get nodes
echo "--- kafka ---";    kubectl --context "$PROD_CONTEXT" get pods -n messaging
echo "--- services ---"; kubectl --context "$PROD_CONTEXT" get pods -n "$PROD_NS"
echo "--- ingress LB ---"
kubectl --context "$PROD_CONTEXT" get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'; echo
echo "--- postgres dbs ---"; doctl databases db   list "$PROD_PG_ID" --format Name
echo "--- postgres users ---"; doctl databases user list "$PROD_PG_ID" --format Name
echo "=== [PROD] Verify done ==="
