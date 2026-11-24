#!/bin/bash

set -euo pipefail

# ============================================================
# YESCARE PRE-PROD DEPLOYMENT
# ============================================================

# ------------------------------------------------------------
# PRE-PROD TARGET
# ------------------------------------------------------------

CLUSTER="yescare-pre-prod-scale-k8s"
CONTEXT="do-sgp1-yescare-pre-prod-scale-k8s"
NAMESPACE="pre-prod"

# ------------------------------------------------------------
# BACKEND REPOSITORY
# ------------------------------------------------------------

BACKEND_DIR="/mnt/d/yescare_manual_deploy/yescare-backend"

# ------------------------------------------------------------
# PRE-PROD APPLICATION CONFIG
# ------------------------------------------------------------

ENV_FILE="/mnt/d/digitalocean/envs/prod-scale/pre-prod.env"

# ------------------------------------------------------------
# PRE-PROD INFRASTRUCTURE CONFIG
# Terraform-generated DB / Redis endpoints
# ------------------------------------------------------------

INFRA_ENV="/mnt/d/digitalocean/envs/prod-scale/.env.preprod"

# ------------------------------------------------------------
# GHCR
# ------------------------------------------------------------

REGISTRY="ghcr.io/yescare-tech"

# Windows kubectl.exe uses the Windows kubeconfig
KUBECTL="kubectl.exe"

# ------------------------------------------------------------
# SERVICES
# ------------------------------------------------------------

SERVICES=(
  auth-service
  hospital-service
  notification-service
  payment-service
  user-bff
  websocket-gateway
)

echo "========================================="
echo "YESCARE PRE-PROD DEPLOYMENT"
echo "========================================="
echo

# ============================================================
# 1. CHECK REQUIRED PATHS
# ============================================================

echo "=== Checking deployment paths ==="

if [ ! -d "$BACKEND_DIR" ]; then
  echo "ERROR: Backend directory not found:"
  echo "$BACKEND_DIR"
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: Pre-prod env file not found:"
  echo "$ENV_FILE"
  exit 1
fi

if [ ! -f "$INFRA_ENV" ]; then
  echo "ERROR: Pre-prod infrastructure env not found:"
  echo "$INFRA_ENV"
  exit 1
fi

echo "Backend : $BACKEND_DIR"
echo "App env : $ENV_FILE"
echo "Infra   : $INFRA_ENV"
echo

# ============================================================
# 2. LOAD PRE-PROD CONFIGURATION
# ============================================================

echo "=== Loading pre-prod configuration ==="

set -a
source "$ENV_FILE"
source "$INFRA_ENV"
set +a

# These values MUST come from Terraform-generated
# pre-prod infrastructure.

: "${DB_HOST:?DB_HOST is missing from $INFRA_ENV}"
: "${DB_PORT:?DB_PORT is missing from $INFRA_ENV}"
: "${REDIS_HOST:?REDIS_HOST is missing from $INFRA_ENV}"
: "${REDIS_PORT:?REDIS_PORT is missing from $INFRA_ENV}"

echo "Pre-prod DB host    : $DB_HOST"
echo "Pre-prod DB port    : $DB_PORT"
echo "Pre-prod Redis host : $REDIS_HOST"
echo "Pre-prod Redis port : $REDIS_PORT"
echo

# ============================================================
# 3. SELECT PRE-PROD KUBERNETES CONTEXT
# ============================================================

echo "=== Selecting pre-prod Kubernetes context ==="

"$KUBECTL" config use-context "$CONTEXT"

echo

# ============================================================
# 4. VERIFY KUBERNETES CONTEXT
# ============================================================

echo "=== Kubernetes context ==="

CURRENT_CONTEXT="$("$KUBECTL" config current-context)"

echo "Current context: $CURRENT_CONTEXT"

if [ "$CURRENT_CONTEXT" != "$CONTEXT" ]; then
  echo "ERROR: Wrong Kubernetes context"
  echo "Expected: $CONTEXT"
  echo "Actual  : $CURRENT_CONTEXT"
  exit 1
fi

echo

# ============================================================
# 5. CHECK PRE-PROD CLUSTER
# ============================================================

echo "=== Checking pre-prod cluster ==="

"$KUBECTL" get nodes

echo

