#!/bin/bash
set -e

echo "=== Deploying all YesCare services to prod ==="

REPO="YesCare-Tech/yescare-backend"
SERVICES=("auth-service" "hospital-service" "payment-service" "notification-service" "user-bff" "websocket-gateway")

# Try GitHub Actions first
echo "Attempting GitHub Actions deployment..."
PIPELINE_FAILED=false

for SERVICE in "${SERVICES[@]}"; do
  echo "Triggering deploy for $SERVICE..."
  RUN_OUTPUT=$(gh workflow run deploy.yml \
    --repo $REPO \
    --field environment=prod \
    --field service=$SERVICE \
    --field image_tag=latest 2>&1)
  
  if echo "$RUN_OUTPUT" | grep -q "failed\|error\|billing\|payment"; then
    echo "GitHub Actions failed for $SERVICE — will use manual deploy"
    PIPELINE_FAILED=true
    break
  fi
  sleep 2
done

# Wait and check if pipelines succeeded
if [ "$PIPELINE_FAILED" = false ]; then
  echo "Waiting 900s for pipelines to complete..."
  sleep 900
  
  # Check if pods are running
  RUNNING=$(kubectl get pods -n prod --no-headers | grep "1/1" | wc -l)
  if [ "$RUNNING" -lt 6 ]; then
    echo "Pipelines ran but pods not healthy — falling back to manual deploy"
    PIPELINE_FAILED=true
  fi
fi

# Fall back to manual deploy if GitHub Actions failed
if [ "$PIPELINE_FAILED" = true ]; then
  echo "=== Falling back to manual deployment ==="
  bash "$(dirname "$0")/manual-deploy.sh"
else
  echo "=== GitHub Actions deployment successful ==="
  kubectl get pods -n prod
fi

echo "=== Deploy complete ==="
