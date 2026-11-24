# Production Roadmap: 10 users today → 1K baseline → scalable to 10M

> Plan only — nothing executed. Region `sgp1`. Written 2026-07-21.
> Companion to `PREPROD_DOWNSCALE_AND_PROD_10K_PLAN.md`.

## The core idea: ONE architecture, many sizes

You have **10 real users today** but want a prod that (a) is right-sized/cheap now, (b) comfortably handles ~1K concurrent, and (c) can scale to 10M **without re-architecting**. The way to get all three is:

1. **Build the scalable design from day 1** (stateless services, autoscaling, pooled DB, event-driven, CDN-offloaded static, IaC).
2. **Deploy it at the SMALLEST tier now** (Tier 0). You are NOT paying for 1K or 10M capacity today.
3. **Scale by turning knobs** (Terraform variables + HPA + autoscaler + DB resize/replicas), not by rebuilding.

Autoscaling is the budget mechanism: you pay for *current load*, and capacity grows only when real traffic arrives.

---

## Non-negotiable design decisions (do these at Tier 0 so you never re-architect)

| # | Decision | Why it enables 10M later |
|---|---|---|
| 1 | **Stateless services** — sessions/state in Redis, never in-pod | Lets any request hit any pod; horizontal scale is linear |
| 2 | **DB access only via a connection pool** (managed PgBouncer, transaction mode) | Thousands of app conns → tens of DB conns; scaling clients doesn't exhaust PG |
| 3 | **Read/write split in the app data layer now** (even if it points at one DB) | Read replicas slot in at 100K+ with no code change |
| 4 | **Tenant/shard key in the data model from the start** | Sharding/partitioning at 1M+ becomes feasible instead of a rewrite |
| 5 | **Everything async via Kafka** (already in place) | Decouples spikes; add partitions/brokers to scale throughput |
| 6 | **Static + media on Spaces + CDN from day 1** | Offloads the majority of bytes/requests off your cluster cheaply |
| 7 | **HPA on every service + cluster-autoscaler** | Pods and nodes track load automatically |
| 8 | **Separate node pools by role** (app / data-adjacent / kafka / ingress) via labels+taints | Add dedicated pools at scale without moving workloads |
| 9 | **12-factor config** (env/secrets, no baked config) | Multi-region / multi-cell replication is trivial |
| 10 | **Everything in Terraform** (`prod-scale` already is) | Scaling = variable bumps + `apply`, reviewable & reversible |
| 11 | **Observability on from day 1** (you already run Grafana/Prometheus/Loki/Tempo) | You can't scale what you can't measure — watch p95, DB conns, Kafka lag |

> **Honest scoping note on "10M concurrent":** 10M *simultaneous* users is genuine hyperscale (top-tier global app territory, ~1–3M RPS). Reaching it is 80% **application & data architecture** (sharding, cell-based isolation, aggressive caching, async, backpressure) and 20% infra sizing. DO managed Postgres/Redis top out before 10M — beyond ~1M concurrent you move to **multi-region clusters + sharded/self-managed or managed-partitioned data + a global edge (Cloudflare)**. The ladder below keeps that path open; it does not pretend a single DO cluster serves 10M.

---

## The scaling ladder (sizes + cost per tier, sgp1)

All tiers use the SAME Terraform (`prod-scale`); you only change variable values and DB tier/replicas.

### Tier 0 — NOW (10 users) · "prod-minimal" · **~$95–130/mo**
Right-sized for real current load; autoscales toward Tier 1 automatically.
```hcl
k8s_node_size        = "s-2vcpu-4gb"   # $24/node
k8s_min_nodes        = 2               # 2 for basic resiliency
k8s_max_nodes        = 4               # headroom to ~1K without touching TF
k8s_ha_control_plane = false           # save $40/mo now; enable at Tier 1
db_size              = "db-s-1vcpu-2gb"
db_node_count        = 1               # single node now (+ connection pool)
redis_size           = "db-s-1vcpu-1gb"
ingress_replica_count = 2
registry_tier        = "basic"
# Kafka: 3-broker HA is safest; for pure cost at 10 users you may run 1 broker (RF=1) and bump later
```
Cost: nodes 2×$24=$48 + PG ~$30 + Redis ~$15 + LB(small) ~$12 + Registry $5 + Spaces $5 ≈ **~$115/mo**.

