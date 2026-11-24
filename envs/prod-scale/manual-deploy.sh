#!/bin/bash
set -e

echo "=== Manual Deploy - No GitHub Actions needed ==="

# Switch to prod cluster
doctl kubernetes cluster kubeconfig save yescare-preprod-scale-k8s --set-current-context

# Get prod credentials
PG_CLUSTER_ID=$(doctl databases list --no-header --format ID,Name | grep "yescare-pre-prod-scale-pg" | awk '{print $1}')
REDIS_CLUSTER_ID=$(doctl databases list --no-header --format ID,Name | grep "yescare-pre-prod-scale-redis" | awk '{print $1}')

PG_HOST=$(doctl databases get $PG_CLUSTER_ID --format URI --no-header | grep -oP '(?<=@)[^:]+')
REDIS_HOST=$(doctl databases get $REDIS_CLUSTER_ID --format URI --no-header | grep -oP '(?<=@)[^:]+')
REDIS_PW=$(doctl databases get $REDIS_CLUSTER_ID --format URI --no-header | grep -oP '(?<=:)[^:@]+(?=@)')
YESCARE_APP_PW=$(doctl databases user get $PG_CLUSTER_ID yescare_app --no-header --format Password)
HOSPITAL_PW=$(doctl databases user get $PG_CLUSTER_ID hospital_user --no-header --format Password)
PAYMENT_PW=$(doctl databases user get $PG_CLUSTER_ID payment_user --no-header --format Password)
NOTIFICATION_PW=$(doctl databases user get $PG_CLUSTER_ID notification_user --no-header --format Password)
KAFKA="kafka.messaging.svc.cluster.local:9092"

echo "Credentials fetched!"
echo "PG_HOST: $PG_HOST"
echo "REDIS_HOST: $REDIS_HOST"

# Create prod namespace
kubectl create namespace prod --dry-run=client -o yaml | kubectl apply -f -

# Create GHCR pull secret using dev cluster token
echo "Creating GHCR pull secret..."
kubectl config use-context do-sgp1-dev-doks > /dev/null 2>&1
GHCR_TOKEN=$(kubectl -n dev get secret ghcr-pull -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | grep -oP '(?<="password":")[^"]+')
GHCR_USER=$(kubectl -n dev get secret ghcr-pull -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | grep -oP '(?<="username":")[^"]+')
doctl kubernetes cluster kubeconfig save yescare-preprod-scale-k8s --set-current-context > /dev/null 2>&1

kubectl create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io \
  --docker-username=$GHCR_USER \
  --docker-password=$GHCR_TOKEN \
  --namespace=prod \
  --dry-run=client -o yaml | kubectl apply -f -

# Copy secrets from dev and patch with prod values
echo "Copying secrets from dev..."
kubectl config use-context do-sgp1-dev-doks > /dev/null 2>&1

for SECRET in auth-service-secret hospital-service-secret payment-service-secret notification-service-secret user-bff-secret websocket-gateway-secret; do
  kubectl -n dev get secret $SECRET -o go-template='{{range $k,$v := .data}}--from-literal={{$k}}="{{$v | base64decode}}" {{end}}' | \
  xargs kubectl --context do-sgp1-yescare-preprod-scale-k8s create secret generic $SECRET -n prod --dry-run=client -o yaml | \
  kubectl --context do-sgp1-yescare-preprod-scale-k8s apply -f -
done

doctl kubernetes cluster kubeconfig save yescare-preprod-scale-k8s --set-current-context > /dev/null 2>&1

# Patch all secrets with correct prod values
echo "Patching secrets with prod values..."
PG_B64=$(echo -n "$PG_HOST" | base64 -w 0)
REDIS_B64=$(echo -n "$REDIS_HOST" | base64 -w 0)
REDIS_PW_B64=$(echo -n "$REDIS_PW" | base64 -w 0)
YESCARE_PW_B64=$(echo -n "$YESCARE_APP_PW" | base64 -w 0)
HOSPITAL_PW_B64=$(echo -n "$HOSPITAL_PW" | base64 -w 0)
PAYMENT_PW_B64=$(echo -n "$PAYMENT_PW" | base64 -w 0)
NOTIFICATION_PW_B64=$(echo -n "$NOTIFICATION_PW" | base64 -w 0)
KAFKA_B64=$(echo -n "$KAFKA" | base64 -w 0)
REDIS_PORT_B64=$(echo -n "25061" | base64 -w 0)
AUTH_DB_USER_B64=$(echo -n "yescare_app" | base64 -w 0)

