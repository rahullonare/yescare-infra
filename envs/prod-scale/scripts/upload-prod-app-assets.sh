#!/usr/bin/env bash
# =============================================================================
# upload-prod-app-assets.sh — seed static app assets into the PROD Spaces bucket
# =============================================================================
# Fixes "missing icons" on a fresh prod: the DB carries relative object keys
# (e.g. speciality.image_url = 'specialities/general-surgery.svg') but a freshly
# created bucket has none of the objects. This uploads the versioned assets in
# this repo (assets/prod-app-bucket/{app,specialities,wellness_tips}) to the
# prod app bucket so those keys resolve.
#
# The assets in this repo are the source of truth (copied from bucket
# `prod-yescare-app`). Re-run any time to re-seed a rebuilt bucket.
#
# CREDENTIALS — a Spaces key with readwrite on the destination bucket. Export
# before running (either name works):
#   export AWS_ACCESS_KEY_ID=...        AWS_SECRET_ACCESS_KEY=...
#   export DO_SPACES_ACCESS_KEY=...     DO_SPACES_SECRET_KEY=...   # auto-mapped
#
# USAGE:
#   ./upload-prod-app-assets.sh [--acl private|public-read] [--dry-run]
#     --acl       canned ACL for uploaded objects (default: private — matches the
#                 source bucket; the app serves these via the backend, not public read)
#     --dry-run   show what would upload, change nothing
#
# Override target via env: PROD_SPACES_BUCKET (default yescare-app-prod-prodv1),
# SPACES_REGION (default sgp1).
# =============================================================================
set -euo pipefail

BUCKET="${PROD_SPACES_BUCKET:-yescare-app-prod-prodv1}"
REGION="${SPACES_REGION:-sgp1}"
ENDPOINT="https://${REGION}.digitaloceanspaces.com"
ACL="private"
DRY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --acl)     ACL="${2:?--acl needs a value}"; shift 2 ;;
    --dry-run) DRY="--dryrun"; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

# Accept DO_SPACES_* as an alias for AWS_*
: "${AWS_ACCESS_KEY_ID:=${DO_SPACES_ACCESS_KEY:-}}"
: "${AWS_SECRET_ACCESS_KEY:=${DO_SPACES_SECRET_KEY:-}}"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION="$REGION"
if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  echo "ERROR: set AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY (or DO_SPACES_ACCESS_KEY/DO_SPACES_SECRET_KEY)" >&2
  exit 1
fi
command -v aws >/dev/null || { echo "ERROR: aws CLI not found" >&2; exit 1; }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../assets/prod-app-bucket" && pwd)"
echo "Source : $DIR"
echo "Target : s3://$BUCKET  (endpoint $ENDPOINT, acl=$ACL)${DRY:+  [DRY-RUN]}"

for p in app specialities wellness_tips; do
  if [ ! -d "$DIR/$p" ]; then echo "  skip $p/ (not present)"; continue; fi
  echo "== sync $p/ =="
  # aws guesses Content-Type from extension (svg -> image/svg+xml, png, jpeg).
  aws --endpoint-url "$ENDPOINT" s3 sync "$DIR/$p/" "s3://$BUCKET/$p/" \
      --acl "$ACL" --no-progress $DRY
done

echo "Done. Verify (needs read creds or public ACL):"
echo "  aws --endpoint-url $ENDPOINT s3 ls s3://$BUCKET/specialities/ | head"
