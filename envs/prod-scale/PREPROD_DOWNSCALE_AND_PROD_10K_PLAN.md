# Preprod Downscale + Production 10K-User Setup — Detailed Plan

> Author aid: Claude — 2026-07-21. **This is a PLAN ONLY. Nothing here has been executed.**
> Region: `sgp1`. All `doctl`/`terraform` commands are copy-paste ready but must be run by you.

---

## Current state (verified 2026-07-21 via doctl)

| Resource | Name | Current spec | ~Cost/mo |
|---|---|---|---|
| DOKS | `yescare-preprod-scale-k8s` | `s-4vcpu-8gb` × 2 (autoscale 2–4) | ~$96 nodes |
| Postgres | `yescare-preprod-scale-pg` | `db-s-1vcpu-2gb`, **HA (2 nodes)**, 30GiB | ~$60 |
| Valkey | `yescare-preprod-scale-redis` | `db-s-1vcpu-1gb` | ~$15 |
| LB | ingress-nginx (hash-named) | 1 DO LB | ~$12 |
| **Total preprod** | | | **~$183/mo** |

Cluster IDs:
- k8s `ab26696b-1100-4312-a173-0497cc3e32a7`
- pg `8f4c1685-3b1a-49ac-9f57-71d7497be5ab`
- redis `8518a236-f7e9-499c-b6dd-27082df3f259`

---

# PART A — Downsize preprod to support 15 users (delete in ~2 days)

**Goal:** cheapest config that still serves ~15 users for the remaining ~2 days, then a clean full teardown on **2026-07-23**.

**Reality check first:** 2 days of downsizing saves only ~$6–8 in absolute dollars, and each resize causes a short disruption (node drain, DB failover). So pick ONE of these three strategies:

- **Option A1 — Do nothing, just schedule teardown (RECOMMENDED).** The savings from 2 days of downsizing are marginal and resizing risks breaking the env before its planned deletion. Skip to §A.3.
- **Option A2 — Light downsize (halve the big costs), low risk.** Drop Postgres HA→single and cluster 2→1 node. ~50% cheaper, ~2 short disruptions. §A.1.
- **Option A3 — Aggressive minimum.** Also shrink node size + Kafka replicas. More disruption, not worth it for 2 days. Documented in §A.2 for completeness only.

## A.1 — Light downsize (Option A2)

### Preferred: via Terraform (keeps state consistent)
Edit `digitalocean/envs/prod-scale/terraform.tfvars` (create from `.example` if missing) and set:
```hcl
# 15-user throwaway sizing
k8s_min_nodes = 1
k8s_max_nodes = 1        # pin to a single node
db_node_count = 1        # drop Postgres standby (removes HA)
```
Then:
```bash
cd digitalocean/envs/prod-scale
export TF_VAR_do_token="dop_v1_..."          # never commit
export TF_VAR_spaces_access_id="DO00DFK8BZWDVLZRK639"
export TF_VAR_spaces_secret_key="..."
terraform init -reconfigure -backend-config="access_key=$TF_VAR_spaces_access_id" \
  -backend-config="secret_key=$TF_VAR_spaces_secret_key"
terraform plan -out=downsize.plan      # REVIEW: must show only node_count + node pool changes
terraform apply downsize.plan
```
> ⚠️ Before scaling the cluster to 1 node, confirm all app + Kafka pods fit on one `s-4vcpu-8gb` (4 vCPU/8GB). With 3-broker Kafka this is tight — scale Kafka to 1 replica first (§A.2 step 3) or keep 2 nodes.

### Faster alternative: imperative doctl (bypasses Terraform, will cause drift)
Only if you're tearing down in 2 days and don't care about state drift:
```bash
# Postgres HA -> single node (removes standby, ~$30/mo saved)
doctl databases resize 8f4c1685-3b1a-49ac-9f57-71d7497be5ab \
  --size db-s-1vcpu-2gb --num-nodes 1

# Cluster 2 -> 1 node (pin autoscale to 1/1)
doctl kubernetes cluster node-pool update yescare-preprod-scale-k8s default \
  --auto-scale --min-nodes 1 --max-nodes 1 --count 1
```

## A.2 — Aggressive minimum (Option A3, documented only)
1. Scale app + Kafka down inside the cluster:
   ```bash
   kubectl get ns
   kubectl -n messaging scale statefulset kafka --replicas=1     # RF must drop too; risky
   kubectl -n <app-ns> scale deploy --all --replicas=1
   kubectl -n ingress-nginx scale deploy ingress-nginx-controller --replicas=1
   ```
