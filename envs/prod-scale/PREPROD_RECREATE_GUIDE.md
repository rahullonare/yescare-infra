# YesCare "Preprod" — How It Was Built & How to Delete / Recreate It

> This document explains, end-to-end, how the **preprod** environment was created
> from the code in this repo, and gives you a repeatable procedure to **tear it
> down and rebuild an identical copy**.

---

## 1. What "preprod" actually is

There is **no folder called `preprod`**. "Preprod" is the **`env` value** used when
applying the `prod-scale` Terraform stack. The environment lives entirely under:

```
digitalocean/
├── envs/
│   ├── bootstrap-prod/     ← Step 1: DO Project + Terraform state bucket (LOCAL state, run ONCE)
│   └── prod-scale/         ← Step 2: ALL preprod infra + app deploy (REMOTE state)
├── modules/                ← reusable building blocks (vpc, kubernetes, postgres, redis, …)
└── helm-values/prod/       ← ingress-nginx / cert-manager / kafka value templates
```

Everything is deployed on **DigitalOcean** (not AWS), in region **`sgp1` (Singapore)**.

### Why "prod-scale" folder but "preprod" names?

The folder is generically named `prod-scale` and driven by `var.env`. When this
environment was built, it was applied with **`env = "preprod"`**, so every resource
was named `yescare-preprod-scale-*`. You can confirm this: the deploy/setup scripts
(`setup-db.sh`, `manual-deploy.sh`, `update-secrets.sh`, `verify.sh`, `build-all.sh`,
`setup-kafka.sh`) all reference hardcoded names like:

- Cluster: `yescare-preprod-scale-k8s` (kube context `do-sgp1-yescare-preprod-scale-k8s`)
- Postgres: `yescare-preprod-scale-pg`
- Redis: `yescare-preprod-scale-redis`
- Spaces app bucket: `yescare-app-preprod-v2`
- Terraform state bucket: `yescare-tf-state-preprod` (see `versions.tf`)

> ⚠️ **Naming discrepancy to be aware of:** `terraform.tfvars.example` ships with
> `env = "prod"` and the bootstrap default state bucket is `yescare-tfstate-prod`,
> but the **live preprod** deployment used `env = "preprod"` and state bucket
> `yescare-tf-state-preprod`. To recreate an *identical* copy you must override
> both to `preprod` (details in §5). Otherwise you'll get `yescare-prod-scale-*`
> names and the hardcoded scripts will not find your resources.

---

## 2. Full inventory of what gets created

### Layer 1 — `bootstrap-prod` (run once, LOCAL state)
`envs/bootstrap-prod/main.tf` creates:

| Resource | Purpose |
|---|---|
| `digitalocean_project` "YesCare Production" | Billing / access isolation boundary |
| `digitalocean_spaces_bucket` (state) | Holds `prod-scale` remote Terraform state, versioned, 90-day noncurrent expiry |
| `digitalocean_project_resources` | Attaches the state bucket to the project |

Outputs: `project_id`, `state_bucket_name` → fed into `prod-scale`.

### Layer 2 — `prod-scale` (REMOTE state in the bucket above)
`envs/prod-scale/main.tf` wires these modules and resources:

