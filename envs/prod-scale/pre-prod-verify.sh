#!/bin/bash
set -euo pipefail

# ==================================================
# YesCare Pre-Prod Verification
# ==================================================

CLUSTER_NAME="yescare-pre-prod-scale-k8s"
EXPECTED_CONTEXT="do-sgp1-yescare-pre-prod-scale-k8s"

echo "=================================================="
echo "        YesCare Pre-Prod Verification"
echo "=================================================="

# ==================================================
# 0. DigitalOcean + Kubernetes Credentials
# ==================================================

echo
echo "=================================================="
echo "0. Kubernetes Credentials"
echo "=================================================="

echo "Cluster:"
echo "$CLUSTER_NAME"

echo
echo "Checking DigitalOcean authentication..."

doctl account get --format Status --no-header

echo "DigitalOcean authentication: OK"

# ==================================================
# Generate temporary kubeconfig
# ==================================================

KUBECONFIG_FILE="$(pwd)/.preprod-kubeconfig"

cleanup() {
    rm -f "$KUBECONFIG_FILE"
}

trap cleanup EXIT

echo
echo "Generating temporary kubeconfig..."

doctl kubernetes cluster kubeconfig show "$CLUSTER_NAME" \
    > "$KUBECONFIG_FILE"

chmod 600 "$KUBECONFIG_FILE" 2>/dev/null || true

export KUBECONFIG="$KUBECONFIG_FILE"

CURRENT_CONTEXT="$(kubectl config current-context)"

echo
echo "Current context:"
echo "$CURRENT_CONTEXT"

if [ "$CURRENT_CONTEXT" != "$EXPECTED_CONTEXT" ]; then
    echo "ERROR: Unexpected Kubernetes context."
    echo "Expected: $EXPECTED_CONTEXT"
    echo "Actual:   $CURRENT_CONTEXT"
    exit 1
fi

echo "Kubernetes context: OK"

# ==================================================
# 1. Kubernetes Nodes
# ==================================================

echo
echo "=================================================="
echo "1. Kubernetes Nodes"
echo "=================================================="

kubectl get nodes -o wide

echo
echo "Node verification: OK"

# ==================================================
# 2. Kafka
# ==================================================

echo
echo "=================================================="
echo "2. Kafka"
echo "=================================================="

if kubectl get namespace kafka >/dev/null 2>&1; then
    echo
    echo "Kafka namespace:"
    kubectl get namespace kafka

    echo
    echo "Kafka deployments:"
    kubectl -n kafka get deployments -o wide || true

    echo
    echo "Kafka pods:"
    kubectl -n kafka get pods -o wide || true

    echo
    echo "Kafka services:"
    kubectl -n kafka get services -o wide || true

    echo
    echo "Kafka StatefulSets:"
    kubectl -n kafka get statefulsets -o wide || true

    echo
    echo "Kafka verification completed."
else
    echo "WARNING: kafka namespace does not exist."
fi

# ==================================================
# 3. PostgreSQL
# ==================================================

echo
echo "=================================================="
echo "3. PostgreSQL"
echo "=================================================="

echo
echo "DigitalOcean databases:"

doctl databases list

POSTGRES_ID="$(
    doctl databases list \
        --format ID,Name \
        --no-header |
    awk '$2 == "yescare-pre-pg" || $2 == "yescare-pre-prod-pg" || $2 == "yescare-pre-prod-scale-pg" {print $1; exit}'
)"

if [ -n "${POSTGRES_ID:-}" ]; then
    echo
    echo "PostgreSQL cluster ID found:"
    echo "$POSTGRES_ID"

    echo
    echo "PostgreSQL cluster:"
    doctl databases get "$POSTGRES_ID"

    echo
    echo "PostgreSQL databases:"
    doctl databases db "$POSTGRES_ID" || true

    echo
    echo "PostgreSQL users:"
    doctl databases user "$POSTGRES_ID" || true
else
    echo
    echo "WARNING: PostgreSQL cluster could not be located automatically."
    echo "Verify the database name using:"
    echo "  doctl databases list"
fi

# ==================================================
# 4. Redis
# ==================================================

echo
echo "=================================================="
echo "4. Redis"
echo "=================================================="

echo
echo "DigitalOcean Redis databases:"

doctl databases list

REDIS_ID="$(
    doctl databases list \
        --format ID,Name \
        --no-header |
    awk '$2 == "yescare-pre-redis" || $2 == "yescare-pre-prod-redis" || $2 == "yescare-pre-prod-scale-redis" {print $1; exit}'
)"

if [ -n "${REDIS_ID:-}" ]; then
    echo
    echo "Redis cluster ID found:"
    echo "$REDIS_ID"

    echo
    echo "Redis cluster:"
    doctl databases get "$REDIS_ID"
else
    echo
    echo "WARNING: Redis cluster could not be located automatically."
    echo "Verify the database name using:"
    echo "  doctl databases list"
fi

# ==================================================
# 5. Ingress NGINX
# ==================================================

echo
echo "=================================================="
echo "5. Ingress NGINX"
echo "=================================================="

