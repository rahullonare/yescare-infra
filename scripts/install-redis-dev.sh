#!/usr/bin/env bash
# Installs Bitnami Redis into the default namespace — same in-cluster endpoint as AWS dev k3s userdata:
#   redis-master.default.svc.cluster.local:6379
#
# Prerequisites: kubectl works (export KUBECONFIG to kubeconfig from terraform output).

set -euo pipefail

helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
helm repo update

helm upgrade --install redis bitnami/redis \
  --set auth.enabled=false \
  --set architecture=standalone \
  --wait --timeout 10m

echo "Redis ready: redis-master.default.svc.cluster.local:6379"
