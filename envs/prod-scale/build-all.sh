#!/bin/bash
set -e

echo "=== Building and pushing all YesCare services ==="

cd ~/yescare-backend
git pull origin main

# Login to GHCR using org token from dev cluster
GHCR_TOKEN=$(kubectl --context do-sgp1-dev-doks -n dev get secret ghcr-pull \
  -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | grep -oP '(?<="password":")[^"]+')
echo $GHCR_TOKEN | docker login ghcr.io -u YesCare-Tech --password-stdin

# Build all 6 in parallel
for SERVICE in auth-service hospital-service payment-service notification-service user-bff websocket-gateway; do
  (
    echo "Building $SERVICE..."
    ./gradlew :services:$SERVICE:build --no-daemon > /tmp/build-$SERVICE.log 2>&1
    docker buildx build \
      --platform linux/amd64 \
      -t ghcr.io/yescare-tech/$SERVICE:latest \
      -f services/$SERVICE/Dockerfile \
      services/$SERVICE >> /tmp/build-$SERVICE.log 2>&1
    docker push ghcr.io/yescare-tech/$SERVICE:latest >> /tmp/build-$SERVICE.log 2>&1
    echo "$SERVICE DONE" >> /tmp/build-$SERVICE.log
  ) &
  echo "Started $SERVICE"
done

echo "Waiting for all builds..."
wait
echo "All builds complete!"

# Check results
for SERVICE in auth-service hospital-service payment-service notification-service user-bff websocket-gateway; do
  echo "=== $SERVICE ==="
  tail -3 /tmp/build-$SERVICE.log
done

# Deploy to prod
echo "Deploying to prod..."
kubectl config use-context do-sgp1-yescare-preprod-scale-k8s
for SERVICE in auth-service hospital-service payment-service notification-service user-bff websocket-gateway; do
  kubectl rollout restart deployment/$SERVICE -n prod
done

sleep 30
kubectl get pods -n prod
echo "=== Build and Deploy Complete ==="
