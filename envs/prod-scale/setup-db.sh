#!/bin/bash
set -e

echo "=== Setting up DB permissions ==="

PG_CLUSTER_ID=$(doctl databases list --no-header --format ID,Name | grep "yescare-pre-prod-scale-pg" | awk '{print $1}')
DOADMIN_PW=$(doctl databases user get $PG_CLUSTER_ID doadmin --no-header --format Password)
PG_HOST=$(doctl databases get $PG_CLUSTER_ID --format URI --no-header | grep -oP '(?<=@)[^:]+')

echo "PG_HOST: $PG_HOST"
kubectl create namespace prod --dry-run=client -o yaml | kubectl apply -f -
echo "Granting schema permissions to all service users..."

kubectl run psql-grants --image=postgres:16 --restart=Never -n prod \
  --env="PGPASSWORD=$DOADMIN_PW" \
  --env="PG_HOST=$PG_HOST" \
  -- bash -c '
psql "sslmode=require host=$PG_HOST port=25060 dbname=payment_db user=doadmin" -c "GRANT ALL ON SCHEMA public TO payment_user; ALTER SCHEMA public OWNER TO payment_user;"
psql "sslmode=require host=$PG_HOST port=25060 dbname=hospital_db user=doadmin" -c "GRANT ALL ON SCHEMA public TO hospital_user; ALTER SCHEMA public OWNER TO hospital_user;"
psql "sslmode=require host=$PG_HOST port=25060 dbname=yescareprod user=doadmin" -c "GRANT ALL ON SCHEMA public TO yescare_app; ALTER SCHEMA public OWNER TO yescare_app;"
psql "sslmode=require host=$PG_HOST port=25060 dbname=notification_service_db user=doadmin" -c "GRANT ALL ON SCHEMA public TO notification_user; ALTER SCHEMA public OWNER TO notification_user;"
psql "sslmode=require host=$PG_HOST port=25060 dbname=auth_db user=doadmin" -c "GRANT ALL ON SCHEMA public TO auth_user; ALTER SCHEMA public OWNER TO auth_user;"
echo ALL GRANTS DONE
'

# Wait for pod to complete
sleep 30
kubectl logs -n prod psql-grants
kubectl delete pod psql-grants -n prod --ignore-not-found

echo "=== DB permissions setup complete ==="
