#!/usr/bin/env bash
# Grant schema ownership to each service user on the PROD Postgres.
# Prod-only. Portable (no grep -oP — uses doctl connection fields).
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/prod.env"

echo "=== [PROD] DB permissions on $PROD_PG_NAME ==="
DOADMIN_PW="$(doctl databases user get "$PROD_PG_ID" doadmin --no-header --format Password)"
PG_HOST="$(doctl databases connection "$PROD_PG_ID" --no-header --format Host)"
PG_PORT="$(doctl databases connection "$PROD_PG_ID" --no-header --format Port)"
echo "PG_HOST=$PG_HOST  PG_PORT=$PG_PORT"

kubectl --context "$PROD_CONTEXT" create namespace "$PROD_NS" --dry-run=client -o yaml | kubectl --context "$PROD_CONTEXT" apply -f -

kubectl --context "$PROD_CONTEXT" run psql-grants --image=postgres:16 --restart=Never -n "$PROD_NS" \
  --env="PGPASSWORD=$DOADMIN_PW" --env="PG_HOST=$PG_HOST" --env="PG_PORT=$PG_PORT" \
  -- bash -c '
set -e
psql "sslmode=require host=$PG_HOST port=$PG_PORT dbname=payment_db user=doadmin" -c "GRANT ALL ON SCHEMA public TO payment_user; ALTER SCHEMA public OWNER TO payment_user;"
psql "sslmode=require host=$PG_HOST port=$PG_PORT dbname=hospital_db user=doadmin" -c "GRANT ALL ON SCHEMA public TO hospital_user; ALTER SCHEMA public OWNER TO hospital_user;"
psql "sslmode=require host=$PG_HOST port=$PG_PORT dbname=yescareprod user=doadmin" -c "GRANT ALL ON SCHEMA public TO yescare_app; ALTER SCHEMA public OWNER TO yescare_app;"
psql "sslmode=require host=$PG_HOST port=$PG_PORT dbname=notification_service_db user=doadmin" -c "GRANT ALL ON SCHEMA public TO notification_user; ALTER SCHEMA public OWNER TO notification_user;"
psql "sslmode=require host=$PG_HOST port=$PG_PORT dbname=auth_db user=doadmin" -c "GRANT ALL ON SCHEMA public TO auth_user; ALTER SCHEMA public OWNER TO auth_user;"
echo ALL_GRANTS_DONE
'

echo "Waiting for grants pod..."
kubectl --context "$PROD_CONTEXT" wait --for=jsonpath='{.status.phase}'=Succeeded pod/psql-grants -n "$PROD_NS" --timeout=120s || true
kubectl --context "$PROD_CONTEXT" logs -n "$PROD_NS" psql-grants || true
kubectl --context "$PROD_CONTEXT" delete pod psql-grants -n "$PROD_NS" --ignore-not-found
echo "=== [PROD] DB permissions complete ==="
