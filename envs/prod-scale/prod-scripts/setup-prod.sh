#!/usr/bin/env bash
# =============================================================================
# setup-prod.sh — build the ENTIRE prod environment end to end (Tier 0).
# One command, no manual steps. Config lives in prod.env.
#
# Before running, export the secrets (the only manual input):
#   export TF_VAR_do_token=...            # DigitalOcean API token
#   export TF_VAR_spaces_access_id=...    # Spaces key (terraform state backend)
#   export TF_VAR_spaces_secret_key=...
#   export ADMIN_PIN=<private-pin>        # optional; default 123456 (rotate!)
# and be authenticated: `doctl auth init`, `gh auth login`.
#
# Usage:
#   ./setup-prod.sh                 # run all stages in order
#   ./setup-prod.sh --list          # list stages with indexes
#   ./setup-prod.sh --from 8        # resume from stage 8
#   ./setup-prod.sh --only 11       # run just one stage
# =============================================================================
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"; source "$DIR/prod.env"

STAGES=(
  "00-preflight.sh"          # 0  tools/auth/secrets present
  "01-terraform-apply.sh"    # 1  cluster + PG + Redis + Spaces bucket + VPC
  "02-platform-addons.sh"    # 2  ingress-nginx + cert-manager + letsencrypt-prod
  "03-app-spaces-key.sh"     # 3  dedicated app Spaces key -> prod.secrets
  "setup-kafka-prod.sh"      # 4  in-cluster Kafka (3-broker RF=3) + topics
  "setup-db-prod.sh"         # 5  per-service schema grants
  "db-config-prod.sh"        # 6  managed-DB tuning (valkey idle timeout off)
  "update-secrets-prod.sh"   # 7  GitHub secrets CD cutover (incl. Spaces creds)
  "deploy-services-prod.sh"  # 8  deploy the 6 backend services
  "04-monitoring.sh"         # 9  scale nodes + observability stack
  "05-ingress-dns-tls.sh"    # 10 LB IP -> apiprod + grafana DNS + TLS
  "06-seed-admin.sh"         # 11 SUPER_ADMIN login in auth_db
  "07-point-web.sh"          # 12 website -> prod backend (apiprod)
  "08-upload-assets.sh"      # 13 seed app assets (fixes icons)
  "verify-prod.sh"           # 14 read-only verification
)

FROM=0; ONLY=""
while [ $# -gt 0 ]; do case "$1" in
  --from) FROM="$2"; shift 2 ;;
  --only) ONLY="$2"; shift 2 ;;
  --list) for i in "${!STAGES[@]}"; do printf "  %2d  %s\n" "$i" "${STAGES[$i]}"; done; exit 0 ;;
  -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
  *) echo "unknown arg: $1" >&2; exit 1 ;;
esac; done

echo "############################################################"
echo "# PROD SETUP — cluster $PROD_CLUSTER ($PROD_REGION)"
echo "############################################################"
for i in "${!STAGES[@]}"; do
  [ -n "$ONLY" ] && [ "$ONLY" != "$i" ] && continue
  { [ -z "$ONLY" ] && [ "$i" -lt "$FROM" ]; } && continue
  s="${STAGES[$i]}"
  echo; echo "==================== STAGE $i: $s ===================="
  bash "$DIR/$s"
done

echo; echo "############################################################"
echo "# DONE. API https://$PROD_API_HOST | Web https://www.$PROD_DOMAIN | Grafana https://$GRAFANA_HOST"
echo "############################################################"
