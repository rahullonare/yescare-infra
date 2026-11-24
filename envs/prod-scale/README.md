# YesCare Prod-Scale (DigitalOcean)

Production-ready DigitalOcean stack designed to scale from **~10K concurrent users (Phase 1) → ~10M users (Phase 4)** with budget-centric defaults. Mirrors the `digitalocean/envs/dev` topology but uses managed Postgres, managed Redis, multi-broker **Kafka** (no RabbitMQ), DOKS autoscale, cert-manager, and DO DNS.

> Side-by-side with the legacy `digitalocean/envs/prod` env. Pick this one if you want Kafka and a documented scale path. Keep the other if you want RabbitMQ.

---

## 1. Architecture

```
                Internet
                    │
                    ▼
          ┌─────────────────────┐
          │  DO Load Balancer   │  (created by ingress-nginx, ~$12/mo)
          │     (Cloudflare      │
          │      in front from   │
          │      Phase 2)        │
          └─────────┬───────────┘
                    │ 443
                    ▼
        ┌───────────────────────┐
        │   DOKS (autoscale)    │  Phase 1: 3-8 × s-2vcpu-4gb
        │  ┌─────────────────┐  │
        │  │  ingress-nginx  │  │  2 replicas, anti-affinity
        │  │   cert-manager  │  │
        │  │  app + workers  │  │
        │  │  Kafka × 3      │  │  KRaft combined, anti-affinity, 20Gi PVC each
        │  └─────────────────┘  │
        └─────────┬─────────────┘
                  │ VPC-private
   ┌──────────────┼──────────────┐
   ▼              ▼              ▼
Managed       Managed         Spaces
Postgres      Redis           (S3 API)
(VPC)         (VPC)           app + logs
```

**Stack**

| Layer | Component | Phase 1 default |
|-------|-----------|------------------|
| Network | VPC `10.30.0.0/16` | Separate from dev/legacy-prod |
| Compute | DOKS autoscale 3-8 nodes | `s-2vcpu-4gb` |
| Database | Managed Postgres 16 | `db-s-2vcpu-4gb`, single node (flip to 2 for HA before go-live) |
| Cache | Managed Redis 7 | `db-s-1vcpu-1gb`, `allkeys-lru` |
| Streaming | Kafka (Bitnami Helm, KRaft) | 3 nodes combined, 20Gi PVC, PLAINTEXT in-cluster |
| Object storage | Spaces | App + logs buckets, 90d log retention |
| Registry | DOCR | Shared `yescare` registry (or `basic` tier per env) |
| Ingress | ingress-nginx | 2 replicas, anti-affinity |
| TLS | cert-manager + Let's Encrypt | ClusterIssuer `letsencrypt-prod` |
| DNS | DO Domain + records | apex + www + api |
| Firewall | DO Cloud Firewall | 80/443 inbound on workers |

---

## 2. Phased capacity model (10K → 10M users)

| Phase | Users | Peak concurrent | API RPS (order) | DOKS | Postgres | Redis | Kafka | LB |
|-------|-------|------------------|------------------|------|----------|-------|-------|----|
| **1** | 10K | 50–200 | 20–100 | 3× `s-2vcpu-4gb` | `db-s-2vcpu-4gb` (single) | `db-s-1vcpu-1gb` | 3× combined, 20Gi | 1× |
| **2** | 100K | 500–2K | 200–1K | 4-6× `s-4vcpu-8gb` | `db-s-4vcpu-8gb` HA | `db-s-2vcpu-4gb` | 5× combined, 50Gi, SASL | 1× sized up |
| **3** | 1M | 5K–20K | 2K–10K | 8-15× `s-8vcpu-16gb`, dedicated kafka pool | largest single + **read replica** | HA cluster | 3 ctrl + 5 brk, TLS | 2× + CDN |
| **4** | 10M | 50K+ | 20K–100K+ | Multi-pool, multi-cluster | Migrate to dedicated / Citus / RDS | Managed HA + sharding | **Confluent Cloud / Aiven** | Multi-LB + CDN/WAF |

**Tweaks live in `terraform.tfvars`.** Scaling from Phase 1 → 2 is a `terraform apply` (resize), not a rebuild.

---

## 3. Monthly budget plan (USD, `blr1` estimates)

