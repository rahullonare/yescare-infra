```bash
#!/bin/bash
set -euo pipefail

echo "=== YesCare PRE-PROD LOCAL DEPLOYMENT ==="

NAMESPACE="pre-prod"
REGISTRY="ghcr.io/yescare-tech"

SERVICES=(
  "auth-service"
  "hospital-service"
  "payment-service"
  "notification-service"
  "user-bff"
  "websocket-gateway"
)

echo "=== Verifying Kubernetes context ==="

EXPECTED_CONTEXT="do-sgp1-yescare-pre-prod-scale-k8s"
CURRENT_CONTEXT="$(kubectl config current-context)"

echo "Current context: $CURRENT_CONTEXT"

if [ "$CURRENT_CONTEXT" != "$EXPECTED_CONTEXT" ]; then
  echo "ERROR: Wrong Kubernetes context."
  echo "Expected: $EXPECTED_CONTEXT"
  echo "Current:  $CURRENT_CONTEXT"
  exit 1
fi

echo "Kubernetes context verified."

echo
echo "=== Verifying namespace ==="

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || \
  kubectl create namespace "$NAMESPACE"

echo "Namespace verified: $NAMESPACE"

echo
echo "=== Verifying Docker ==="

docker info >/dev/null 2>&1 || {
  echo "ERROR: Docker is not running."
  exit 1
}

echo "Docker verified."

echo
echo "=== Building application JARs ==="

./gradlew clean build -x test

echo
echo "=== Building and pushing Docker images ==="

for SERVICE in "${SERVICES[@]}"; do

  IMAGE="$REGISTRY/$SERVICE:pre-prod"

  echo
  echo "========================================"
  echo "Service: $SERVICE"
  echo "Image:   $IMAGE"
  echo "========================================"

  docker build \
    -t "$IMAGE" \
    -f "services/$SERVICE/Dockerfile" \
    .

  docker push "$IMAGE"

done

echo
echo "=== Applying Kubernetes manifests ==="

kubectl apply -k k8s/overlays/pre-prod

echo
echo "=== Updating deployment images ==="

for SERVICE in "${SERVICES[@]}"; do

  IMAGE="$REGISTRY/$SERVICE:pre-prod"

  kubectl -n "$NAMESPACE" set image \
    deployment/"$SERVICE" \
    "$SERVICE"="$IMAGE"

done

echo
echo "=== Waiting for rollouts ==="

for SERVICE in "${SERVICES[@]}"; do

  echo "Waiting for $SERVICE..."

  kubectl -n "$NAMESPACE" rollout status \
    deployment/"$SERVICE" \
    --timeout=420s

done

echo
echo "=== Final deployment status ==="

kubectl -n "$NAMESPACE" get deployments
echo
kubectl -n "$NAMESPACE" get pods -o wide
echo
kubectl -n "$NAMESPACE" get services

echo
echo "=== PRE-PROD LOCAL DEPLOYMENT COMPLETE ==="
```

---

### 2. Terraform `null_resource`

Add this separately in your Terraform file:

```hcl
# Deploy all services locally after infrastructure and DB setup
resource "null_resource" "deploy_services" {
  triggers = {
    cluster_id = module.kubernetes.cluster_id
  }

  provisioner "local-exec" {
    command     = "bash ${path.module}/deploy-services.sh"
    working_dir = path.module
  }

  depends_on = [
    null_resource.setup_db,
    null_resource.verify
  ]
}
```

### Before running Terraform

Check whether this directory actually exists:

```powershell
Test-Path .\k8s\overlays\pre-prod
```

And check your actual Kubernetes namespace:

```powershell
kubectl get namespaces
```

I used `pre-prod` because this is your **pre-prod-scale** environment, but we should use your repo's actual namespace/manifests rather than assuming it.
