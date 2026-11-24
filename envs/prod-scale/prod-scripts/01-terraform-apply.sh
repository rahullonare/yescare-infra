#!/usr/bin/env bash
# Stage 01 — terraform init (ISOLATED state key) + apply, then assert infra exists
# and save the kubeconfig/context. Tolerates the known preprod-hardcoded
# null_resource post-step failure (infra still applies; we finish via the scripts).
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/prod.env"
TFDIR="$(cd "$DIR/.." && pwd)"
echo "=== [01] Terraform ($TFDIR) ==="
cd "$TFDIR"
terraform init -reconfigure \
  -backend-config="access_key=$TF_VAR_spaces_access_id" \
  -backend-config="secret_key=$TF_VAR_spaces_secret_key" \
  -backend-config="key=$TF_STATE_KEY"
terraform apply -auto-approve -var-file="$TFVARS_FILE" \
  || echo "  (apply reported errors — expected on the preprod null_resources; verifying infra…)"

echo "-- asserting core infra exists --"
doctl kubernetes cluster get "$PROD_CLUSTER" >/dev/null 2>&1 && echo "  ok: cluster $PROD_CLUSTER" || { echo "  ERROR: cluster missing"; exit 1; }
doctl databases list --no-header --format Name | grep -qx "$PROD_PG_NAME"    && echo "  ok: pg $PROD_PG_NAME"       || { echo "  ERROR: pg missing"; exit 1; }
doctl databases list --no-header --format Name | grep -qx "$PROD_REDIS_NAME" && echo "  ok: redis $PROD_REDIS_NAME" || { echo "  ERROR: redis missing"; exit 1; }

echo "-- saving kubeconfig / context --"
doctl kubernetes cluster kubeconfig save "$PROD_CLUSTER" --set-current-context
echo "[01] done"
