#!/usr/bin/env bash
# Stage 02 — cluster add-ons: ingress-nginx (creates the DO LB), cert-manager,
# and the letsencrypt-prod ClusterIssuer. Idempotent (helm upgrade --install).
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/prod.env"
CTX="$PROD_CONTEXT"
echo "=== [02] Platform add-ons ==="
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo add jetstack      https://charts.jetstack.io                  >/dev/null 2>&1 || true
helm repo update >/dev/null

echo "-- ingress-nginx $INGRESS_NGINX_VERSION --"
helm --kube-context "$CTX" upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace --version "$INGRESS_NGINX_VERSION" \
  --set controller.service.type=LoadBalancer --wait --timeout 10m

echo "-- cert-manager $CERT_MANAGER_VERSION --"
helm --kube-context "$CTX" upgrade --install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace --version "$CERT_MANAGER_VERSION" \
  --set crds.enabled=true --wait --timeout 10m

echo "-- letsencrypt-prod ClusterIssuer --"
kubectl --context "$CTX" apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: $LE_EMAIL
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
kubectl --context "$CTX" wait --for=condition=ready clusterissuer/letsencrypt-prod --timeout=120s || true
echo "[02] done"