| # | Resource (module) | Name pattern | Notes |
|---|---|---|---|
| 1 | **VPC** (`modules/vpc`) | `yescare-preprod-scale` | `10.30.0.0/16`, distinct from dev/legacy-prod |
| 2 | **DOKS cluster** (`modules/kubernetes`) | `yescare-preprod-scale-k8s` | Autoscaling `s-4vcpu-8gb`, min 3 / max 6, auto-upgrade |
| 3 | **Managed Postgres** (`modules/postgres`) | `yescare-preprod-scale-pg` | `db-s-2vcpu-4gb`, PG 16, HA (2 nodes). Creates DBs + users (see below) |
| 4 | **Managed Redis/Valkey** (`modules/redis`) | `yescare-preprod-scale-redis` | `db-s-1vcpu-2gb`, `allkeys-lru`, k8s firewall rule |
| 5 | **Spaces** (`modules/spaces`) | `yescare-app-preprod-*`, `yescare-logs-preprod-*` | S3-compatible, versioning + CORS + log expiry |
| 6 | **Container Registry** (`modules/registry`) | `yescare` | Only if `create_registry=true` (account-global; usually shared with dev → false) |
| 7 | **Cloud Firewall** (`modules/firewall`) | `yescare-preprod-scale-fw` | Opens 80/443 to worker nodes |
| 8 | **Project attach** | — | Attaches DOKS/PG/Redis/Spaces to the DO Project |
| 9 | **ingress-nginx** (Helm) | — | Provisions the DO Load Balancer (public IP) |
| 10 | **cert-manager** (Helm) | — | Let's Encrypt TLS |
| 11 | **Domain/DNS** (`modules/domain`) | — | Only if `domain_name` + `load_balancer_ip` set |

Then a chain of `null_resource` **local-exec provisioners** runs automatically on
every apply, in this dependency order:

```
deploy_kafka ──► setup_db ──┐
     │                      ├──► deploy_services
     └──► update_github_secrets ──► verify
```

- **`setup-kafka.sh`** → deploys a single-node Kafka (`kafka.yaml`, KRaft combined,
  Apache Kafka 3.7.0) into the `messaging` namespace and creates ~24 app topics
  (`appointment.created`, `consultation.*`, `payment.processed`, `gateway.*`, …).
  (Note: the Helm-based 3-broker Kafka in `main.tf` is **commented out**; the live
  env runs the simpler single-pod `kafka.yaml`.)
- **`setup-db.sh`** → creates the `prod` namespace, grants schema ownership to each
  service user (`payment_user`→`payment_db`, `hospital_user`→`hospital_db`,
  `yescare_app`→`yescareprod`/`auth_db`, `notification_user`→`notification_service_db`).
- **`update-secrets.sh`** → pushes DB/Redis/Spaces/kubeconfig values as GitHub
  secrets to `YesCare-Tech/yescare-backend` (PROD_DB_HOST, PROD_REDIS_*, etc.).
- **`deploy-services.sh`** → tries GitHub Actions `deploy.yml` for the 6 services;
  if that fails (billing/unhealthy pods), falls back to **`manual-deploy.sh`**.
- **`verify.sh`** → prints cluster/DB/Kafka status **and updates the `yescare.co.in`
  DNS A-records to the new LB IP** (record IDs `1821333975`, `1822440970`).

### Postgres databases & users created (by `modules/postgres` + `setup-db.sh`)

| Database | Owner/User |
|---|---|
| `yescareprod` (default) | `yescare_app` |
| `auth_db` | `yescare_app` |
| `hospital_db` | `hospital_user` |
| `payment_db` | `payment_user` |
| `notification_service_db` | `notification_user` |

### Application services deployed (namespace `prod`)
`auth-service`, `hospital-service`, `payment-service`, `notification-service`,
`user-bff`, `websocket-gateway` — images from `ghcr.io/yescare-tech/<svc>:latest`.
`manual-deploy.sh` also: creates the GHCR pull secret + app secrets (copied/patched
from the **dev** cluster `do-sgp1-dev-doks`), ClusterIP services, the ingress for
`api.yescare.co.in`, the full **monitoring stack** (Prometheus, Grafana, Loki,
Tempo, promtail, otel-collector), the `letsencrypt-prod` ClusterIssuer, a
SUPER_ADMIN user in `auth_db`, and the Grafana ingress at `grafana.yescare.co.in`.

---

## 3. Prerequisites (tools + credentials)