### Tier 1 — ~1K concurrent (~100–300 RPS) · **~$180–260/mo**
Your stated baseline target. Mostly reached by **autoscaling from Tier 0** + turning on HA.
```hcl
k8s_node_size        = "s-4vcpu-8gb"   # or stay s-2vcpu-4gb with more nodes
k8s_min_nodes        = 2
k8s_max_nodes        = 4
k8s_ha_control_plane = true            # +$40/mo — turn ON for prod SLA
db_size              = "db-s-1vcpu-2gb"
db_node_count        = 2               # HA (primary+standby)
redis_size           = "db-s-1vcpu-2gb"
# LB size-unit: small is fine (10K conn limit)
```

### Tier 2 — ~10K concurrent (~1–3K RPS) · **~$370–510/mo**
Exactly the current `prod-scale` defaults. Details + the two gaps (PG pooling, LB size-unit=large) are in `PREPROD_DOWNSCALE_AND_PROD_10K_PLAN.md` §B.
```hcl
k8s_node_size = "s-4vcpu-8gb"; k8s_min_nodes = 3; k8s_max_nodes = 6
db_size = "db-s-2vcpu-4gb"; db_node_count = 2   # HA + pool
redis_size = "db-s-1vcpu-2gb"
# DO LB annotation: do-loadbalancer-size-unit = "3" (large)
```

### Tier 3 — ~100K concurrent (~10–30K RPS) · **~$1.5K–3K/mo**
- **Multi-pool DOKS**: app pool 6–12× `s-4vcpu-8gb` + dedicated **kafka pool** (3× `s-4vcpu-8gb`, tainted) so brokers don't fight app pods.
- **Postgres** `db-s-4vcpu-8gb` HA + **1–2 read replicas**; route reads to replicas via the read/write split you built at Tier 0.
- **Redis** `db-s-2vcpu-4gb`.
- **Kafka** 5 brokers, partitions 12–24.
- **CDN mandatory** (Spaces CDN or Cloudflare in front) — cache static + cacheable API responses.

### Tier 4 — ~1M concurrent (~100–300K RPS) · **~$15K–40K/mo**
- DOKS `s-8vcpu-16gb` nodes, 10–20+, fully separated pools (app / kafka / ingress / system).
- **Data layer graduates**: PG read replicas per read-heavy path + **begin sharding by tenant key**; PgBouncer as its own deployment layer. Consider managed Kafka (Aiven/Confluent) to offload broker ops.
- **Redis clustered** (multiple shards).
- Edge caching + strict rate limiting + circuit breakers + async everything.

### Tier 5 — ~10M concurrent (~1–3M RPS) · **$100K–500K+/mo**
- **Multi-region, cell-based**: several regional DOKS clusters behind a **global anycast edge** (Cloudflare / global LB). Each "cell" serves a slice of tenants.
- **Sharded data**: Postgres sharded (Citus/Vitess-style) or partitioned managed; write routing by tenant/geo; per-region read replicas.
- **Redis** multi-shard per region; **Kafka** large dedicated/managed clusters with cross-region mirroring.
- Static 100% on CDN; API responses cached at edge where possible.
- At this scale, evaluate whether DO alone is the right home vs a hybrid with a hyperscaler for specific data services.

| Tier | Concurrent | Nodes | Postgres | Redis | ~Cost/mo |
|---|---|---|---|---|---|
| 0 (now) | 10 | 2× s-2vcpu-4gb | 1× 2GB + pool | 1GB | **~$115** |
| 1 | 1K | 2–4× s-4vcpu-8gb | HA 2GB + pool | 2GB | ~$180–260 |
| 2 | 10K | 3–6× s-4vcpu-8gb | HA db-s-2vcpu-4gb | 2GB | ~$370–510 |
| 3 | 100K | multi-pool 6–12 | db-s-4vcpu-8gb HA + replicas | 4GB | ~$1.5–3K |
| 4 | 1M | s-8vcpu-16gb 10–20+ | sharded + replicas | clustered | ~$15–40K |
| 5 | 10M | multi-region cells | sharded, multi-region | multi-shard/region | $100K+ |

