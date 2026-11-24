#!/usr/bin/env bash
# Stage 05 — discover the ingress LB IP and point apiprod + grafana DNS at it.
# cert-manager then issues Let's Encrypt TLS automatically (via letsencrypt-prod).
#
# NOTE: the apiprod host itself should live in the backend repo's ingress template
# (durable fix — see RUNBOOK §8). The backend deploy (deploy-services-prod.sh)
# creates the app ingress; this stage only ensures DNS + the issuer annotation.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/prod.env"
CTX="$PROD_CONTEXT"
echo "=== [05] Ingress + DNS + TLS ==="

LB_IP=""
for i in $(seq 1 30); do
  LB_IP=$(kubectl --context "$CTX" get svc ingress-nginx-controller -n ingress-nginx \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [ -n "$LB_IP" ] && break; echo "  waiting for LB IP…"; sleep 10
done
[ -n "$LB_IP" ] || { echo "  ERROR: ingress LB has no IP yet"; exit 1; }
echo "  ingress LB IP = $LB_IP"

# make sure cert-manager will manage the app ingress cert
ING=$(kubectl --context "$CTX" get ingress -n "$PROD_NS" -o name 2>/dev/null | head -1 || true)
[ -n "$ING" ] && kubectl --context "$CTX" -n "$PROD_NS" annotate "$ING" \
  cert-manager.io/cluster-issuer=letsencrypt-prod --overwrite >/dev/null 2>&1 || \
  echo "  (no app ingress yet — ensure the backend template defines host $PROD_API_HOST)"

# upsert A records for apiprod + grafana
upsert_a(){ local name="$1" ip="$2" id
  id=$(doctl compute domain records list "$PROD_DOMAIN" --no-header --format ID,Type,Name \
       | awk -v n="$name" '$2=="A" && $3==n {print $1}')
  if [ -n "$id" ]; then
    doctl compute domain records update "$PROD_DOMAIN" --record-id "$id" \
      --record-type A --record-name "$name" --record-data "$ip" --record-ttl 300 >/dev/null
    echo "  updated $name.$PROD_DOMAIN -> $ip"
  else
    doctl compute domain records create "$PROD_DOMAIN" \
      --record-type A --record-name "$name" --record-data "$ip" --record-ttl 300 >/dev/null
    echo "  created $name.$PROD_DOMAIN -> $ip"
  fi; }
upsert_a apiprod "$LB_IP"
upsert_a grafana "$LB_IP"
echo "[05] done — TLS for $PROD_API_HOST / $GRAFANA_HOST issues automatically once DNS propagates"