Install / have ready:
- `terraform` >= 1.5, `doctl` (authenticated), `kubectl`, `helm`, `gh` (GitHub CLI, authed), `docker`, `psql`, `base64`, `envsubst`
- A **DigitalOcean API token** and a **Spaces access key/secret** pair
- Access to the `YesCare-Tech/yescare-backend` and `yescare-infra` repos
- The **dev DOKS cluster** must exist and be reachable (`do-sgp1-dev-doks`) — the
  manual deploy copies GHCR + app secrets and deployment manifests **from dev**.

Export sensitive vars (never commit these):
```bash
export TF_VAR_do_token="dop_v1_..."
export TF_VAR_spaces_access_id="DO..."
export TF_VAR_spaces_secret_key="..."
```

---

## 4. First-time build order (how it was originally created)

```bash
# ── Layer 1: bootstrap (LOCAL state, once) ────────────────────────────
cd digitalocean/envs/bootstrap-prod
cp terraform.tfvars.example terraform.tfvars
#   set: state_bucket_name = "yescare-tf-state-preprod"   (to match the live env)
terraform init
terraform apply            # note the project_id output
#   ⚠️ back up bootstrap-prod/terraform.tfstate somewhere private (1Password)

# ── Layer 2: prod-scale (REMOTE state) ────────────────────────────────
cd ../prod-scale
cp terraform.tfvars.example terraform.tfvars
#   EDIT terraform.tfvars — critical values for an identical rebuild:
#     env                  = "preprod"          # <-- MUST override the "prod" default
#     project_id           = "<from bootstrap output>"
#     spaces_bucket_suffix = "v2"               # gives bucket yescare-app-preprod-v2
#     k8s_version          = "$(doctl kubernetes options versions --region sgp1 | sed -n 2p | awk '{print $1}')"
#     domain_name / letsencrypt_email as desired

terraform init \
  -backend-config="access_key=$TF_VAR_spaces_access_id" \
  -backend-config="secret_key=$TF_VAR_spaces_secret_key"

terraform apply    # provisions infra, then auto-runs kafka/db/secrets/deploy/verify
```

After apply, grab the LB IP if you need to wire DNS manually:
```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

---

## 5. ⚠️ Critical settings for an IDENTICAL rebuild

Because the operational scripts have **hardcoded `preprod` names**, your rebuild
must produce those exact names or the scripts break. Ensure in
`prod-scale/terraform.tfvars`:

| Variable | Value | Produces |
|---|---|---|
| `env` | `preprod` | `yescare-preprod-scale-*` cluster/pg/redis |
| `spaces_bucket_suffix` | `v2` | `yescare-app-preprod-v2` (matches `update-secrets.sh`) |
| `region` | `sgp1` | matches `do-sgp1-...` kube context |
| `create_registry` | `false` | reuse the shared account-global `yescare` registry |

And in `bootstrap-prod/terraform.tfvars`: `state_bucket_name = "yescare-tf-state-preprod"`
to match `prod-scale/versions.tf` (which hardcodes that bucket name in the backend block).

> If you instead accept the defaults (`env = "prod"`), you get `yescare-prod-scale-*`
> and you'd have to sed-replace `preprod`→`prod` across all 7 shell scripts.

---

## 6. Delete / teardown procedure

### 6a. Destroy the infra (`prod-scale`)
A helper script exists: `destroy.sh`. It destroys everything except the VPC first,
then retries the VPC (which can only delete after DO fully releases the LB + DB
private-network attachments):

```bash
cd digitalocean/envs/prod-scale
bash destroy.sh
```

What it does:
```
terraform destroy -target=... (null_resources, helm releases, postgres, redis,
                               spaces, firewall, kubernetes, project attachment)