| Line item | Phase 1 | Phase 2 | Phase 3 | Phase 4 |
|-----------|--------:|--------:|--------:|--------:|
| DOKS workers | 72 (3× $24) | 192–288 | 800–1,500 | 3,000–8,000+ |
| HA control plane (DOKS) | 0 (optional +$40) | 40 | 40 | 40+ |
| Managed Postgres | 50 (single) / 100 (HA) | 200–280 | 400–800 | 2,000–10,000+ |
| Managed Redis | 15 | 60–90 | 100–200 | 200–400+ |
| Kafka (in-cluster, PVC cost only) | ~6 (3×20Gi) | ~15 (5×50Gi) | ~60+ dedicated pool | $$$ managed |
| Load Balancer(s) | 12 | 12–24 | 24–48 | 48+ |
| Spaces + egress | 10–25 | 40–100 | 200–800 | 1,000–15,000+ |
| Container Registry | 5 (basic) | 20 (pro) | 20 | 20+ |
| CDN (Cloudflare, non-DO) | 0 | 20–200 | 200–500 | 500–3,000 |
| **Subtotal** | **~170–235** | **~600–1,050** | **~1,800–4,000** | **~7,000–35,000+** |
| 15% buffer | ~30 | ~100 | ~400 | ~1,500+ |
| **Total / month** | **~200–270** | **~700–1,150** | **~2,200–4,400** | **~8,500–37,000+** |

Set **DO billing alerts** at 50% / 80% / 100% of the Phase 1 budget before first apply: <https://docs.digitalocean.com/products/billing/how-to/set-billing-alerts/>.

---

## 4. Deploy order

### 4.1 Prereqs

1. **DO project** — create `YesCare Production` in the DO console, copy the UUID into `terraform.tfvars` (`project_id`).
2. **State bucket** — create `yescare-tfstate-prod` Space in `sgp1` (versioning on, private ACL). One-time. (`blr1` does not host Spaces; `sgp1` is the closest Spaces region to Bangalore.)
3. **API tokens** — create a prod-only DO API token; create Spaces access/secret keys for prod.
4. **Secrets in env** — never commit:
   ```bash
   export TF_VAR_do_token="dop_v1_..."
   export TF_VAR_spaces_access_id="DO..."
   export TF_VAR_spaces_secret_key="..."
   ```
5. **`terraform.tfvars`** — copy from `terraform.tfvars.example`, fill `spaces_bucket_suffix`, `k8s_version` (`doctl kubernetes options versions --region blr1`), and (later) `domain_name` + `letsencrypt_email`.

### 4.2 Phase-1 apply (two passes)

```bash
cd digitalocean/envs/prod-scale

# Pass 1 — provision cluster + managed services (Helm releases will be planned but the kubeconfig isn't wired yet)
terraform init \
  -backend-config="access_key=$TF_VAR_spaces_access_id" \
  -backend-config="secret_key=$TF_VAR_spaces_secret_key"

terraform apply \
  -target=module.vpc \
  -target=module.kubernetes \
  -target=module.postgres \
  -target=module.redis \
  -target=module.spaces \
  -target=module.firewall

# Export kubeconfig
terraform output -raw kubeconfig > kubeconfig-prod-scale.yaml
export KUBECONFIG="$PWD/kubeconfig-prod-scale.yaml"

# Pass 2 — Helm releases (ingress-nginx, cert-manager, Kafka) + remaining
terraform apply -var="kubeconfig_path=kubeconfig-prod-scale.yaml"

# Grab the LB IP
kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Update terraform.tfvars: load_balancer_ip = "<that IP>", domain_name = "yescare.in"
terraform apply -var="kubeconfig_path=kubeconfig-prod-scale.yaml"
```

### 4.3 Verify Kafka

```bash
kubectl get pods -n messaging
# Expected: kafka-controller-0/1/2 (Ready), kafka-provisioning-* (Completed)

kubectl exec -it kafka-controller-0 -n messaging -- \
  kafka-topics.sh --bootstrap-server localhost:9092 --list
# Expected: prod-events, prod-notifications, prod-jobs, prod-audit
```

Connection string for the app:

```
spring.kafka.bootstrap-servers=kafka.messaging.svc.cluster.local:9092
```

---

## 5. Scaling knobs (`terraform.tfvars` diffs)

### Phase 1 → 2 (100K users)