---

## Budget-reduction levers (relevant NOW at 10 users)

1. **Deploy Tier 0, not Tier 2.** Biggest lever — don't pay for 10K capacity to serve 10 users. Autoscaling covers growth. (Saves ~$250/mo vs the 10K defaults.)
2. **Skip HA control plane at Tier 0** (−$40/mo). Add at Tier 1 when you have paying users / an SLA.
3. **Single-node Postgres now** (−~$30/mo); add the standby (HA) at Tier 1.
4. **Smaller nodes** `s-2vcpu-4gb` (−$24/node/mo vs s-4vcpu-8gb).
5. **Finish the preprod teardown** (planned 2026-07-23) so you're not paying for preprod + dev + prod simultaneously.
6. **Scale dev off-hours / to zero** when idle (dev-doks + dev-pg ≈ $57/mo). A nightly `doctl ... --count 0` or cluster stop schedule.
7. **Registry**: `basic` ($5) is fine; keep it lean with periodic GC (just reclaimed ~42GB). `starter` is free if you stay under quota.
8. **In-cluster Kafka** (already) is cheaper than managed until Tier 3–4.
9. **Serve static/media from Spaces + CDN**, not from cluster pods — cheap bytes, fewer nodes.
10. **DO annual billing / committed-use** if available on your plan — check for a discount vs hourly.
11. **Right-size with data**: watch Grafana for 2–4 weeks; if nodes sit <40% you're overprovisioned — lower `min_nodes`.

**Recommended starting point:** deploy **Tier 0 (~$115/mo)** now. It serves your 10 users with room, and autoscaling absorbs growth toward 1K before you touch anything. Move to Tier 1 (turn on HA + PG standby) the moment you have real paying traffic or an uptime commitment.

---

## Execution (reuse the prod-scale steps, at Tier 0 sizing)

The full step-by-step (bootstrap project → tfvars → init/plan/apply → PG connection pool → LB IP → DNS/TLS → load test → hardening) is in `PREPROD_DOWNSCALE_AND_PROD_10K_PLAN.md` §B.5. **Only difference for starting cheap:** paste the **Tier 0** variable block above into `terraform.tfvars` instead of the 10K block.

Then scaling up a tier = edit those variables (and add PG read replicas / extra node pools at Tier 3+), `terraform plan`, `terraform apply`. Application-layer items (sharding, read/write split, CDN, HPA custom metrics) should be implemented in the app repos in parallel — infra can't deliver the higher tiers without them.

## Decisions — LOCKED IN (2026-07-21)
1. ✅ **Start at Tier 0** (~$115/mo). Autoscaling absorbs growth toward 1K before any manual change.
2. ✅ **Kafka at Tier 0 = 1 broker** (RF=1). Cheapest. Bump to 3-broker RF=3 at Tier 1.
   → In tfvars: `kafka_replica_count = 1`, `kafka_topic_replication_factor = 1`.
   → ⚠️ RF=1 = no Kafka redundancy: a broker restart drops in-flight events. Acceptable at 10 users; **must** move to RF=3 before real traffic (a topic created at RF=1 needs partition reassignment to raise RF later — plan the cutover at Tier 1).
3. ✅ **Fresh isolated prod project** (Path 1). New `bootstrap-prod` project + state, separate from the soon-deleted preprod. Clean, no drift, can run side-by-side during cutover.
4. ✅ **Dev off-hours auto-stop** — YES. Mechanism drafted in `scripts/dev-autostop/` (see that dir). Activation pending your schedule window (hours/timezone).

### Tier 0 tfvars delta for the locked decisions
```hcl
# fresh prod project
project_id = "<from a NEW bootstrap-prod apply>"
# Tier 0 sizing (see Tier 0 block above) +:
kafka_replica_count            = 1
kafka_topic_replication_factor = 1
k8s_ha_control_plane           = false
db_node_count                  = 1
```
