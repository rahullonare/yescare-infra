#!/usr/bin/env bash
###############################################################################
# dev-autostop.sh — scale the dev DOKS node pool off-hours to save cost.
#
# DOKS control plane (non-HA) is free; you pay for worker droplets. Off-hours
# we scale the dev pool to 0 nodes, and back to 1 for work hours. Managed
# dev-pg CANNOT be paused on DO, so it keeps running (~$16/mo unavoidable).
#
# Driven by .github/workflows/dev-autostop.yml (GitHub Actions cron, UTC).
# Schedule: Mon-Sat up 10:00 IST (04:30 UTC), down 19:00 IST (13:30 UTC);
#           Sunday stays down all day.
#
# Usage:  dev-autostop.sh {up|down|status}
# Auth:   requires doctl authenticated (local) or DIGITALOCEAN_ACCESS_TOKEN
#         env / digitalocean/action-doctl (CI).
###############################################################################
set -euo pipefail

CLUSTER="${CLUSTER:-dev-doks}"
POOL="${POOL:-dev-default}"
ACTION="${1:-status}"

log() { echo "[dev-autostop] $*"; }

case "$ACTION" in
  down|stop)
    log "Scaling ${CLUSTER}/${POOL} -> 0 nodes (auto-stop)"
    doctl kubernetes cluster node-pool update "$CLUSTER" "$POOL" \
      --auto-scale=false --count 0
    ;;
  up|start)
    log "Scaling ${CLUSTER}/${POOL} -> 1 node (auto-start)"
    doctl kubernetes cluster node-pool update "$CLUSTER" "$POOL" \
      --auto-scale=false --count 1
    ;;
  status)
    doctl kubernetes cluster node-pool list "$CLUSTER" -o json \
      | python3 -c "import sys,json;[print(p['name'],'count='+str(p.get('count')),'auto='+str(p.get('auto_scale', False)),'min='+str(p.get('min_nodes')),'max='+str(p.get('max_nodes'))) for p in json.load(sys.stdin)]"
    ;;
  *)
    echo "usage: $0 {up|down|status}" >&2
    exit 1
    ;;
esac