kubectl -n prod patch secret auth-service-secret -p "{\"data\":{\"DB_HOST\":\"$PG_B64\",\"DB_USER\":\"$AUTH_DB_USER_B64\",\"DB_PASSWORD\":\"$YESCARE_PW_B64\",\"REDIS_HOST\":\"$REDIS_B64\",\"REDIS_PORT\":\"$REDIS_PORT_B64\",\"REDIS_PASSWORD\":\"$REDIS_PW_B64\"}}"
kubectl -n prod patch secret hospital-service-secret -p "{\"data\":{\"DB_HOST\":\"$PG_B64\",\"DB_PASSWORD\":\"$HOSPITAL_PW_B64\",\"REDIS_HOST\":\"$REDIS_B64\",\"REDIS_PORT\":\"$REDIS_PORT_B64\",\"REDIS_PASSWORD\":\"$REDIS_PW_B64\",\"KAFKA_BOOTSTRAP_SERVERS\":\"$KAFKA_B64\"}}"
kubectl -n prod patch secret payment-service-secret -p "{\"data\":{\"DB_HOST\":\"$PG_B64\",\"DB_PASSWORD\":\"$PAYMENT_PW_B64\",\"REDIS_HOST\":\"$REDIS_B64\",\"REDIS_PORT\":\"$REDIS_PORT_B64\",\"REDIS_PASSWORD\":\"$REDIS_PW_B64\",\"KAFKA_BOOTSTRAP_SERVERS\":\"$KAFKA_B64\"}}"
kubectl -n prod patch secret notification-service-secret -p "{\"data\":{\"DB_HOST\":\"$PG_B64\",\"DB_PASSWORD\":\"$NOTIFICATION_PW_B64\",\"REDIS_HOST\":\"$REDIS_B64\",\"REDIS_PORT\":\"$REDIS_PORT_B64\",\"REDIS_PASSWORD\":\"$REDIS_PW_B64\",\"KAFKA_BOOTSTRAP_SERVERS\":\"$KAFKA_B64\"}}"
kubectl -n prod patch secret websocket-gateway-secret -p "{\"data\":{\"REDIS_HOST\":\"$REDIS_B64\",\"REDIS_PORT\":\"$REDIS_PORT_B64\",\"REDIS_PASSWORD\":\"$REDIS_PW_B64\",\"KAFKA_BOOTSTRAP_SERVERS\":\"$KAFKA_B64\"}}"

echo "Secrets patched!"

# Deploy services from dev manifests
echo "Deploying services..."
kubectl config use-context do-sgp1-dev-doks > /dev/null 2>&1

for SERVICE in auth-service hospital-service payment-service notification-service user-bff websocket-gateway; do
  kubectl -n dev get deployment $SERVICE -o yaml | \
    sed 's/namespace: dev/namespace: prod/g' | \
    sed "s|ghcr.io/yescare-tech/${SERVICE}:v1.0.0|ghcr.io/yescare-tech/${SERVICE}:latest|g" | \
    grep -v "resourceVersion\|uid:\|creationTimestamp\|generation:\|selfLink" \
    > /tmp/${SERVICE}-deployment.yaml
done

doctl kubernetes cluster kubeconfig save yescare-preprod-scale-k8s --set-current-context > /dev/null 2>&1

for SERVICE in auth-service hospital-service payment-service notification-service user-bff websocket-gateway; do
  kubectl apply -f /tmp/${SERVICE}-deployment.yaml
  kubectl -n prod patch deployment $SERVICE -p '{"spec":{"template":{"spec":{"containers":[{"name":"'$SERVICE'","env":[{"name":"SPRING_PROFILES_ACTIVE","value":"prod"}]}]}}}}'
done
# Fix Flyway out-of-order for payment-service
kubectl -n prod set env deployment/payment-service SPRING_FLYWAY_OUT_OF_ORDER=true SPRING_FLYWAY_REPAIR_ON_MIGRATE=true 2>/dev/null || true

# Create ClusterIP services
echo "Creating ClusterIP services..."
kubectl create service clusterip auth-service --tcp=80:8080 -n prod --dry-run=client -o yaml | kubectl apply -f -
kubectl create service clusterip hospital-service --tcp=80:8080 -n prod --dry-run=client -o yaml | kubectl apply -f -
kubectl create service clusterip payment-service --tcp=80:8080 -n prod --dry-run=client -o yaml | kubectl apply -f -
kubectl create service clusterip notification-service --tcp=80:8080 -n prod --dry-run=client -o yaml | kubectl apply -f -
kubectl create service clusterip user-bff --tcp=80:8080 -n prod --dry-run=client -o yaml | kubectl apply -f -
kubectl create service clusterip websocket-gateway --tcp=80:8080 --tcp=9001:9000 -n prod --dry-run=client -o yaml | kubectl apply -f -

# Apply ingress
echo "Applying ingress..."
export K8S_NAMESPACE="prod"
export INGRESS_HOST="api.yescare.co.in"
envsubst < ~/yescare-backend/k8s/ingress.yml | kubectl apply -f -

echo "=== Waiting 350s for services to start ==="
sleep 350
kubectl get pods -n prod

