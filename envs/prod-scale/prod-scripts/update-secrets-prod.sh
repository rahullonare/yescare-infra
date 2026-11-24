#!/usr/bin/env bash
# Update ALL prod GitHub Action secrets in the backend repo to point at the
# NEW prod cluster + prod DBs. This is the CD CUTOVER — after this, the backend
# repo's `deploy.yml environment=prod` deploys to yescare-prod-scale-k8s.
# Portable (base64 without -w0). Requires: gh auth login.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/prod.env"

echo "=== [PROD] Updating GitHub secrets in $PROD_BACKEND_REPO (CD CUTOVER) ==="

PG_HOST="$(doctl databases connection "$PROD_PG_ID"   --no-header --format Host)"
PG_PORT="$(doctl databases connection "$PROD_PG_ID"   --no-header --format Port)"
REDIS_HOST="$(doctl databases connection "$PROD_REDIS_ID" --no-header --format Host)"
REDIS_PW="$(doctl databases connection "$PROD_REDIS_ID"   --no-header --format Password)"

YESCARE_APP_PW="$(doctl databases user get "$PROD_PG_ID" yescare_app       --no-header --format Password)"
HOSPITAL_PW="$(doctl databases user get "$PROD_PG_ID" hospital_user        --no-header --format Password)"
PAYMENT_PW="$(doctl databases user get "$PROD_PG_ID" payment_user          --no-header --format Password)"
NOTIFICATION_PW="$(doctl databases user get "$PROD_PG_ID" notification_user --no-header --format Password)"

R="$PROD_BACKEND_REPO"
gh secret set PROD_DB_HOST                 --body "$PG_HOST"            --repo "$R"
gh secret set PROD_DB_PORT                 --body "$PG_PORT"            --repo "$R"
gh secret set PROD_DB_PASSWORD             --body "$YESCARE_APP_PW"     --repo "$R"
gh secret set PROD_AUTH_DB_PASSWORD        --body "$YESCARE_APP_PW"     --repo "$R"
gh secret set PROD_HOSPITAL_DB_PASSWORD    --body "$HOSPITAL_PW"        --repo "$R"
gh secret set PROD_PAYMENT_DB_PASSWORD     --body "$PAYMENT_PW"         --repo "$R"
gh secret set PROD_NOTIFICATION_DB_PASSWORD --body "$NOTIFICATION_PW"   --repo "$R"
gh secret set PROD_NOTIFICATION_DB_HOST    --body "$PG_HOST"            --repo "$R"
gh secret set PROD_NOTIFICATION_DB_PORT    --body "$PG_PORT"            --repo "$R"
gh secret set PROD_REDIS_HOST              --body "$REDIS_HOST"         --repo "$R"
gh secret set PROD_REDIS_PASSWORD          --body "$REDIS_PW"           --repo "$R"
gh secret set PROD_S3_BUCKET               --body "$PROD_SPACES_BUCKET" --repo "$R"
gh secret set DOKS_PROD_CLUSTER_NAME       --body "$PROD_CLUSTER"       --repo "$R"

# App Spaces credentials (from prod.secrets, created by 03-app-spaces-key.sh).
# Without these the app signs uploads with a stale/revoked key -> S3 403 (see RUNBOOK §7.8).
if [ -n "${APP_SPACES_ACCESS_KEY:-}" ] && [ -n "${APP_SPACES_SECRET_KEY:-}" ]; then
  for k in PROD_SPACES_ACCESS_KEY DO_SPACES_ACCESS_KEY PROD_DO_SPACES_ACCESS_KEY; do
    gh secret set "$k" --body "$APP_SPACES_ACCESS_KEY" --repo "$R"
  done
  for k in PROD_SPACES_SECRET_KEY DO_SPACES_SECRET_KEY PROD_DO_SPACES_SECRET_KEY; do
    gh secret set "$k" --body "$APP_SPACES_SECRET_KEY" --repo "$R"
  done
  echo "  set Spaces access/secret GitHub secrets from prod.secrets"
else
  echo "  WARN: APP_SPACES_* not set — Spaces creds NOT rotated (run 03-app-spaces-key.sh first)"
fi

KUBECONFIG_B64="$(doctl kubernetes cluster kubeconfig show "$PROD_CLUSTER" | base64 | tr -d '\n')"
gh secret set KUBE_CONFIG_PROD --body "$KUBECONFIG_B64" --repo "$R"

echo "=== [PROD] All GitHub secrets updated -> new prod cluster ==="
