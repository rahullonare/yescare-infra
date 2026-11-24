#!/usr/bin/env bash
###############################################################################
# cluster-power.sh — MANUAL stop/start of any DOKS cluster's worker nodes.
#
# On-demand cost control: scale ALL node pools of a cluster to 0 (stop) or back
# up (start). Works for single- or multi-pool clusters (dev, preprod, prod).
#
#   NOTE: the DOKS control plane (non-HA) is free; you pay for worker droplets.
#   Managed databases (Postgres/Redis) are NOT touched — DO cannot pause them.
#   Stopping a cluster terminates its nodes; pods reschedule on start (~5-10m).
#
# Usage:
#   cluster-power.sh status <cluster>
#   cluster-power.sh stop   <cluster>
#   cluster-power.sh start  <cluster> [nodes-per-pool]   # default 1
#
# Examples:
#   cluster-power.sh stop  dev-doks
#   cluster-power.sh start dev-doks
#   cluster-power.sh stop  yescare-preprod-scale-k8s
#   cluster-power.sh start yescare-preprod-scale-k8s 2
#
# Auth: doctl authenticated (local) or DIGITALOCEAN_ACCESS_TOKEN (CI).
###############################################################################
set -euo pipefail

ACTION="${1:-}"
CLUSTER="${2:-}"
NODES="${3:-1}"

[ -z "$ACTION" ] || [ -z "$CLUSTER" ] && {
  echo "usage: $0 {status|stop|start} <cluster> [nodes-per-pool]" >&2
  exit 1
}

show() {
  doctl kubernetes cluster node-pool list "$CLUSTER" -o json \
    | python3 -c "import sys,json;[print(' -',p['name'],'count='+str(p.get('count')),'auto='+str(p.get('auto_scale',False)),'min='+str(p.get('min_nodes')),'max='+str(p.get('max_nodes'))) for p in json.load(sys.stdin)]"
}

# list of pool names for the cluster
pools() {
  doctl kubernetes cluster node-pool list "$CLUSTER" -o json \
    | python3 -c "import sys,json;[print(p['name']) for p in json.load(sys.stdin)]"
}

case "$ACTION" in
  status)
    echo "[$CLUSTER] node pools:"; show
    ;;
  stop|down)
    echo "[$CLUSTER] STOP — scaling all pools to 0"
    while read -r p; do
      [ -z "$p" ] && continue
      echo "  -> $p = 0"
      doctl kubernetes cluster node-pool update "$CLUSTER" "$p" --auto-scale=false --count 0 >/dev/null
    done < <(pools)
    echo "done."; show
    ;;
  start|up)
    echo "[$CLUSTER] START — scaling all pools to ${NODES}"
    while read -r p; do
      [ -z "$p" ] && continue
      echo "  -> $p = ${NODES}"
      doctl kubernetes cluster node-pool update "$CLUSTER" "$p" --auto-scale=false --count "$NODES" >/dev/null
    done < <(pools)
    echo "done (nodes take a few minutes to become Ready)."; show
    ;;
  *)
    echo "usage: $0 {status|stop|start} <cluster> [nodes-per-pool]" >&2
    exit 1
    ;;
esac