set +e
# Deploy monitoring stack
echo "Deploying monitoring..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f ~/yescare-infra/digitalocean/envs/prod-scale/monitoring/rbac/ --force
kubectl apply --force -f ~/yescare-infra/digitalocean/envs/prod-scale/monitoring/configmaps/

# Fix Loki/Tempo PVCs
kubectl delete pvc loki-data tempo-data -n monitoring --force --grace-period=0 2>/dev/null || true
sleep 5

kubectl apply -f - <<PVCEOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: loki-data
  namespace: monitoring
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: do-block-storage
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: tempo-data
  namespace: monitoring
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: do-block-storage
PVCEOF

sleep 10
kubectl apply --force -f ~/yescare-infra/digitalocean/envs/prod-scale/monitoring/deployments/
echo "=== Monitoring deployed ==="
set -e

kubectl get pods -n monitoring
echo "=== Manual Deploy Complete ==="

# Create ClusterIssuer for Let's Encrypt
echo "Creating ClusterIssuer..."
kubectl apply -f - <<CERTEOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: yescaretech@gmail.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
CERTEOF
echo "=== ClusterIssuer created ==="

# Create admin users in auth_db
echo "Creating admin users..."
PG_CLUSTER_ID=$(doctl databases list --no-header --format ID,Name | grep "yescare-pre-prod-scale-pg" | awk '{print $1}')
AUTH_PW=$(doctl databases user get $PG_CLUSTER_ID yescare_app --no-header --format Password)
PG_HOST=$(doctl databases get $PG_CLUSTER_ID --format URI --no-header | grep -oP '(?<=@)[^:]+')

kubectl run psql-admin --image=postgres:15 --restart=Never -n prod -- sleep 300
kubectl wait --for=condition=ready pod/psql-admin -n prod --timeout=60s

kubectl exec -n prod psql-admin -- psql \
  "postgresql://yescare_app:${AUTH_PW}@${PG_HOST}:25060/auth_db?sslmode=require" \
  -c "
CREATE EXTENSION IF NOT EXISTS pgcrypto;
WITH new_admin AS (
  INSERT INTO users (phone_number, status, user_type, admin_scope)
  VALUES ('9000000001', 'ACTIVE'::user_status_enum, 'ADMIN'::user_type_enum, 'SUPER_ADMIN')
  ON CONFLICT (phone_number) DO UPDATE SET status = 'ACTIVE'::user_status_enum
  RETURNING id
)
INSERT INTO user_credentials (user_id, pin_hash, failed_attempts)
SELECT id, crypt('089908', gen_salt('bf')), 0
FROM new_admin
ON CONFLICT (user_id) DO UPDATE SET pin_hash = crypt('089908', gen_salt('bf'));
SELECT u.phone_number, u.user_type, u.admin_scope, (c.user_id IS NOT NULL) AS has_credentials FROM users u LEFT JOIN user_credentials c ON c.user_id = u.id WHERE u.phone_number = '9000000001';
"

kubectl delete pod psql-admin -n prod
echo "=== Admin users created ==="

# Remove V9 from flyway_schema_history if it exists (V9 file deleted - was causing fresh install failures)
echo "Cleaning up V9 Flyway history..."
PW=$(kubectl -n prod get secret payment-service-secret -o jsonpath='{.data.DB_PASSWORD}' | base64 -d)
DB_HOST=$(kubectl -n prod get secret payment-service-secret -o jsonpath='{.data.DB_HOST}' | base64 -d)
kubectl run flyway-cleanup --rm -it --restart=Never \
  --image=postgres:16 -n prod \
  --env="PGPASSWORD=$PW" \
  -- psql "host=$DB_HOST port=25060 dbname=payment_db user=payment_user sslmode=require" \
  -c "DELETE FROM flyway_schema_history WHERE version='9';" 2>/dev/null || true
echo "Flyway V9 cleanup done"

# Remove V9 from flyway_schema_history if it exists (V9 file deleted - was causing fresh install failures)
echo "Cleaning up V9 Flyway history..."
PW=$(kubectl -n prod get secret payment-service-secret -o jsonpath='{.data.DB_PASSWORD}' | base64 -d)
DB_HOST=$(kubectl -n prod get secret payment-service-secret -o jsonpath='{.data.DB_HOST}' | base64 -d)
kubectl run flyway-cleanup --rm -it --restart=Never \
  --image=postgres:16 -n prod \
  --env="PGPASSWORD=$PW" \
  -- psql "host=$DB_HOST port=25060 dbname=payment_db user=payment_user sslmode=require" \
  -c "DELETE FROM flyway_schema_history WHERE version='9';" 2>/dev/null || true
echo "Flyway V9 cleanup done"

# Apply Grafana ingress with TLS
echo "Applying Grafana ingress..."
kubectl apply -f ~/yescare-infra/digitalocean/envs/prod-scale/monitoring/grafana-ingress.yaml
echo "Grafana ingress applied — https://grafana.yescare.co.in"
