#!/bin/bash
set -e

echo "=== Updating GitHub secrets from Terraform outputs ==="

PG_CLUSTER_ID=$(doctl databases list --no-header --format ID,Name | grep "yescare-pre-prod-scale-pg" | awk '{print $1}')
REDIS_CLUSTER_ID=$(doctl databases list --no-header --format ID,Name | grep "yescare-pre-prod-scale-redis" | awk '{print $1}')

# Get hosts via URI parsing
PG_HOST=$(doctl databases get $PG_CLUSTER_ID --format URI --no-header | grep -oP '(?<=@)[^:]+')
REDIS_HOST=$(doctl databases get $REDIS_CLUSTER_ID --format URI --no-header | grep -oP '(?<=@)[^:]+')
SPACES_BUCKET="yescare-app-preprod-v2"

# Get passwords via doctl
YESCARE_APP_PW=$(doctl databases user get $PG_CLUSTER_ID yescare_app --no-header --format Password)
HOSPITAL_PW=$(doctl databases user get $PG_CLUSTER_ID hospital_user --no-header --format Password)
PAYMENT_PW=$(doctl databases user get $PG_CLUSTER_ID payment_user --no-header --format Password)
NOTIFICATION_PW=$(doctl databases user get $PG_CLUSTER_ID notification_user --no-header --format Password)
REDIS_PW=$(doctl databases get $REDIS_CLUSTER_ID --format URI --no-header | grep -oP '(?<=:)[^@]+(?=@)')

REPO="YesCare-Tech/yescare-backend"

gh secret set PROD_DB_HOST --body "$PG_HOST" --repo $REPO
gh secret set PROD_DB_PASSWORD --body "$YESCARE_APP_PW" --repo $REPO
gh secret set PROD_AUTH_DB_PASSWORD --body "$YESCARE_APP_PW" --repo $REPO
gh secret set PROD_HOSPITAL_DB_PASSWORD --body "$HOSPITAL_PW" --repo $REPO
gh secret set PROD_PAYMENT_DB_PASSWORD --body "$PAYMENT_PW" --repo $REPO
gh secret set PROD_NOTIFICATION_DB_PASSWORD --body "$NOTIFICATION_PW" --repo $REPO
gh secret set PROD_REDIS_HOST --body "$REDIS_HOST" --repo $REPO
gh secret set PROD_REDIS_PASSWORD --body "$REDIS_PW" --repo $REPO
gh secret set PROD_S3_BUCKET --body "$SPACES_BUCKET" --repo $REPO
gh secret set PROD_NOTIFICATION_DB_HOST --body "$PG_HOST" --repo $REPO
gh secret set PROD_NOTIFICATION_DB_PORT --body "25060" --repo $REPO
gh secret set DOKS_PROD_CLUSTER_NAME --body "yescare-preprod-scale-k8s" --repo $REPO

KUBECONFIG_B64=$(doctl kubernetes cluster kubeconfig show yescare-preprod-scale-k8s | base64 -w 0)
gh secret set KUBE_CONFIG_PROD --body "$KUBECONFIG_B64" --repo $REPO
echo "=== All GitHub secrets updated successfully ==="
