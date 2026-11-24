#!/bin/bash
set -e

echo "=== Destroying YesCare Preprod ==="

# Destroy everything except VPC first
terraform destroy \
  -target=null_resource.verify \
  -target=null_resource.update_github_secrets \
  -target=null_resource.deploy_kafka \
  -target=helm_release.ingress_nginx \
  -target=helm_release.cert_manager \
  -target=module.postgres \
  -target=module.redis \
  -target=module.spaces \
  -target=module.firewall \
  -target=module.kubernetes \
  -target=digitalocean_project_resources.prod_scale \
  -auto-approve

echo ""
echo "Waiting for DO to fully terminate nodes..."

# Retry VPC deletion until it succeeds
MAX_ATTEMPTS=10
ATTEMPT=1
while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
  echo "Attempt $ATTEMPT/$MAX_ATTEMPTS - waiting 30s then trying VPC deletion..."
  sleep 30
  if terraform destroy -target=module.vpc -auto-approve 2>/dev/null; then
    echo "VPC deleted successfully!"
    break
  fi
  ATTEMPT=$((ATTEMPT + 1))
done

echo "=== Destroy complete! Ready to rebuild ==="