```hcl
k8s_ha_control_plane           = true
k8s_node_size                  = "s-4vcpu-8gb"
k8s_min_nodes                  = 3
k8s_max_nodes                  = 10
db_size                        = "db-s-4vcpu-8gb"
db_node_count                  = 2          # HA primary+standby
redis_size                     = "db-s-2vcpu-4gb"
kafka_replica_count            = 5
kafka_storage_size             = "50Gi"
kafka_resources_request_memory = "2Gi"
kafka_resources_limit_memory   = "4Gi"
kafka_topic_partitions         = 12
ingress_replica_count          = 3
registry_tier                  = "professional"
```

Then `terraform apply` — DOKS resizes are online (rolling), Postgres adds a standby (~5min), Redis resize is online, Kafka StatefulSet rolls one pod at a time.

### Phase 2 → 3 (1M users)

```hcl
k8s_node_size       = "s-8vcpu-16gb"
k8s_min_nodes       = 5
k8s_max_nodes       = 15
db_size             = "db-s-8vcpu-32gb"   # confirm latest size slug
redis_size          = "db-s-4vcpu-16gb"
kafka_replica_count = 8     # consider split mode — edit kafka-values.yaml.tpl
kafka_storage_size  = "200Gi"
```

Additionally (not in tfvars, manual changes):

- Add a **read replica** for Postgres via the DO console or extend `modules/postgres` with `digitalocean_database_replica`.
- Add a **dedicated Kafka node pool** to DOKS (extend `modules/kubernetes` to accept multiple `node_pool` blocks; taint+tolerations on Kafka pods).
- Switch `kafka-values.yaml.tpl` listeners to `SASL_SSL`; generate cluster cert via cert-manager `Certificate` resource.
- Front everything with **Cloudflare** (proxy on apex + api subdomains).
- Add **kube-prometheus-stack** + Grafana for observability (the JMX exporters in `kafka-values.yaml.tpl` and `serviceMonitor.enabled: true` toggle wire it up).

### Phase 3 → 4 (10M users)

Architecture-review gate, not a tfvars tweak:

- Split into multiple DOKS clusters (e.g. `api`, `workers`, `kafka`).
- Migrate Kafka to **Confluent Cloud** or **Aiven Kafka** (DO doesn't offer managed Kafka).
- Migrate Postgres to dedicated host / Citus / AWS RDS, depending on workload.
- Multi-region (DO `blr1` + `sgp1`) or DR to AWS Mumbai.
- Egress regularly exceeds compute spend — **CDN + WAF mandatory**.
- Request **quota increases** from DO support (LB count, droplet count, API rate).

---

## 6. Files

```
digitalocean/envs/prod-scale/
├── README.md                    (this file)
├── versions.tf                  (TF version, providers, S3 backend on Spaces)
├── provider.tf                  (DO, Helm, Kubernetes providers)
├── variables.tf                 (all scaling knobs)
├── main.tf                      (VPC, DOKS, Postgres, Redis, Spaces, Registry,
│                                 Firewall, ingress-nginx, cert-manager, Kafka, Domain)
├── outputs.tf                   (kubeconfig, DB host/pw, Kafka bootstrap, LB IP cmd)
└── terraform.tfvars.example     (Phase-1 defaults — copy to terraform.tfvars)

digitalocean/helm-values/prod/
├── kafka-values.yaml.tpl        (KRaft combined, anti-affinity, topic provisioning)
├── ingress-nginx-values.yaml.tpl (DO LB annotations, anti-affinity, autoscaling stub)
└── cert-manager-values.yaml     (lean resources, CRDs on)
```

---

## 7. Security checklist before go-live

- [ ] `db_node_count = 2` (HA Postgres standby)
- [ ] `k8s_ha_control_plane = true`
- [ ] Rotate Postgres + Redis passwords (rotate via DO console; outputs re-render on next apply)
- [ ] `letsencrypt_email` set so `ClusterIssuer` is created
- [ ] `domain_name` + `load_balancer_ip` set; cert resolves via Let's Encrypt
- [ ] DO Cloud Firewall reviewed (currently 0.0.0.0/0 on 80/443 — restrict if behind Cloudflare)
- [ ] DO billing alerts configured
- [ ] Spaces buckets `private` ACL confirmed
- [ ] App-level secrets (DB creds, Kafka SASL once enabled) stored in `kubernetes_secret` (not in tfvars)
- [ ] `kubectl get networkpolicies -A` — add default-deny once app pods are stable
- [ ] Kafka SASL/TLS enabled at Phase 2 (edit `kafka-values.yaml.tpl`, regenerate users)
