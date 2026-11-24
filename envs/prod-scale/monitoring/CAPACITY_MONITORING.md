# Capacity Monitoring — Tier 0 → Tier 1 signals

How to know when to scale prod from **Tier 0 (~$115/mo, ~few-hundred concurrent)** to
**Tier 1 (HA + bigger DB, ~1K concurrent)**. See `../PROD_SCALABLE_ROADMAP_10_TO_10M.md` for the tiers.

## The split: where each signal lives

| Signal | Lives in | Asset |
|---|---|---|
| DB connection-pool saturation, RPS, p95 latency, 5xx, JVM heap | **In-cluster Prometheus/Grafana** (app Micrometer metrics) | `configmaps/prometheus-alerts.yaml` (group `yescare-capacity-alerts`) + dashboard `yescare-tier-capacity` |
| **Postgres/Redis host CPU, memory, disk; DOKS node CPU/mem** | **DO monitoring** (managed DBs + no node-exporter in Prometheus) | `do-native-capacity-alerts.tf.example` |

> ⚠️ The single most authoritative Tier-1 trigger — **Postgres CPU** — is a DO-native alert, NOT Prometheus. Don't rely on Grafana alone.

## Thresholds (fire on SUSTAINED load, days not spikes)

| Metric | Warn | Action |
|---|---|---|
| **Postgres CPU** (DO) | >70% for days | **Primary trigger** → Tier 1: `db_size = db-s-2vcpu-4gb`, `db_node_count = 2` |
| **DB pool utilization** (Grafana) | >70% / >90% crit | Enlarge PgBouncer pool, then bigger DB |
| **DB connections pending** (Grafana) | >0 for 5m | Pool too small / DB too slow |
| **p95 latency** (Grafana) | >500ms for 15m | Check DB pool + node headroom |
| **Node CPU / mem** (DO) | >70% / >80% | Raise `k8s_max_nodes` or node size |
| **Redis memory** (DO) | >80% | `redis_size = db-s-1vcpu-2gb` |
| **RPS** (Grafana) | >100 sustained | Trending to Tier 1 — review board |

## Apply the assets (nothing here auto-deploys)

**1. Prometheus capacity alerts** — already added to the existing configmap; reload:
```bash
kubectl apply -f configmaps/prometheus-alerts.yaml
# hot-reload Prometheus (or rollout restart):
kubectl -n monitoring exec deploy/prometheus -- kill -HUP 1 2>/dev/null \
  || kubectl -n monitoring rollout restart deploy/prometheus
# verify the rules loaded:
kubectl -n monitoring exec deploy/prometheus -- \
  wget -qO- localhost:9090/api/v1/rules | grep -o capacity-tier1 | head
```

**2. Capacity dashboard** — rebuild the dashboards configmap from the folder (file-provider auto-loads it):
```bash
kubectl -n monitoring create configmap grafana-dashboards \
  --from-file=dashboards/ -o yaml --dry-run=client | kubectl apply -f -
kubectl -n monitoring rollout restart deploy/grafana   # picks up new file mount
# then open Grafana → folder "Yescare" → "YesCare — Tier 0→1 Capacity Signals"
```

**3. DO-native infra alerts** — fill IDs, drop `.example`, apply in a TF root with the DO provider:
```bash
doctl databases list            # copy the pg + redis cluster UUIDs
cp do-native-capacity-alerts.tf.example ../do-native-capacity-alerts.tf   # into prod env root
# edit: capacity_alert_emails, pg_cluster_id, redis_cluster_id, doks_worker_tag
cd .. && terraform plan && terraform apply
```

## Notes / caveats
- **Alertmanager routing:** these alerts carry `signal: capacity-tier1`. If you want them in a separate (non-paging) channel, add an Alertmanager route on that label. If no Alertmanager is wired yet, they still show under Prometheus `/alerts` and can be paneled in Grafana.
- **Metric coverage:** `hikaricp_*` is exposed by the JVM services (auth, payment, …). A non-JVM or reactive/R2DBC service (e.g. hospital-service showed no HikariCP pool) won't appear in the DB-pool panels — that's expected; rely on DO Postgres CPU for those.
- **Tune `SustainedRequestRateApproachingTier1`:** the 100 RPS threshold is a placeholder — set it from your measured Tier 0 baseline after a week of real traffic.
- **Existing dashboards** (`yescare-capacity.json`) have Node CPU/mem panels that need node-exporter/kube-state-metrics — those aren't scraped today, so those panels are blank. This board deliberately avoids them and points at DO for node/DB CPU.