# ============================================================
# 6. CREATE PRE-PROD NAMESPACE
# ============================================================

echo "=== Creating namespace ==="

"$KUBECTL" create namespace "$NAMESPACE" \
  --dry-run=client -o yaml |
"$KUBECTL" apply -f -

echo

# ============================================================
# 7. CHECK GHCR PULL SECRET
# ============================================================

echo "=== Checking GHCR pull secret ==="

if "$KUBECTL" get secret ghcr-pull -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "ghcr-pull exists in namespace $NAMESPACE"
else
  echo "ERROR: ghcr-pull does not exist in namespace $NAMESPACE"
  echo
  echo "Create the GHCR pull secret before deployment."
  exit 1
fi

echo

# ============================================================
# 8. BACKEND REPOSITORY
# ============================================================

cd "$BACKEND_DIR"

echo "=== Backend repository ==="

echo "Path:"
pwd

echo

echo "Branch:"
git branch --show-current

echo

echo "Git status:"
git status --short

echo

# ============================================================
# 9. DEPLOY SERVICES
# ============================================================

for SERVICE in "${SERVICES[@]}"; do

  TAG="preprod-$(date +%Y%m%d-%H%M%S)-${SERVICE}"

  IMAGE="${REGISTRY}/${SERVICE}:${TAG}"

  echo
  echo "========================================="
  echo "DEPLOYING: ${SERVICE}"
  echo "IMAGE: ${IMAGE}"
  echo "========================================="
  echo

  # ----------------------------------------------------------
  # BUILD JAR
  # ----------------------------------------------------------

  echo "=== Building JAR ==="

  ./gradlew ":services:${SERVICE}:build" --no-daemon

  # ----------------------------------------------------------
  # BUILD + PUSH DOCKER IMAGE
  # ----------------------------------------------------------

  echo
  echo "=== Building and pushing Docker image ==="

  docker buildx build \
    --platform linux/amd64 \
    --build-arg SERVICE_NAME="${SERVICE}" \
    -t "${IMAGE}" \
    -f "services/${SERVICE}/Dockerfile" \
    "services/${SERVICE}" \
    --push

  # ----------------------------------------------------------
  # APPLY SERVICE
  # ----------------------------------------------------------

  echo
  echo "=== Applying service ==="

  "$KUBECTL" apply \
    -n "$NAMESPACE" \
    -f "services/${SERVICE}/k8s/do-${SERVICE}/service.yml"

  # ----------------------------------------------------------
  # APPLY DEPLOYMENT
  # ----------------------------------------------------------

  echo
  echo "=== Applying deployment ==="

  export IMAGE

  # Existing DEV application code/profile
  # deployed onto PRE-PROD infrastructure.
  export SPRING_PROFILE="dev"

  envsubst '${IMAGE} ${SPRING_PROFILE}' \
    < "services/${SERVICE}/k8s/do-${SERVICE}/deployment.yml" |
  "$KUBECTL" apply \
    -n "$NAMESPACE" \
    -f -

  # ----------------------------------------------------------
  # WAIT FOR ROLLOUT
  # ----------------------------------------------------------

  echo
  echo "=== Waiting for rollout ==="

  "$KUBECTL" rollout status \
    "deployment/${SERVICE}" \
    -n "$NAMESPACE" \
    --timeout=420s

  echo
  echo "=== ${SERVICE} deployed successfully ==="

done

# ============================================================
# 10. FINAL STATUS
# ============================================================

echo
echo "========================================="
echo "PRE-PROD DEPLOYMENT COMPLETE"
echo "========================================="
echo

echo "=== Target ==="

echo "Cluster  : $CLUSTER"
echo "Context  : $CONTEXT"
echo "Namespace: $NAMESPACE"

echo "DB Host  : $DB_HOST"
echo "DB Port  : $DB_PORT"

echo "Redis    : $REDIS_HOST:$REDIS_PORT"

echo

echo "=== Deployments ==="

"$KUBECTL" get deployments \
  -n "$NAMESPACE"

echo

echo "=== Pods ==="

"$KUBECTL" get pods \
  -n "$NAMESPACE" \
  -o wide

echo

echo "=== Services ==="

"$KUBECTL" get services \
  -n "$NAMESPACE"

echo

echo "========================================="
echo "DONE"
echo "========================================="