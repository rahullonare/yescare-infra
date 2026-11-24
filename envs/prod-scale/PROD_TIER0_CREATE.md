# Create fresh PROD (Tier 0) + point apiprod.yescare.co.in

Config: `terraform.tfvars.prod-tier0`. Isolated from preprod via a separate
state key, new project, new VPC (10.50/16), `env=prod`.

## What gets created (~$115/mo)
`yescare-prod-scale-k8s` (2× s-2vcpu-4gb) · `yescare-prod-scale-pg` (db-s-1vcpu-2gb, 1 node)
· `yescare-prod-scale-redis` (db-s-1vcpu-2gb) · Spaces buckets · ingress-nginx LB · cert-manager
· 1-broker Kafka · services auto-deployed from the `yescare` registry.

## Prerequisite — credentials (only you have these)
```bash
export TF_VAR_do_token="dop_v1_PROD..."        # DO API token, write scope
export TF_VAR_spaces_access_id="DO..."          # Spaces key
export TF_VAR_spaces_secret_key="..."           # Spaces secret
```

## Step 1 — init with a PROD-ONLY state key (do NOT reuse preprod state)
```bash
cd digitalocean/envs/prod-scale
terraform init -reconfigure \
  -backend-config="access_key=$TF_VAR_spaces_access_id" \
  -backend-config="secret_key=$TF_VAR_spaces_secret_key" \
  -backend-config="key=envs/prod-scale/prod.tfstate"     # <-- isolates prod from preprod
```

## Step 2 — plan & apply with the Tier 0 prod vars
```bash
terraform plan  -var-file=terraform.tfvars.prod-tier0 -out=prod.plan   # REVIEW: all NEW yescare-prod-scale-* resources
terraform apply prod.plan
```
The apply auto-runs setup-kafka / setup-db / update-secrets / deploy-services / verify.

## Step 3 — get the LB IP and point apiprod
```bash
doctl kubernetes cluster kubeconfig save yescare-prod-scale-k8s
LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "prod LB = $LB_IP"

# apiprod.yescare.co.in -> new prod LB (DO DNS; does NOT touch www/api/root)
doctl compute domain records create yescare.co.in \
  --record-type A --record-name apiprod --record-data "$LB_IP" --record-ttl 300
```

## Step 4 — TLS + verify
cert-manager + ingress issue a Let's Encrypt cert for `apiprod.yescare.co.in`
once the Ingress host is set and DNS resolves. Then:
```bash
curl -I https://apiprod.yescare.co.in/actuator/health   # or your health path
```

---

## URL / endpoint map (after apply)
| Purpose | URL / endpoint |
|---|---|
| **Public API (prod)** | `https://apiprod.yescare.co.in` → ingress-nginx LB (`$LB_IP`) |
| Ingress LB IP | `kubectl get svc -n ingress-nginx ingress-nginx-controller` |
| Postgres (VPC-private) | `yescare-prod-scale-pg` — `doctl databases connection <id>` (host:25060, +pool 25061) |
| Redis/Valkey (VPC-private) | `yescare-prod-scale-redis` — `doctl databases connection <id>` |
| Container registry | `registry.digitalocean.com/yescare/<service>` (shared, existing) |
| Spaces (app/logs) | `https://yescare-app-prod-prodv1.sgp1.digitaloceanspaces.com` |
| Kubeconfig | `doctl kubernetes cluster kubeconfig save yescare-prod-scale-k8s` |
| Kafka (in-cluster) | `kafka.messaging.svc.cluster.local:9092` (1 broker, RF=1) |

## Deploy your services into it
- Images already in `registry.digitalocean.com/yescare/*`. Point your prod
  deploy (Helm/kubectl or GitHub Actions) at the new cluster's kubeconfig.
- App DB config → use the **connection pool** endpoint (port 25061), not 25060.
- `update-secrets.sh` (run during apply) pushes PG/Redis hosts to GitHub secrets.

## ⚠️ Reminders
- **Kafka RF=1** = no redundancy. Move to 3-broker RF=3 (Tier 1) before real traffic.
- Add **Postgres standby + HA control plane** at Tier 1 when Postgres CPU >70% sustained.
- Watch the Tier 0→1 signals (see `monitoring/CAPACITY_MONITORING.md`).
