
#!/bin/bash
set -e
if [ -f "/mnt/c/Users/HP 745 G6/.kube/config" ]; then
  export KUBECONFIG="/mnt/c/Users/HP 745 G6/.kube/config"
fi

echo "=== Setting up DB permissions ==="

# ============================================================
# CURRENT PRE-PROD INFRASTRUCTURE
# ============================================================
K8S_CLUSTER_ID="1b690c65-df36-4e0c-ae01-a31cbc4f9004"
PG_CLUSTER_ID="a5b49a1e-929a-4c99-9435-ab9d90681702"

K8S_CLUSTER_NAME="yescare-pre-prod-scale-k8s"
PG_CLUSTER_NAME="yescare-pre-prod-scale-pg"

echo "Kubernetes cluster:"
echo "  Name: $K8S_CLUSTER_NAME"
echo "  ID:   $K8S_CLUSTER_ID"

echo "PostgreSQL cluster:"
echo "  Name: $PG_CLUSTER_NAME"
echo "  ID:   $PG_CLUSTER_ID"

# ============================================================
# VERIFY KUBERNETES CONTEXT
# ============================================================
CURRENT_CONTEXT=$(kubectl config current-context)

echo
echo "Current kubectl context:"
echo "  $CURRENT_CONTEXT"

EXPECTED_CONTEXT="do-sgp1-yescare-pre-prod-scale-k8s"

if [ "$CURRENT_CONTEXT" != "$EXPECTED_CONTEXT" ]; then
  echo "ERROR: Wrong Kubernetes context."
  echo "Expected: $EXPECTED_CONTEXT"
  echo "Current:  $CURRENT_CONTEXT"
  exit 1
fi

echo "Kubernetes context verified."

# ============================================================
# VERIFY POSTGRESQL CLUSTER
# ============================================================
ACTUAL_PG_NAME=$(doctl databases get "$PG_CLUSTER_ID" --format Name --no-header)

if [ "$ACTUAL_PG_NAME" != "$PG_CLUSTER_NAME" ]; then
  echo "ERROR: PostgreSQL cluster ID does not match expected cluster."
  echo "Expected: $PG_CLUSTER_NAME"
  echo "Found:    $ACTUAL_PG_NAME"
  exit 1
fi

echo "PostgreSQL cluster verified."

# ============================================================
# GET DATABASE CREDENTIALS
# ============================================================
DOADMIN_PW=$(doctl databases user get "$PG_CLUSTER_ID" doadmin \
  --no-header --format Password)

PG_HOST=$(doctl databases get "$PG_CLUSTER_ID" \
  --format URI --no-header | grep -oP '(?<=@)[^:]+' | head -1)

echo
echo "PG_HOST: $PG_HOST"

# ============================================================
# CREATE PROD NAMESPACE
# ============================================================
kubectl create namespace pre-prod \
  --dry-run=client -o yaml |
  kubectl apply -f -

echo
echo "Granting schema permissions to all service users..."

# ============================================================
# CREATE TEMPORARY POSTGRES POD
# ============================================================
kubectl delete pod psql-grants -n pre-prod --ignore-not-found

kubectl run psql-grants \
  --image=postgres:16 \
  --restart=Never \
  -n pre-prod \
  --env="PGPASSWORD=$DOADMIN_PW" \
  --env="PG_HOST=$PG_HOST" \
  --command -- bash -c '
set -e 
export KUBECONFIG="/mnt/c/Users/HP 745 G6/.kube/config"

echo "Granting payment_db permissions..."
psql "sslmode=require host=$PG_HOST port=25060 dbname=payment_db user=doadmin" \
  -c "GRANT ALL ON SCHEMA public TO payment_user; ALTER SCHEMA public OWNER TO payment_user;"

echo "Granting hospital_db permissions..."
psql "sslmode=require host=$PG_HOST port=25060 dbname=hospital_db user=doadmin" \
  -c "GRANT ALL ON SCHEMA public TO hospital_user; ALTER SCHEMA public OWNER TO hospital_user;"

#echo "Granting yescareprod permissions..."
#psql "sslmode=require host=$PG_HOST port=25060 dbname=yescareprod user=doadmin" \
#  -c "GRANT ALL ON SCHEMA public TO yescare_app; ALTER SCHEMA public OWNER TO yescare_app;"

echo "Granting notification_service_db permissions..."
psql "sslmode=require host=$PG_HOST port=25060 dbname=notification_service_db user=doadmin" \
  -c "GRANT ALL ON SCHEMA public TO notification_user; ALTER SCHEMA public OWNER TO notification_user;"

echo "Granting auth_db permissions..."
psql "sslmode=require host=$PG_HOST port=25060 dbname=auth_db user=doadmin" \
  -c "GRANT ALL ON SCHEMA public TO auth_user; ALTER SCHEMA public OWNER TO auth_user;"

echo "Transferring ownership of existing objects to service users..."
for pair in auth_db:auth_user hospital_db:hospital_user notification_service_db:notification_user payment_db:payment_user; do
  db="${pair%%:*}"
  usr="${pair##*:}"
  echo "  $db -> $usr"
  psql "sslmode=require host=$PG_HOST port=25060 dbname=$db user=doadmin" \
    -c "GRANT $usr TO doadmin;"
  psql "sslmode=require host=$PG_HOST port=25060 dbname=$db user=doadmin" -c "
DO \$\$
DECLARE r record;
BEGIN
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = '"'"'public'"'"' LOOP
    EXECUTE format('"'"'ALTER TABLE public.%I OWNER TO %I'"'"', r.tablename, '"'"'$usr'"'"');
  END LOOP;
  FOR r IN SELECT sequencename FROM pg_sequences WHERE schemaname = '"'"'public'"'"' LOOP
    EXECUTE format('"'"'ALTER SEQUENCE public.%I OWNER TO %I'"'"', r.sequencename, '"'"'$usr'"'"');
  END LOOP;
  FOR r IN SELECT viewname FROM pg_views WHERE schemaname = '"'"'public'"'"' LOOP
    EXECUTE format('"'"'ALTER VIEW public.%I OWNER TO %I'"'"', r.viewname, '"'"'$usr'"'"');
  END LOOP;
END \$\$;"
done

echo "ALL GRANTS DONE"
'

# ============================================================
# WAIT FOR POD TO COMPLETE
# ============================================================
echo
echo "Waiting for DB permission setup to complete..."

kubectl wait \
  --for=jsonpath='{.status.phase}'=Succeeded \
  pod/psql-grants \
  -n pre-prod \
  --timeout=120s

echo
echo "=== DB GRANT LOGS ==="
kubectl logs -n pre-prod psql-grants

# ============================================================
# CLEANUP
# ============================================================
kubectl delete pod psql-grants \
  -n pre-prod \
  --ignore-not-found

echo
echo "=== DB permissions setup complete ==="