# then loops up to 10x, sleeping 30s, retrying:
terraform destroy -target=module.vpc
```

### 6b. Manual cleanup the script does NOT cover
`destroy.sh` targets Terraform-managed resources only. Also remove, if you want a
truly clean slate:
- **DO Load Balancer** created by ingress-nginx — usually auto-deleted when the
  Helm release/Service is removed, but verify in the DO console; orphaned LBs bill.
- **Block-storage PVCs** (Kafka, Loki 10Gi, Tempo 10Gi) — `kubectl delete pvc` or
  they linger as DO Volumes after the cluster is gone.
- **GitHub secrets** on `yescare-backend` (PROD_*) — stale after teardown.
- **DNS records** — `verify.sh` repointed `yescare.co.in` (IDs 1821333975 /
  1822440970) and the ingress uses `api.yescare.co.in` / `grafana.yescare.co.in`.
- **App data in Spaces** — buckets use `force_destroy = true`, so `terraform
  destroy` will wipe their contents. Back up first if needed.

### 6c. Optionally destroy the bootstrap layer
Only if you also want to remove the DO Project + state bucket. **Do this last**,
and remember it holds your remote state — export/back it up first:
```bash
cd ../bootstrap-prod
terraform destroy      # removes project + state bucket (versioned)
```

---

## 7. Recreate = §6 then §4

To "delete and create the same like that":

1. **Tear down**: `prod-scale/destroy.sh` (§6a) + manual cleanup (§6b). Keep the
   bootstrap layer so you don't lose the project/state bucket.
2. **Rebuild**: re-run `terraform apply` in `prod-scale` with the same
   `terraform.tfvars` (§4 Layer 2), ensuring the `preprod` settings from §5.
3. The `null_resource` provisioners re-run automatically, so Kafka topics, DB
   grants, GitHub secrets, service deploy, monitoring, admin user, and DNS update
   all happen without extra manual steps — **provided the dev cluster
   (`do-sgp1-dev-doks`) is up**, since secrets/manifests are sourced from it.

---

## 8. Cost & scaling reference (Phase 1 defaults)

~$210–450/mo: 3× `s-4vcpu-8gb` nodes (~$48 each) + HA Postgres `db-s-2vcpu-4gb`
(~$100) + Redis `db-s-1vcpu-2gb` (~$30) + LB + Spaces + block storage. Scaling
knobs (Phase 2/3/4) are documented in `outputs.tf` (`scale_phase_hints`) and
`README.md`.

---

## 9. File map (quick reference)

| File | Role |
|---|---|
| `envs/bootstrap-prod/main.tf` | DO Project + state bucket (run once) |
| `envs/prod-scale/main.tf` | All infra + provisioner chain |
| `envs/prod-scale/variables.tf` | All tunables + defaults |
| `envs/prod-scale/terraform.tfvars.example` | Copy → `terraform.tfvars` |
| `envs/prod-scale/versions.tf` | Providers + **remote state backend** (`yescare-tf-state-preprod`) |
| `envs/prod-scale/provider.tf` | DO + helm + kubernetes providers |
| `envs/prod-scale/kafka.yaml` | Single-node Kafka Deployment + Service |
| `envs/prod-scale/setup-kafka.sh` | Deploy Kafka + create topics |
| `envs/prod-scale/setup-db.sh` | Grant DB schema ownership per service |
| `envs/prod-scale/update-secrets.sh` | Push PROD_* GitHub secrets |
| `envs/prod-scale/deploy-services.sh` | GH Actions deploy w/ manual fallback |
| `envs/prod-scale/manual-deploy.sh` | Full manual deploy (secrets, services, ingress, monitoring, admin, TLS) |
| `envs/prod-scale/build-all.sh` | Build+push all 6 images, rollout restart |
| `envs/prod-scale/verify.sh` | Post-deploy checks + DNS repoint |
| `envs/prod-scale/destroy.sh` | Teardown (infra, then VPC retry loop) |
| `envs/prod-scale/monitoring/` | Prometheus/Grafana/Loki/Tempo/otel manifests + dashboards |
| `modules/*` | vpc, kubernetes, postgres, redis, spaces, registry, firewall, domain |
```
