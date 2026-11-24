#!/usr/bin/env bash
# Stage 04 — scale the node pool for headroom, then apply the full observability
# stack (Prometheus/Grafana/Loki/Tempo/Promtail/otel-collector) in dependency order.
# Fixes the app pods' "UnknownHostException otel-collector.monitoring…" logs.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/prod.env"
CTX="$PROD_CONTEXT"; MON="$(cd "$DIR/../monitoring" && pwd)"
echo "=== [04] Monitoring ==="

CID=$(doctl kubernetes cluster get "$PROD_CLUSTER" --no-header --format ID)
read -r PID CNT < <(doctl kubernetes cluster node-pool list "$CID" -o json \
  | python3 -c 'import json,sys;p=json.load(sys.stdin)[0];print(p["id"],p["count"])')
if [ "$CNT" -lt "$MONITORING_MIN_NODES" ]; then
  echo "  scaling default pool $CNT -> $MONITORING_MIN_NODES (stack needs the headroom)"
  doctl kubernetes cluster node-pool update "$CID" "$PID" \
    --count "$MONITORING_MIN_NODES" --auto-scale \
    --min-nodes "$MONITORING_MIN_NODES" --max-nodes "$((MONITORING_MIN_NODES+1))"
  for i in $(seq 1 30); do
    r=$(kubectl --context "$CTX" get nodes --no-headers 2>/dev/null | grep -cw Ready)
    echo "    nodes Ready: $r/$MONITORING_MIN_NODES"; [ "$r" -ge "$MONITORING_MIN_NODES" ] && break; sleep 15
  done
fi

echo "  applying stack (ns -> rbac -> configmaps -> pvcs -> services -> deployments -> ingress)"
kubectl --context "$CTX" apply -f "$MON/namespace.yaml"
kubectl --context "$CTX" apply -f "$MON/rbac/"
kubectl --context "$CTX" apply -f "$MON/configmaps/"
kubectl --context "$CTX" apply -f "$MON/loki-pvc.yaml" -f "$MON/tempo-pvc.yaml"
kubectl --context "$CTX" apply -f "$MON/deployments/services.yaml"
for f in otel-collector tempo prometheus loki promtail-daemonset grafana; do
  kubectl --context "$CTX" apply -f "$MON/deployments/$f.yaml"
done
kubectl --context "$CTX" apply -f "$MON/grafana-ingress.yaml"
echo "[04] done"