if kubectl get namespace ingress-nginx >/dev/null 2>&1; then
    echo
    echo "Ingress namespace:"
    kubectl get namespace ingress-nginx

    echo
    echo "Ingress pods:"
    kubectl -n ingress-nginx get pods -o wide

    echo
    echo "Ingress services:"
    kubectl -n ingress-nginx get services -o wide

    echo
    echo "Ingress deployments:"
    kubectl -n ingress-nginx get deployments -o wide

    echo
    echo "Ingress resources:"
    kubectl get ingress --all-namespaces -o wide || true
else
    echo "WARNING: ingress-nginx namespace does not exist."
fi

# ==================================================
# 6. Load Balancer IP
# ==================================================

echo
echo "=================================================="
echo "6. Load Balancer"
echo "=================================================="

if kubectl get namespace ingress-nginx >/dev/null 2>&1; then
    kubectl -n ingress-nginx get svc \
        -o custom-columns='NAME:.metadata.name,TYPE:.spec.type,EXTERNAL-IP:.status.loadBalancer.ingress[*].ip,HOSTNAME:.status.loadBalancer.ingress[*].hostname' \
        || true
fi

# ==================================================
# 7. cert-manager
# ==================================================

echo
echo "=================================================="
echo "7. cert-manager"
echo "=================================================="

if kubectl get namespace cert-manager >/dev/null 2>&1; then
    echo
    echo "cert-manager namespace:"
    kubectl get namespace cert-manager

    echo
    echo "cert-manager pods:"
    kubectl -n cert-manager get pods -o wide

    echo
    echo "cert-manager deployments:"
    kubectl -n cert-manager get deployments -o wide

    echo
    echo "ClusterIssuers:"
    kubectl get clusterissuer -o wide || true

    echo
    echo "Certificates:"
    kubectl get certificate --all-namespaces -o wide || true
else
    echo "WARNING: cert-manager namespace does not exist."
fi

# ==================================================
# 8. Kubernetes Storage / Secrets Overview
# ==================================================

echo
echo "=================================================="
echo "8. Kubernetes Storage / Secrets"
echo "=================================================="

echo
echo "PersistentVolumeClaims:"
kubectl get pvc --all-namespaces -o wide || true

echo
echo "Secrets in pre-prod namespace:"

if kubectl get namespace pre-prod >/dev/null 2>&1; then
    kubectl -n pre-prod get secrets
elif kubectl get namespace preprod >/dev/null 2>&1; then
    kubectl -n preprod get secrets
elif kubectl get namespace prod >/dev/null 2>&1; then
    kubectl -n prod get secrets
else
    echo "No pre-prod/preprod/prod namespace found."
fi

# ==================================================
# 9. Spaces Configuration
# ==================================================

echo
echo "=================================================="
echo "9. DigitalOcean Spaces"
echo "=================================================="

echo
echo "Spaces buckets:"

doctl spaces list || {
    echo "WARNING: Unable to list Spaces."
}

# ==================================================
# 10. Terraform Outputs
# ==================================================

echo
echo "=================================================="
echo "10. Terraform Outputs"
echo "=================================================="

if command -v terraform >/dev/null 2>&1; then
    echo
    echo "Terraform outputs:"

    terraform output -no-color 2>/dev/null || {
        echo "WARNING: Terraform outputs unavailable."
    }
else
    echo "WARNING: terraform command not found."
fi

# ==================================================
# 11. Pre-Prod Environment File
# ==================================================

echo
echo "=================================================="
echo "11. Pre-Prod Environment Configuration"
echo "=================================================="

ENV_FILE="$(pwd)/.env.preprod"

if [ -f "$ENV_FILE" ]; then
    echo
    echo "Environment file:"
    echo "$ENV_FILE"

    echo
    echo "Configured variable names:"

    grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$ENV_FILE" |
        sed 's/=.*$/=<configured>/' |
        sort
else
    echo "WARNING: .env.preprod not found."
fi

# ==================================================
# 12. Kubernetes Workloads
# ==================================================

echo
echo "=================================================="
echo "12. Kubernetes Workloads"
echo "=================================================="

echo
echo "All namespaces:"
kubectl get namespaces

echo
echo "All deployments:"
kubectl get deployments --all-namespaces -o wide || true

echo
echo "All pods:"
kubectl get pods --all-namespaces -o wide || true

echo
echo "All services:"
kubectl get services --all-namespaces -o wide || true

# ==================================================
# 13. Cluster Health
# ==================================================

echo
echo "=================================================="
echo "13. Cluster Health"
echo "=================================================="

echo
echo "Nodes:"
kubectl get nodes

echo
echo "Cluster info:"
kubectl cluster-info

echo
echo "API server:"
kubectl get --raw='/version' 2>/dev/null || true

# ==================================================
# 14. Final Verification
# ==================================================

echo
echo "=================================================="
echo "14. Final Verification"
echo "=================================================="

echo
echo "Cluster:"
echo "$CLUSTER_NAME"

echo "Expected context:"
echo "$EXPECTED_CONTEXT"

echo "Actual context:"
kubectl config current-context

echo
echo "Kubernetes API:"
kubectl cluster-info >/dev/null

echo "Kubernetes API: OK"

echo
echo "DigitalOcean API:"
doctl account get --format Email,Status --no-header

echo
echo "DigitalOcean API: OK"

echo
echo "=================================================="
echo "     PRE-PROD VERIFICATION COMPLETED"
echo "=================================================="