2. Then resize node pool to a single `s-2vcpu-4gb` (needs a new pool; DO can't change size in place):
   ```bash
   doctl kubernetes cluster node-pool create yescare-preprod-scale-k8s \
     --name tiny --size s-2vcpu-4gb --count 1
   doctl kubernetes cluster node-pool delete yescare-preprod-scale-k8s default --force
   ```
3. Redis is already the smallest tier — leave as is.

> Not recommended for a 2-day window: Kafka RF=3→1 and node replacement risk data/pods breaking with little dollar upside.

## A.3 — Scheduled full teardown on 2026-07-23

**Preferred — `terraform destroy`** (removes everything cleanly, avoids orphans):
```bash
cd digitalocean/envs/prod-scale
export TF_VAR_do_token="dop_v1_..."
export TF_VAR_spaces_access_id="DO00DFK8BZWDVLZRK639"
export TF_VAR_spaces_secret_key="..."
terraform init -reconfigure -backend-config="access_key=$TF_VAR_spaces_access_id" \
  -backend-config="secret_key=$TF_VAR_spaces_secret_key"
terraform plan -destroy -out=teardown.plan   # REVIEW the destroy list carefully
terraform destroy                            # or: terraform apply teardown.plan
```

**Post-destroy orphan sweep** (DOKS LBs + PVC volumes are created by k8s, NOT tracked by Terraform — they linger after destroy):
```bash
# 1. Delete the ingress LB left behind by ingress-nginx
doctl compute load-balancer list --format Name,IP,ID
doctl compute load-balancer delete <preprod-lb-id> --force

# 2. Delete orphaned PVC block volumes (the exact problem that cost $8.39 last cycle)
doctl compute volume list --format Name,DropletIDs,ID   # any with DropletIDs [] are orphans
doctl compute volume delete <vol-id> --force

# 3. Delete leftover cluster firewalls (k8s-<clusterid>-*)
doctl compute firewall list --format Name,ID
doctl compute firewall delete <fw-id> --force

# 4. Confirm nothing remains
doctl kubernetes cluster list ; doctl databases list ; doctl compute volume list
```
> ⚠️ ORDER MATTERS: delete the ingress-nginx **Service** (or `helm uninstall ingress-nginx`) BEFORE deleting the cluster, or the LB becomes an untracked orphan. `terraform destroy` will remove the helm_release first if state is intact — but always run the sweep afterward to be sure.

> **DO NOT touch** `king-prawn-app` (production website), the `yescare` registry, or the `dev-*` resources during teardown — those are separate and must survive.

---

# PART B — Production for 10,000 concurrent users

**Good news:** `digitalocean/envs/prod-scale` is *already engineered* for 10K concurrent (~1–3K RPS). The current "preprod" is just that same stack deployed at reduced sizes. Standing up real prod = deploying this stack at its production-grade defaults. Below is the full plan with capacity rationale, the gaps to close, cost, and step-by-step execution.

## B.1 — Target architecture

```
                    Internet (yescare.co.in / api.yescare.co.in)
                                    │
                        DO Load Balancer (size: LARGE, 40K conns)
                                    │
                    ┌───────────────┴────────────────┐
                    │   DOKS cluster (sgp1)            │
                    │   HA control plane (+$40/mo)     │
                    │   3–6× s-4vcpu-8gb (autoscale)   │
                    │                                  │
                    │  ns ingress-nginx (2–3 replicas) │
                    │  ns <app>: auth, hospital,       │
                    │     notification, payment, bff   │
                    │     (HPA on CPU/mem)             │
                    │  ns messaging: Kafka 3-broker    │
                    │  ns cert-manager                 │
                    └───────┬───────────────┬──────────┘
             VPC-private    │               │  VPC-private
                    ┌───────┴──────┐  ┌─────┴──────────┐
                    │ Managed PG   │  │ Managed Valkey │
                    │ db-s-2vcpu-  │  │ db-s-1vcpu-2gb │
                    │ 4gb HA +     │  │ (allkeys-lru)  │
                    │ PgBouncer    │  └────────────────┘
                    │ pool         │
                    └──────────────┘
   Spaces (sgp1): app + logs buckets   |   Container Registry: yescare (professional tier)
```

## B.2 — Capacity sizing & rationale (10K concurrent ≈ 1–3K RPS)

| Layer | Spec | Why it holds 10K | Headroom knob |
|---|---|---|---|
| DOKS nodes | `s-4vcpu-8gb` × min 3 / max 6, autoscale | 12–24 vCPU / 24–48GB. Fits 5 services (HPA) + 3 Kafka + ingress + system with room | raise max_nodes to 8 |
| Control plane | **HA (+$40/mo)** | Survives control-plane node loss; required for prod SLA | — |
| Postgres | `db-s-2vcpu-4gb` **HA** + **connection pool** | 2 vCPU handles ~1–3K RPS *if pooled*. DO managed PgBouncer pool (transaction mode) multiplexes 10K app conns → ~80 backend conns | add read replica |
| Valkey | `db-s-1vcpu-2gb`, allkeys-lru | 2GB ≈ 2–5K active sessions w/ headroom | bump to 4gb |
| Kafka | 3-broker KRaft, RF=3, 6 partitions/topic | In-cluster HA; RF3 survives 1 broker loss | 12–24 partitions |
| Ingress | ingress-nginx 2–3 replicas | Spreads across nodes | +replicas |
| DO LB | **size-unit ≥ 3 (large)** | small=10K / medium=20K / large=40K concurrent conns. 10K users need ≥ medium; large gives spike headroom | — |

### ⚠️ Two gaps in the current defaults you MUST close for real 10K prod
1. **Postgres connection pooling** — a 2-vCPU PG maxes ~97 backend connections. 10K users without a pool WILL exhaust connections. Create a DO managed connection pool (PgBouncer, transaction mode) and point services at the pool port (25061), not the raw DB.
   ```bash
   doctl databases pool create <pg-cluster-id> yescare-pool \
     --db yescareprod --mode transaction --size 90 --user yescare_app
   ```
   Then set the app `DB_HOST/DB_PORT` (in GitHub secrets / update-secrets.sh) to the **pool** host/port.
2. **Load Balancer sizing** — ingress-nginx provisions a *small* DO LB by default. Force a larger one via Service annotations in `helm-values/prod/ingress-nginx-values.yaml.tpl`:
   ```yaml
   controller:
     service:
       annotations:
         service.beta.kubernetes.io/do-loadbalancer-size-unit: "3"          # large
         service.beta.kubernetes.io/do-loadbalancer-enable-proxy-protocol: "true"
   ```
   And enable HPA for the app services (add HorizontalPodAutoscaler manifests keyed on CPU 70%).

## B.3 — Estimated cost (production 10K)

| Item | Monthly |
|---|---|
| DOKS nodes 3× s-4vcpu-8gb (baseline) | $144 |
| HA control plane | $40 |
| Postgres db-s-2vcpu-4gb HA | ~$100 |
| Valkey db-s-1vcpu-2gb | ~$30 |
| DO LB (large) | ~$24 |
| Kafka block storage 3×20Gi | ~$6 |
| Registry (professional) | $20 |
| Spaces | $5 |
| **Baseline total** | **~$369/mo** |
| Peak (autoscale to 6 nodes) | ~$513/mo |

## B.4 — Prerequisites checklist
- [ ] Separate **prod DO API token** (do NOT reuse dev/preprod token) → `TF_VAR_do_token`
- [ ] Spaces key for TF backend + app (`TF_VAR_spaces_access_id` / `_secret_key`) — reuse `YesCare-Preprod-Terraform` or mint a prod-scoped one
- [ ] Decide domain: reuse `yescare.co.in` (means DNS cutover from current App Platform site) or a new prod host like `api.yescare.co.in` only
- [ ] `letsencrypt_email` for TLS
- [ ] Globally-unique `spaces_bucket_suffix`
- [ ] Confirm `doctl kubernetes options versions --region sgp1` for a current `k8s_version`

## B.5 — Step-by-step execution

### Step 0 — Decide: reuse preprod stack as prod, or stand up a NEW isolated prod?
- **Path 1 (RECOMMENDED): promote a fresh env.** Keep the `prod-scale` code but deploy a *new* project/state so prod is isolated from the dying preprod. Cleanest, no drift.
- **Path 2: reuse the existing preprod stack**, just scale it up to prod sizes and stop calling it preprod. Cheaper/faster but you inherit any drift and can't run preprod + prod side by side.

The steps below assume **Path 1**.

### Step 1 — Bootstrap prod project + state bucket
```bash
cd digitalocean/envs/bootstrap-prod
export TF_VAR_do_token="dop_v1_PROD..."
terraform init
terraform apply
terraform output project_id        # copy this
```

### Step 2 — Configure prod tfvars
```bash
cd ../prod-scale
cp terraform.tfvars.example terraform.tfvars   # if not present
```
Set in `terraform.tfvars` (production-grade — these ARE the 10K defaults):
```hcl
env           = "prod"
region        = "sgp1"
project_id    = "<from step 1>"
k8s_version   = "<from doctl options versions>"
k8s_ha_control_plane = true
k8s_node_size = "s-4vcpu-8gb"
k8s_min_nodes = 3
k8s_max_nodes = 6
db_size       = "db-s-2vcpu-4gb"
db_node_count = 2                 # HA
redis_size    = "db-s-1vcpu-2gb"
enable_spaces = true
spaces_bucket_suffix = "<unique>"
create_registry = false          # registry already exists (account-global)
registry_tier   = "professional" # upgrade for prod image volume
ingress_replica_count = 3
letsencrypt_email = "ops@yescare.co.in"
domain_name       = ""           # fill AFTER first apply (see step 5)
load_balancer_ip  = ""
```

### Step 3 — Init backend + plan
```bash
export TF_VAR_do_token="dop_v1_PROD..."
export TF_VAR_spaces_access_id="DO..."
export TF_VAR_spaces_secret_key="..."
terraform init -reconfigure \
  -backend-config="access_key=$TF_VAR_spaces_access_id" \
  -backend-config="secret_key=$TF_VAR_spaces_secret_key"
terraform plan -out=prod.plan     # REVIEW node/db/redis sizes match the table above
```

### Step 4 — Apply (provisions cluster, DB, redis, ingress, cert-manager, Kafka, services)
```bash
terraform apply prod.plan
```
> The stack auto-runs `setup-kafka.sh`, `setup-db.sh`, `update-secrets.sh`, `deploy-services.sh`, `verify.sh` via null_resources. Watch their output — deploy-services pulls images from the `yescare` registry.

### Step 5 — Close the two prod gaps (§B.2)
1. Create the Postgres connection pool (command in §B.2 gap 1); update GitHub secrets / `update-secrets.sh` so services use the **pool** endpoint.
2. Confirm the LB came up as large and grab its IP:
   ```bash
   export KUBECONFIG=$(pwd)/kubeconfig    # or: doctl k8s cluster kubeconfig save yescare-prod-scale-k8s
   kubectl get svc ingress-nginx-controller -n ingress-nginx \
     -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
   doctl compute load-balancer list --format Name,IP,SizeUnit   # verify size-unit=3
   ```

### Step 6 — DNS + TLS cutover
Put the LB IP into `terraform.tfvars` and re-apply to create DO DNS records + LB cert:
```hcl
domain_name      = "yescare.co.in"
load_balancer_ip = "<LB IP from step 5>"
```
```bash
terraform apply
```
> If `yescare.co.in` currently points to the App Platform `king-prawn-app` static site, decide the split: e.g. keep `www` on App Platform (frontend) and point only `api.yescare.co.in` at the new cluster. Adjust `modules/domain` inputs accordingly. **Verify TLS issues (cert-manager) before flipping production DNS.**

### Step 7 — Load test & validate BEFORE announcing prod
```bash
# smoke
kubectl get pods -A
kubectl get hpa -A
# load test to 10K concurrent (from a separate box)
k6 run --vus 10000 --duration 5m loadtest.js     # or vegeta/locust
# watch autoscaling + DB connections + Kafka lag during the run
kubectl top nodes ; kubectl top pods -A
doctl databases pool list <pg-cluster-id>
```
Success criteria: p95 latency acceptable, no 5xx spikes, nodes autoscale and settle, PG backend connections stay under the pool ceiling, Kafka consumer lag drains.

### Step 8 — Production hardening (post-launch)
- [ ] Enable DO **daily DB backups** + test a restore (`doctl databases backups list`)
- [ ] Restrict k8s API access (`doctl kubernetes cluster update --... ` trusted CIDRs) instead of 0.0.0.0/0
- [ ] Set resource `requests`/`limits` + `PodDisruptionBudget` on every service
- [ ] Deploy monitoring — the repo has `digitalocean/envs/prod-scale/monitoring/` (Grafana ingress w/ TLS per recent commits). Wire alerts (CPU, DB conns, Kafka lag, cert expiry)
- [ ] Firewall: keep only 80/443 inbound on workers (already in `module.firewall`)
- [ ] Rotate/secure the remaining 2 Spaces keys; store all secrets in GitHub Actions secrets, never in tfvars

---

## Decision summary needed from you
1. **Preprod:** Option A1 (just schedule teardown — recommended) vs A2 (light downsize)?
2. **Prod:** Path 1 (fresh isolated prod — recommended) vs Path 2 (reuse/rename preprod)?
3. **Domain:** dedicate `api.yescare.co.in` to the cluster and keep `www` on App Platform, or full cutover?
