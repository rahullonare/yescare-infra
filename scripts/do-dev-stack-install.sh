#!/usr/bin/env bash
# Post-terraform install script for the DEV environment.
# Installs: ingress-nginx, Redis, RabbitMQ, Kafka into DOKS.
#
# Usage:
#   cd digitalocean/envs/dev
#   terraform output -raw kubeconfig > kubeconfig-dev.yaml
#   export KUBECONFIG="$PWD/kubeconfig-dev.yaml"
#   bash ../../scripts/do-dev-stack-install.sh

set -euo pipefail

NAMESPACE_MESSAGING="messaging"
NAMESPACE_INGRESS="ingress-nginx"

echo "==> Adding Helm repos"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
helm repo update

echo "==> Creating namespaces"
kubectl create namespace "${NAMESPACE_INGRESS}"  --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "${NAMESPACE_MESSAGING}" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing ingress-nginx (creates DO Load Balancer)"
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace "${NAMESPACE_INGRESS}" \
  --set controller.service.type=LoadBalancer \
  --version 4.10.1 \
  --wait --timeout 10m

echo "==> Installing Redis (standalone, no auth — dev only)"
helm upgrade --install redis bitnami/redis \
  --namespace default \
  --set auth.enabled=false \
  --set architecture=standalone \
  --wait --timeout 10m

echo "==> Installing RabbitMQ"
helm upgrade --install rabbitmq bitnami/rabbitmq \
  --namespace "${NAMESPACE_MESSAGING}" \
  --set auth.username=yescare \
  --set auth.password=devpassword \
  --set persistence.enabled=false \
  --wait --timeout 10m

echo "==> Installing Kafka (KRaft mode)"
helm upgrade --install kafka bitnami/kafka \
  --namespace "${NAMESPACE_MESSAGING}" \
  --set kraft.enabled=true \
  --set controller.replicaCount=1 \
  --set broker.replicaCount=0 \
  --set persistence.enabled=false \
  --wait --timeout 10m

echo ""
echo "==> Stack ready. Waiting for LoadBalancer IP..."
kubectl wait --namespace "${NAMESPACE_INGRESS}" \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

LB_IP=$(kubectl get svc ingress-nginx-controller \
  -n "${NAMESPACE_INGRESS}" \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")

echo ""
echo "=========================================="
echo "  Dev Stack Installed"
echo "=========================================="
echo "  Load Balancer IP : ${LB_IP}"
echo "  Redis            : redis-master.default.svc.cluster.local:6379"
echo "  RabbitMQ         : rabbitmq.${NAMESPACE_MESSAGING}.svc.cluster.local:5672"
echo "  Kafka            : kafka.${NAMESPACE_MESSAGING}.svc.cluster.local:9092"
echo ""
echo "  RabbitMQ Management UI:"
echo "    kubectl port-forward svc/rabbitmq 15672:15672 -n ${NAMESPACE_MESSAGING}"
echo "    http://localhost:15672  (user: yescare / devpassword)"
echo "=========================================="
