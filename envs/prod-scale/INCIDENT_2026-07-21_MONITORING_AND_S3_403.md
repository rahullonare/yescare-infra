# Incident + Change Log — 2026-07-21

Two pieces of work, done in one session against the **prod** cluster
`yescare-prod-scale-k8s` (context `do-sgp1-yescare-prod-scale-k8s`, region `sgp1`):

1. **Deployed the monitoring namespace / observability stack** (app pods were logging
   `UnknownHostException` for `otel-collector`).
2. **Fixed fleet-wide S3 403 upload failures** caused by a Spaces key that was revoked
   on 2026-07-21.

Cluster/env facts referenced below:
- Clusters: prod `do-sgp1-yescare-prod-scale-k8s` (ns `prod`), preprod
  `do-sgp1-yescare-preprod-scale-k8s` (ns `prod`), dev `do-sgp1-dev-doks` (ns `dev`).
  The `arn:aws:eks:*` contexts are the legacy/unused AWS stack — ignore them.
- Ingress LB IP: **139.59.216.77**. ClusterIssuer `letsencrypt-prod` (Ready), cert-manager running.
- Backend repo (GitHub secrets / CD): `YesCare-Tech/yescare-backend`.

---

## Part 1 — Monitoring namespace / observability stack

### Symptom
App pods logged, on every OTLP export interval:
```
java.net.UnknownHostException: otel-collector.monitoring.svc.cluster.local
logger=io.opentelemetry.exporter.internal.http.HttpExporter  level=ERROR
```

### Root cause
The fresh Tier 0 prod cluster never had a `monitoring` namespace. The repo already
contained a complete stack under `digitalocean/envs/prod-scale/monitoring/`
(Prometheus, Grafana, Loki, Tempo, Promtail, otel-collector) but **no Namespace
manifest and no apply script**, so it had never been applied here.

### Capacity decision
Full stack ≈ **1.0 GiB memory requests + 20 GiB disk**. Both Tier 0 nodes
(`s-2vcpu-4gb`) were already at **86% / 96%** memory requests (~500 MiB free total),
so the stack would not schedule. **Scaled the default pool 2 → 3 nodes**
(pinned `min=3`, `s-2vcpu-4gb`, ≈ +$24/mo):

```bash
doctl kubernetes cluster node-pool update 782a3d18-8756-4a95-9322-8f67bea14d58 \
  fa7639d8-9b07-4933-aebc-df1b805116e8 --count 3 --auto-scale --min-nodes 3 --max-nodes 4
```

### Component footprint (mem requests)
| Component      | Mem req | Notes |
|----------------|---------|-------|
| otel-collector | 128Mi   | the service apps dial (`otel-collector:4318`) |
| tempo          | 256Mi   | +10Gi PVC — collector's only export target (traces) |
| prometheus     | 256Mi   | scrapes app pods directly (metrics path, not via collector) |
| grafana        | 128Mi   | UI |
| loki           | 128Mi   | +10Gi PVC (logs) |
| promtail       | 64Mi ×3 | DaemonSet |

otel-collector runs a **traces-only** pipeline → exports to
`tempo.monitoring.svc.cluster.local:4317`. Metrics come from Prometheus scraping app
pods, not through the collector.

### Two latent repo bugs found & fixed
Several manifests were raw `kubectl get -o yaml` dumps from the old cluster:

1. **`loki-pvc.yaml` / `tempo-pvc.yaml`** pinned a dead `volumeName:` (+ `bind-completed`
   annotation) → PVCs bound **Lost**. Rewrote both clean (dynamic provisioning). Fixed in repo.
2. **`deployments/services.yaml`** pinned old `clusterIP` / `clusterIPs` (10.105.x.x)
   → `failed to allocate IP … network does not match the current range`. Stripped those
   lines. Fixed in repo.
3. The `deployments/*.yaml` also carry `resourceVersion`/`uid`/`status` cruft, but
   `kubectl apply` tolerates it on create (verified with `--dry-run=server`) — left as-is.

Also added a new `monitoring/namespace.yaml` (was missing entirely).

### Apply order (what was run)
```bash
cd digitalocean/envs/prod-scale/monitoring
kubectl apply -f namespace.yaml
kubectl apply -f rbac/
kubectl apply -f configmaps/
kubectl apply -f loki-pvc.yaml -f tempo-pvc.yaml      # after rewrite → Bound
# (wait for 3rd node Ready)
kubectl apply -f deployments/services.yaml            # after clusterIP strip
for f in otel-collector tempo prometheus loki promtail-daemonset grafana; do
  kubectl apply -f deployments/$f.yaml
done
kubectl apply -f grafana-ingress.yaml
```

### Result
`otel-collector` **1/1 Running** → the app `UnknownHostException` is resolved.
Grafana / Prometheus / Loki / Tempo Running; Promtail on all 3 nodes.

### Open follow-up
- Grafana ingress host is `grafana.yescare.co.in` (issuer `letsencrypt-prod`). Create DNS
  **A `grafana.yescare.co.in → 139.59.216.77`** for the cert to issue and the UI to load.
- Consider committing a small apply script / kustomization so the namespace + stack are
  reproducible (the ordering above is manual).

---

## Part 2 — S3 403 upload failures (fleet-wide)

### Symptom
```
[500] unhandled exception uri=/api/v1/profile/save : Upload failed:
 (Service: S3, Status Code: 403, Request ID: …-sgp1b)
  at com.yescare.hospital.service.service.impl.StorageService.uploadMultipart(StorageService.java:136)
Caused by: software.amazon.awssdk.services.s3.model.S3Exception: (Status Code: 403)
```
Reported as happening "for all environments".

### Diagnosis (evidence chain)
- **Bucket exists / region correct.** Anonymous probe of the prod app bucket:
  ```bash
  curl -s https://yescare-app-prod-prodv1.sgp1.digitaloceanspaces.com/
  # → 403 AccessDenied  <BucketName>yescare-app-prod-prodv1</BucketName> … sgp1b
  ```
  So this is **not** NoSuchBucket / wrong-region — the endpoint (`sgp1`) is right.
- **Active Spaces keys are all `fullaccess`** (`doctl spaces keys list`):
  `yescare-prod-tf`, `YesCare-Preprod-Terraform`, `YesCare-PreProd-Terraform` — so if the
  app used any of them, writes would succeed.
- **App creds were never rotated at cutover.** `prod-scripts/update-secrets-prod.sh` sets
  `PROD_S3_BUCKET` only; the Spaces access/secret keys come from pre-existing
  backend-repo GitHub secrets (`*_SPACES_ACCESS_KEY` / `*_SPACES_SECRET_KEY`) minted
  Apr–Jul 2 — i.e. an **old** key.
- **On 2026-07-21, 4 Spaces keys were revoked** during a cleanup (`terraform`,
  `yescare-terraform-owner`, `yescare-terraform-key`, `temp-sync`).

**Conclusion:** the apps were signing uploads with one of the revoked keys → every
`PutObject` returns 403 (`InvalidAccessKeyId`) across dev/preprod/prod simultaneously.

### Services affected
All three services carrying Spaces credentials in their k8s secret:
- `hospital-service-secret` — keys `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
  `DO_SPACES_ACCESS_KEY`, `DO_SPACES_SECRET_KEY`
- `payment-service-secret` — `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
- `user-bff-secret` — `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`

### Fix

**1. Create a dedicated app Spaces key** (decoupled from terraform-key lifecycle):
```bash
doctl spaces keys create yescare-app-storage --grants 'bucket=;permission=fullaccess'
# → name: yescare-app-storage   access_key: DO00LZ39FTW3FYWE34EW   (secret handled out-of-band)
```
Smoke-tested a PUT + DELETE against `yescare-app-prod-prodv1` via the `sgp1` endpoint = OK.

**2. Rotate into live k8s secrets** (immediate fix), across all 3 clusters, using a
merge patch (`stringData`, so only these keys change):
```bash
# patch sets AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY + DO_SPACES_ACCESS_KEY/DO_SPACES_SECRET_KEY
kubectl --context do-sgp1-yescare-prod-scale-k8s    -n prod patch secret <svc>-secret --patch-file patch.json
kubectl --context do-sgp1-yescare-preprod-scale-k8s -n prod patch secret <svc>-secret --patch-file patch.json
kubectl --context do-sgp1-dev-doks                  -n dev  patch secret <svc>-secret --patch-file patch.json
# <svc> = hospital-service, payment-service, user-bff
kubectl --context <ctx> -n <ns> rollout restart deploy/<svc>
```

**3. Rotate backend-repo GitHub secrets** so redeploys don't revert (8 secrets):
```
DEV_SPACES_ACCESS_KEY  PROD_SPACES_ACCESS_KEY  DO_SPACES_ACCESS_KEY  PROD_DO_SPACES_ACCESS_KEY   → new access key
DEV_SPACES_SECRET_KEY  PROD_SPACES_SECRET_KEY  DO_SPACES_SECRET_KEY  PROD_DO_SPACES_SECRET_KEY   → new secret key
gh secret set <NAME> --repo YesCare-Tech/yescare-backend < value_file
```

### Verification
- New key PUT/DELETE to prod bucket succeeded.
- `hospital-service` restarted **1/1 in prod, preprod, dev**.
- `payment-service` / `user-bff` restarted in all 3 clusters (Spring startup gate ≈3 min).
- **Recommended manual E2E:** perform a real `POST /api/v1/profile/save` (doctor profile
  upload) and confirm 200 + object in `yescare-app-prod-prodv1`.

### Notes / gotchas
- **hospital-service readiness probe** = `initialDelaySeconds: 180` on
  `/actuator/health/readiness:9090` → rollouts take ~3–3.5 min. Use
  `kubectl rollout status --timeout=240s` or it will falsely "time out".
- Transient `http2: client connection lost` / `TLS handshake timeout` occurred on a couple
  of restart calls (API server load) — `rollout restart` is idempotent, just re-issue.
- Secret material was kept in `/tmp` files (mode 600) only during the change and then
  **shredded**. Access key IDs are public identifiers; secret keys were never printed.

### Durable follow-ups
- **Do NOT revoke `yescare-app-storage`** in future Spaces-key cleanups — it is the app
  storage key now, not a terraform key.
- Teach `prod-scripts/update-secrets-prod.sh` to set the Spaces access/secret keys
  (currently a gap — it only sets `PROD_S3_BUCKET`).
- If anything outside these 3 services used the old revoked key (cron/backup/external
  integrations), it is still broken — scan and rotate those too.
- Least-privilege improvement: `yescare-app-storage` is `fullaccess`; could be scoped to
  the app/archive/logs buckets per env.
