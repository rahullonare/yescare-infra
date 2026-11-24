# RUNBOOK — Create a Fresh Production Environment on DigitalOcean (Tier 0)

Self-contained, reproducible guide. Follow top-to-bottom. Written from the real
2026-07-21 build of `yescare-prod-scale-k8s`. **Read §7 (Gotchas) before you start**
— they are the non-obvious things that will otherwise break your apply.

- **Region:** sgp1 (Singapore)
- **Target:** ~$115/mo, serves a few-hundred concurrent users, autoscales toward ~1K
- **Result:** DOKS cluster + managed Postgres + Valkey + Kafka + 6 services, reachable at
  `https://apiprod.yescare.co.in` with valid Let's Encrypt TLS.

---

## ⭐ Fastest path — one command (no manual steps)

The entire build below is automated in `prod-scripts/`. A new operator does NOT need to run
the manual steps in §3–§12 by hand — those sections are the **reference/explanation** behind
each scripted stage. To just build prod:

```bash
doctl auth init && gh auth login
export TF_VAR_do_token=...  TF_VAR_spaces_access_id=...  TF_VAR_spaces_secret_key=...
export ADMIN_PIN=<private-pin>            # optional; default 123456 — rotate
cd digitalocean/envs/prod-scale/prod-scripts
./setup-prod.sh                          # runs all 14 stages in order
#   --list  show stages   |   --from N  resume   |   --only N  run one
```
See `prod-scripts/README.md` for the stage table. The rest of this runbook explains **what
each stage does and why** (and the gotchas in §7 that the scripts already handle).

---

## 0. What you end up with

| Resource | Name |
|---|---|
| Kubernetes | `yescare-prod-scale-k8s` (2× s-2vcpu-4gb) |
| Postgres | `yescare-prod-scale-pg` (db-s-1vcpu-2gb, single node) |
| Valkey/Redis | `yescare-prod-scale-redis` (db-s-1vcpu-2gb) |
| Kafka | in-cluster **3-broker KRaft StatefulSet, RF=3** (ns `messaging`) — one broker per node |
| Services | auth, hospital, payment, notification, user-bff, websocket-gateway (ns `prod`) |
| Public API | `https://apiprod.yescare.co.in` → ingress-nginx LB |
| Registry | `registry.digitalocean.com/yescare/*` (account-global, shared) |

---

## 1. Prerequisites (install + authenticate)

```bash
# tools (macOS)
brew install doctl kubectl terraform gh jq

# 1a. doctl — DO API
doctl auth init            # paste a DO API token; verify:
doctl account get

# 1b. gh — GitHub (needed for secrets + deploy trigger)
gh auth login              # GitHub.com → HTTPS → browser. Account needs ADMIN on
                           # YesCare-Tech/yescare-backend (set secrets) + workflow (dispatch)
gh auth status

# 1c. kubectl comes from doctl per-cluster (see §4).
```

> ⚠️ **macOS note:** the repo's *original* helper scripts (`../setup-*.sh`) use GNU-only
> `grep -oP` and `base64 -w0`, which DO NOT exist on macOS. Use the `prod-scripts/`
> in this folder instead (they're portable). See §7.1.

---

## 2. Credentials you must create

### 2a. DigitalOcean API token → `TF_VAR_do_token`
Control panel only (CLI cannot mint tokens):
https://cloud.digitalocean.com/account/api/tokens → **Generate New Token** →
name `yescare-prod-terraform`, **Full Access** → copy `dop_v1_…` (shown once).
(Quick reuse alternative: `doctl auth token` prints the token doctl already uses.)

### 2b. Spaces access key → `TF_VAR_spaces_access_id` + `TF_VAR_spaces_secret_key`
```bash
doctl spaces keys create yescare-prod-tf --grants 'bucket=;permission=fullaccess'
# prints Access Key (DO00…) and Secret (shown ONCE) — save both.
```

### 2c. Export for this shell session
```bash
export TF_VAR_do_token="dop_v1_..."
export TF_VAR_spaces_access_id="DO00..."
export TF_VAR_spaces_secret_key="..."
```

---

## 3. Create the infra with Terraform

Directory: `digitalocean/envs/prod-scale`. Config file: `terraform.tfvars.prod-tier0`
(already in the repo; key values below).

```hcl
env          = "prod"                 # -> resources named yescare-prod-scale-*
region       = "sgp1"
vpc_ip_range = "10.50.0.0/16"          # MUST differ from preprod (10.40) & dev (10.1)
project_id   = "<DO project UUID>"     # e.g. yescare-prod project; or bootstrap-prod output
k8s_version  = "1.35.5-do.3"           # doctl kubernetes options versions
k8s_node_size = "s-2vcpu-4gb"
k8s_min_nodes = 2
k8s_max_nodes = 4
k8s_ha_control_plane = false           # Tier 0 saves $40/mo
db_size = "db-s-1vcpu-2gb"
db_node_count = 1
redis_size = "db-s-1vcpu-2gb"
spaces_bucket_suffix = "prodv1"
create_registry = false                # registry is account-global; already exists
kafka_replica_count = 1                 # Tier 0
kafka_topic_replication_factor = 1
letsencrypt_email = "ops@yescare.co.in"
domain_name = ""                        # leave empty — we wire apiprod manually (§5)
load_balancer_ip = ""
```

### 3a. Init with an ISOLATED state key (critical — see §7.2)
```bash
cd digitalocean/envs/prod-scale
terraform init -reconfigure \
  -backend-config="access_key=$TF_VAR_spaces_access_id" \
  -backend-config="secret_key=$TF_VAR_spaces_secret_key" \
  -backend-config="key=envs/prod-scale/prod.tfstate"   # <-- prod-only key, NOT the preprod state
```

### 3b. Plan & apply
```bash
terraform plan  -var-file=terraform.tfvars.prod-tier0 -out=prod.plan   # review: all NEW yescare-prod-scale-*
terraform apply prod.plan
```

**Expect the apply to ERROR at the end** on `null_resource.setup_db` /
`update_github_secrets` (they run preprod-hardcoded, Linux-only scripts). That is OK —
the *infrastructure* (cluster, PG, Redis, ingress, cert-manager) is created. We finish
the rest with the portable `prod-scripts/` in §4. See §7.1/§7.3.

---

## 4. Complete the cluster with prod-scripts/

All portable, all target the prod cluster (they source `prod-scripts/prod.env`).

```bash
cd digitalocean/envs/prod-scale/prod-scripts

./setup-kafka-prod.sh     # 1. Kafka + 24 topics on prod        (prod-only, safe)
./setup-db-prod.sh        # 2. schema grants on prod PG          (prod-only, safe)
./update-secrets-prod.sh  # 3. GitHub secrets -> new cluster     ⚠️ CD CUTOVER (needs gh)
./deploy-services-prod.sh # 4. trigger backend deploy.yml (prod) (needs gh)
./verify-prod.sh          # 5. read-only verify
```

- **Step 3 is the cutover.** It overwrites `YesCare-Tech/yescare-backend`'s `PROD_*`,
  `KUBE_CONFIG_PROD`, `DOKS_PROD_CLUSTER_NAME` secrets to point at the new cluster.
  After this, every `environment=prod` deploy goes here. Only run when ready.
- Watch deploys: `gh run list --repo YesCare-Tech/yescare-backend`
- Watch pods: `kubectl --context do-sgp1-yescare-prod-scale-k8s get pods -n prod -w`
  (expect all 6 → `Running 1/1`).

---

## 5. DNS + Ingress host + TLS

### 5a. Get the LB IP and point apiprod
```bash
CTX=do-sgp1-yescare-prod-scale-k8s
doctl kubernetes cluster kubeconfig save yescare-prod-scale-k8s --set-current-context
LB_IP=$(kubectl --context $CTX get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "$LB_IP"
doctl compute domain records create yescare.co.in \
  --record-type A --record-name apiprod --record-data "$LB_IP" --record-ttl 300
```

### 5b. Add apiprod to the Ingress (see §7.4 — the app ingress only defines `api.…`)
The backend deploy creates `Ingress/yescare-ingress` (ns `prod`) with host
`api.yescare.co.in` only. Add the `apiprod` host + its own TLS entry:
```bash
kubectl --context $CTX patch ingress yescare-ingress -n prod --type=json \
  --patch-file - <<'JSON'
[
  {"op":"add","path":"/spec/rules/-","value":{"host":"apiprod.yescare.co.in","http":{"paths":[
    {"backend":{"service":{"name":"hospital-service","port":{"number":80}}},"path":"/hospital(/|$)(.*)","pathType":"ImplementationSpecific"},
    {"backend":{"service":{"name":"auth-service","port":{"number":80}}},"path":"/auth(/|$)(.*)","pathType":"ImplementationSpecific"},
    {"backend":{"service":{"name":"user-bff","port":{"number":80}}},"path":"/bff(/|$)(.*)","pathType":"ImplementationSpecific"},
    {"backend":{"service":{"name":"payment-service","port":{"number":80}}},"path":"/payment(/|$)(.*)","pathType":"ImplementationSpecific"},
    {"backend":{"service":{"name":"notification-service","port":{"number":80}}},"path":"/notification(/|$)(.*)","pathType":"ImplementationSpecific"},
    {"backend":{"service":{"name":"websocket-gateway","port":{"number":80}}},"path":"/ws-gateway(/|$)(.*)","pathType":"ImplementationSpecific"},
    {"backend":{"service":{"name":"websocket-gateway","port":{"number":9001}}},"path":"/ws-gateway-sio(/|$)(.*)","pathType":"ImplementationSpecific"}
  ]}}},
  {"op":"add","path":"/spec/tls/-","value":{"hosts":["apiprod.yescare.co.in"],"secretName":"yescare-apiprod-tls"}}
]
JSON
```

### 5c. Create the letsencrypt-prod ClusterIssuer (see §7.5 — it's missing by default)
```bash
kubectl --context $CTX apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ops@yescare.co.in
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```
cert-manager then issues `yescare-apiprod-tls` in ~1–2 min (HTTP-01 succeeds because
`apiprod` DNS points at this cluster).

---

## 6. Verification

```bash
CTX=do-sgp1-yescare-prod-scale-k8s
kubectl --context $CTX get pods -n prod           # 6 services Running 1/1
kubectl --context $CTX get pods -n messaging      # kafka Running
kubectl --context $CTX get certificate -n prod    # yescare-apiprod-tls Ready=True
dig +short apiprod.yescare.co.in                  # -> LB IP
/usr/bin/curl -sSk -o /dev/null -w "%{http_code}\n" https://apiprod.yescare.co.in/auth/actuator/health
# 403/401 = reached a backend over valid TLS (auth secures actuator) = SUCCESS
echo | openssl s_client -servername apiprod.yescare.co.in -connect apiprod.yescare.co.in:443 2>/dev/null \
  | openssl x509 -noout -issuer -subject                 # issuer = Let's Encrypt
```

---

## 7. GOTCHAS WE HIT (read these — they will bite you)

**7.1 The original scripts are preprod-hardcoded + Linux-only.**
`../setup-kafka.sh`, `../setup-db.sh`, `../update-secrets.sh` hardcode
`yescare-preprod-scale-*` and use `grep -oP` / `base64 -w0` (GNU only). On macOS they
fail with `grep: invalid option -- P`; even on Linux they'd target PREPROD, not your new
prod. → Always use `prod-scripts/` (portable, prod-targeted) instead.

**7.2 State collision.** The `prod-scale` backend bucket/key is shared with preprod
(`key = envs/prod-scale/terraform.tfstate`). If you `init`/`apply` without overriding the
key, you'll modify PREPROD. Always init with `-backend-config="key=envs/prod-scale/prod.tfstate"`.

**7.3 The apply "fails" but infra is fine.** The `null_resource` provisioners at the end
of `main.tf` run the preprod scripts and error. Infra is already created. Finish with
`prod-scripts/`. **Before any future `terraform apply` on this state, remove/guard those
null_resources** or they'll re-run against preprod.

**7.4 Ingress host mismatch.** The backend's ingress only defines `api.yescare.co.in`.
`apiprod` returns 404 until you add the host (§5b). NOTE: the §5b patch is IN-CLUSTER and
**the next backend deploy reverts it.** Durable fix = add `apiprod.yescare.co.in` to the
ingress template in the `yescare-backend` repo. (§8)

**7.5 No ClusterIssuer by default.** `letsencrypt-prod` is commented out in `main.tf`, so
cert-manager can't issue ANY cert (certs sit `Ready=False` forever). Create it (§5c) and
enable it in Terraform (§8).

**7.6 `api.yescare.co.in` cert stays False** on this cluster because its DNS points at
preprod. Expected — we use `apiprod` for the new cluster. Don't chase it.

**7.7 No `monitoring` namespace on a fresh cluster (added 2026-07-21).** App pods log
`UnknownHostException: otel-collector.monitoring.svc.cluster.local:4318` forever because
the observability stack under `monitoring/` was never applied. That stack has **no
Namespace manifest and no apply script**, and several of its files are raw
`kubectl get -o yaml` dumps that break on a new cluster: the PVCs pin a dead `volumeName`
(bind **Lost**) and `services.yaml` pins old `clusterIP`s (`failed to allocate IP`). Fixes
now in-repo (`namespace.yaml` added; PVCs + services.yaml cleaned). See §11 + the incident doc.
The full stack does NOT fit Tier 0's 2 nodes (86–96% mem) — it needs a 3rd node.

**7.8 App Spaces creds are NOT rotated at cutover — and a key cleanup broke uploads
(added 2026-07-21).** `prod-scripts/update-secrets-prod.sh` sets `PROD_S3_BUCKET` only; the
Spaces access/secret keys come from pre-existing `yescare-backend` GitHub secrets. On
2026-07-21 four surplus Spaces keys were revoked — one was the key the apps signed uploads
with, so every `PutObject` began returning **403** fleet-wide (`StorageService`,
`/api/v1/profile/save`). Fix = dedicated app key `yescare-app-storage` rotated into k8s +
GitHub secrets (§11). Bucket/region were fine; it was purely a dead credential.

**7.9 The admin-seed script doesn't match the deployed schema (added 2026-07-21).** Prod's
auth-service (branch `release-1.0.0`) supports only **2 admin scopes** (`SUPER_ADMIN`,
`HOSPITAL_ADMIN`) and migration V11 auto-seeds SUPER_ADMIN `9000000001`. The repo's
`insert-admin.sql` is a stale **4-scope** script → it errors on prod (enum rejects
`ONBOARDING/HEALTHCARE/FIRSTAIDKIT_ADMIN`). Don't run it blind; see **§12** for the correct
inspect-first + psql-pod procedure to create/reset admins.

**7.10 Kafka was ephemeral → topics vanish on restart (fixed 2026-07-22).** The original
`kafka.yaml` had **no volume** and `KAFKA_AUTO_CREATE_TOPICS_ENABLE=false`. When the broker
pod was recreated, ALL topics were lost and every consumer logged
`Error while fetching metadata … UNKNOWN_TOPIC_OR_PARTITION`. Fixed: `kafka.yaml` now has a
**PVC** (`Recreate` strategy, `fsGroup: 1000`) + **auto-create=true**. Gotcha within the fix:
DO block volumes carry an ext4 `lost+found` at the mount root, which Kafka refuses as a log
dir — so `KAFKA_LOG_DIRS` points at a **subdir** (`/var/lib/kafka/data/kafka-logs`), not the
mount root. Also the topic list in `setup-kafka-prod.sh` was stale (missing `user.notification`
+ `auth.force-logout`) — now added.

**7.11 Kafka is now 3-broker RF=3 (upgraded 2026-07-22, before real traffic).** `kafka.yaml`
is a **StatefulSet** (`replicas: 3`, `podManagementPolicy: Parallel`, hard anti-affinity =
one broker per node, per-pod PVC, shared `CLUSTER_ID`, controller quorum of all 3,
`default.replication.factor=3` / `min.insync.replicas=2`). The bootstrap **service name stays
`kafka`** so apps need no change. **Capacity:** three brokers need **3 schedulable nodes with
room**; on Tier 0 this pushed the pool to **4–5 nodes** (autoscaler `min=4/max=5`) — a real
cost bump. `setup-kafka-prod.sh` creates topics at RF=3 (retried; kubectl-exec streams to a
fresh node can drop mid-batch — it's idempotent). Verify: `kafka-metadata-quorum.sh … describe
--status` → `CurrentVoters [1,2,3]`, and `--under-replicated-partitions` empty.

**7.12 Firebase (FCM) creds must be WHITESPACE-FREE base64 (added 2026-07-23).**
notification-service logs `[FCM] app 'user'/'doctor' not initialized … sent=false` when the
`FIREBASE_USER_CREDENTIALS` / `FIREBASE_DOCTOR_CREDENTIALS` secret values contain spaces or
newlines. The app uses Java's **strict** `Base64.getDecoder()`, which throws
`Illegal base64 character 20` (0x20 = space) → creds null → the FirebaseApp never initializes
(Kafka + in-app notifications still work, so it's easy to miss). Fix: store the service-account
JSON as **single-line base64** — `base64 -w0 sa.json` (Linux) or `base64 < sa.json | tr -d '\n'`
(macOS) — in both the k8s `notification-service-secret` and GitHub `PROD_FIREBASE_*` secrets, then
**restart** (env is read only at pod start): `kubectl -n prod rollout restart deploy/notification-service`.
Success log: `FirebaseApp 'user'/'doctor' initialized (source=base64-env)`. NOTE: these are Admin
SDK **service-account** JSONs (`"type":"service_account"`, has `private_key`) — NOT the Android
`google-services.json` (that's a client config and won't work).

---

## 8. Durable IaC follow-ups (do these so it survives redeploys)

1. **yescare-backend repo:** add `apiprod.yescare.co.in` host (paths + a `tls` entry with
   `secretName: yescare-apiprod-tls`) to the ingress manifest/template.
2. **prod-scale/main.tf:** uncomment/enable the `letsencrypt-prod` ClusterIssuer resource.
3. **prod-scale/main.tf:** make the `null_resource` provisioners env-aware (call
   `prod-scripts/` or pass `CLUSTER=yescare-${var.env}-scale-*`) OR drop them and run
   `prod-scripts/` by hand. Otherwise re-apply targets preprod.
4. Commit `terraform.tfvars.prod-tier0` (no secrets in it) + `prod-scripts/` to the repo.
5. **monitoring/**: keep `namespace.yaml` + the cleaned `loki-pvc.yaml` / `tempo-pvc.yaml` /
   `deployments/services.yaml`; add a small apply script or kustomization so the stack is
   reproducible (ordering: ns → rbac → configmaps → PVCs → services → deployments → ingress).
6. **prod-scripts/update-secrets-prod.sh**: also set the Spaces access/secret keys (currently
   a gap — it only sets `PROD_S3_BUCKET`, so app storage creds silently drift/expire).
7. **Do NOT revoke the `yescare-app-storage` Spaces key** in future key cleanups — it is the
   app upload key now (used by hospital-service, payment-service, user-bff), not a terraform key.

---

## 9. Day-2 operations

**Start/stop any cluster (cost control):**
```bash
digitalocean/scripts/cluster-power.sh status yescare-prod-scale-k8s
digitalocean/scripts/cluster-power.sh stop   yescare-prod-scale-k8s   # scale nodes -> 0
digitalocean/scripts/cluster-power.sh start  yescare-prod-scale-k8s   # back to 1/pool
```
(Managed Postgres/Redis cannot be paused on DO — nodes only.)

**Redeploy a service:** `gh workflow run deploy.yml --repo YesCare-Tech/yescare-backend
--field environment=prod --field service=<name> --field image_tag=latest`

**Point the website at this prod backend.** The public site `www.yescare.co.in` /
`yescare.co.in` is the App Platform app **`king-prawn-app`** (static site `yescare-web`, Vite,
repo `YesCare-Tech/yescare-web`, `deploy_on_push`). Its API target is a **BUILD_TIME env var
`VITE_API_BASE_URL` in the App Platform spec** — a repo edit alone won't change it; the
build-time env overrides. To repoint (done 2026-07-21 → `apiprod.yescare.co.in`):
```bash
APPID=bb281529-b56d-460c-83df-6ac556cd33c2      # king-prawn-app
doctl apps spec get "$APPID" > /tmp/kpa.yaml
sed -i '' 's#value: https://api.yescare.co.in/bff/api/v1#value: https://apiprod.yescare.co.in/bff/api/v1#' /tmp/kpa.yaml
doctl apps update "$APPID" --spec /tmp/kpa.yaml       # triggers a zero-downtime rebuild
doctl apps list-deployments "$APPID" --format ID,Cause,Phase | head -2   # wait for ACTIVE
```
Before switching, verify the backend is ready: `curl -I https://apiprod.yescare.co.in/bff/api/v1/`
(expect 401/valid TLS) and CORS allows the site origin (`OPTIONS` with
`Origin: https://www.yescare.co.in` → `access-control-allow-origin` echoes it). Verify after:
the live JS bundle under `https://www.yescare.co.in/assets/*.js` should contain
`apiprod.yescare.co.in`. NOTE: `yescare-web` source still hardcodes a fallback
`api.yescare.co.in` — if the env var is ever unset it falls back to (dead) preprod; fix in the
web repo.

**Seed static app assets into the prod bucket (fixes "missing icons").** A fresh prod
Spaces bucket has none of the objects the DB references as relative keys (e.g.
`speciality.image_url = 'specialities/general-surgery.svg'`, plus `wellness_tips/`, `app/`),
so icons 404. The assets are versioned in this repo under `assets/prod-app-bucket/` and
uploaded with:
```bash
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=...   # Spaces key w/ rw on the bucket
scripts/upload-prod-app-assets.sh --dry-run              # preview
scripts/upload-prod-app-assets.sh --acl private          # upload (private = matches source;
                                                          # app serves via backend, not public read)
```
Objects were sourced from bucket `prod-yescare-app`. NOTE: the DB references
`specialities/nutrition.svg` + `physiotherapy.svg` which are **absent from the source** —
add those SVGs to `assets/prod-app-bucket/specialities/` and re-run to fix the last two.
If icons still don't render after upload, the app expects public objects → re-run with
`--acl public-read`.

**Scaling / when to grow (Tier 0 → Tier 1):** see `PROD_SCALABLE_ROADMAP_10_TO_10M.md`
and `monitoring/CAPACITY_MONITORING.md`. Trigger: Postgres CPU >70% sustained, DB pool
>70%, or p95 >500ms. Tier 1 = add PG standby (`db_node_count=2`), bump DB, HA control plane.

**DB connection info:** `doctl databases connection <id> --format Host,Port,User,Password`
(use `--private` for the VPC host; add a connection pool on port 25061 at Tier 1).

**Managed-DB tuning** (`prod-scripts/db-config-prod.sh`, idempotent): the Valkey/Redis default
`valkey_timeout=300` drops idle client connections every 5 min → all services log Lettuce
`Reconnecting/Reconnected` when idle. The script sets `valkey_timeout=0`. Gotcha: the API field
is **`valkey_timeout`** and engine **`valkey`** (not `timeout`/`redis`) — wrong names return
`422 the mask must be set`.

---

## 10. Teardown (if you need to remove this prod)

```bash
cd digitalocean/envs/prod-scale
terraform init -reconfigure \
  -backend-config="access_key=$TF_VAR_spaces_access_id" \
  -backend-config="secret_key=$TF_VAR_spaces_secret_key" \
  -backend-config="key=envs/prod-scale/prod.tfstate"
terraform destroy -var-file=terraform.tfvars.prod-tier0
# then orphan sweep (DOKS-created, not in TF state):
doctl compute load-balancer list   # delete the prod ingress LB
doctl compute volume list          # delete any orphaned pvc-* volumes
doctl compute firewall list        # delete leftover k8s-<clusterid>-* firewalls
doctl compute domain records list yescare.co.in   # delete the apiprod A record
```
Do NOT remove the shared `yescare` registry, `king-prawn-app` (prod website), or dev/preprod.

---

## 11. Day-2 change log — 2026-07-21 (go-live day)

Two changes made against prod `yescare-prod-scale-k8s` on the Tier 0 build day.
Full detail + exact commands: `INCIDENT_2026-07-21_MONITORING_AND_S3_403.md`.

**A. Deployed the observability stack into a new `monitoring` namespace.**
- Trigger: app pods logging `UnknownHostException` for `otel-collector` (§7.7).
- Scaled the default pool **2 → 3 nodes** (`min=3`, `s-2vcpu-4gb`, ≈ +$24/mo) — the full
  stack (~1.0 GiB req + 20 GiB disk) does not fit 2 nodes:
  ```bash
  doctl kubernetes cluster node-pool update <cluster-id> <pool-id> \
    --count 3 --auto-scale --min-nodes 3 --max-nodes 4
  ```
- Added `monitoring/namespace.yaml`; rewrote `loki-pvc.yaml`/`tempo-pvc.yaml` clean
  (dropped dead `volumeName` → they now Bind); stripped pinned `clusterIP`s from
  `deployments/services.yaml`. Applied: ns → rbac → configmaps → PVCs → services →
  deployments → grafana-ingress.
- Result: otel-collector 1/1 (error resolved); Grafana/Prometheus/Loki/Tempo/Promtail up.
- Open: create DNS **A `grafana.yescare.co.in → 139.59.216.77`** so its cert issues.

**B. Fixed fleet-wide S3 403 uploads (revoked Spaces key — §7.8).**
- Root cause: apps signed uploads with a Spaces key revoked on 2026-07-21; cutover never
  rotated app storage creds. Bucket `yescare-app-prod-prodv1` (sgp1) is fine.
- Created dedicated key **`yescare-app-storage`** (access id `DO00LZ39FTW3FYWE34EW`,
  `fullaccess`); smoke-tested PUT/DELETE against the prod bucket.
- Rotated it into k8s secrets for **hospital-service, payment-service, user-bff** across
  **prod + preprod + dev** (`patch secret --patch-file` on `AWS_ACCESS_KEY_ID` /
  `AWS_SECRET_ACCESS_KEY` [+ `DO_SPACES_*` for hospital]) and `rollout restart`ed each.
- Rotated 8 `yescare-backend` GitHub secrets (`DEV_/PROD_/DO_/PROD_DO_ SPACES_ACCESS_KEY`
  + `_SECRET_KEY`) so redeploys keep the new key.
- Verified: hospital-service 1/1 in all clusters; new key writes to the bucket. Recommended
  manual E2E: a real `POST /api/v1/profile/save`.
- Watch out: hospital-service readiness `initialDelaySeconds: 180` → use
  `rollout status --timeout=240s`. If anything outside these 3 services used the old key,
  it is still broken — scan and rotate.

---

## 12. Admin-portal logins (auth-service / `auth_db`)

The web **admin portal** authenticates against the **auth-service** database (`auth_db`),
using the `users` + `user_credentials` tables. An admin is a row in `users` with
`user_type = 'ADMIN'` and an `admin_scope`; the login PIN is a **bcrypt** hash in
`user_credentials.pin_hash` (Spring `BCryptPasswordEncoder`, `$2a$` prefix). Admins sign in
with **phone + PIN** at `POST /bff/api/v1/auth/login/admin`.

### 12.0 READ THIS FIRST — the admin model depends on the deployed branch ⚠️
There are two different admin models floating around the codebase. **What prod supports
depends on which auth-service branch is deployed** — check before you seed anything.

- **Prod today runs branch `release-1.0.0`** (image `ghcr.io/yescare-tech/auth-service:latest`).
  Its migration **V12** makes `admin_scope` an **enum with only two values:
  `SUPER_ADMIN`, `HOSPITAL_ADMIN`**. Its migration **V11 already auto-creates the
  SUPER_ADMIN** `9000000001` on a fresh DB — so it always exists after deploy.
- The repo's root **`insert-admin.sql` is STALE**: it seeds a **4-scope** model
  (`SUPER_ADMIN`, `ONBOARDING_ADMIN`, `HEALTHCARE_ADMIN`, `FIRSTAIDKIT_ADMIN`). The last
  three are **not** in prod's enum, so running it against prod **fails** with
  `invalid input value for enum admin_scope_enum: "ONBOARDING_ADMIN"` after a no-op on the
  already-existing SUPER_ADMIN. **Do not expect it to create 4 admins on prod.**
- Bottom line: on current prod you can only have **SUPER_ADMIN** and **HOSPITAL_ADMIN**.
  To get the 4-scope portal you must first ship an auth-service version that expands the
  enum (`ALTER TYPE admin_scope_enum ADD VALUE …`) + the app logic, then seed.

**Always confirm the live model before writing** (§12.1) instead of trusting the script.

### 12.1 Inspect what's actually there (read-only)
All admin DB work uses a throwaway `psql` pod in the `prod` namespace, connecting to the
managed PG as `yescare_app` (the `auth_db` owner). Resolve connection info by name:

```bash
CTX=do-sgp1-yescare-prod-scale-k8s
PGID=$(doctl databases list --no-header --format ID,Name | awk '$2=="yescare-prod-scale-pg"{print $1}')
PG_HOST=$(doctl databases connection "$PGID" --no-header --format Host)
AUTH_PW=$(doctl databases user get "$PGID" yescare_app --no-header --format Password)   # kept in shell var, never echo

kubectl --context $CTX -n prod run psql-admin --image=postgres:16 --restart=Never -- sleep 300
kubectl --context $CTX -n prod wait --for=condition=ready pod/psql-admin --timeout=120s

# inspect: enum values, existing admins, flyway version
kubectl --context $CTX -n prod exec -i psql-admin -- \
  env PGPASSWORD="$AUTH_PW" psql "sslmode=require host=$PG_HOST port=25060 dbname=auth_db user=yescare_app" -tA <<'SQL'
SELECT 'scopes: '||string_agg(enumlabel,', ' ORDER BY enumsortorder) FROM pg_enum WHERE enumtypid='admin_scope_enum'::regtype;
SELECT phone_number, admin_scope, status FROM users WHERE user_type='ADMIN' ORDER BY phone_number;
SELECT version, description FROM flyway_schema_history ORDER BY installed_rank DESC LIMIT 3;
SQL
```
(Leave the pod running if you're about to do §12.2/§12.3; otherwise
`kubectl --context $CTX -n prod delete pod psql-admin`.)

### 12.2 Reset an existing admin's PIN
Use this for the auto-seeded SUPER_ADMIN `9000000001` (its V11 PIN is unknown), or any admin.
Replace `<PHONE>` and `<PIN>` (PINs are 6-digit numeric):

```bash
kubectl --context $CTX -n prod exec -i psql-admin -- \
  env PGPASSWORD="$AUTH_PW" psql "sslmode=require host=$PG_HOST port=25060 dbname=auth_db user=yescare_app" -v ON_ERROR_STOP=1 <<'SQL'
CREATE EXTENSION IF NOT EXISTS pgcrypto;
UPDATE user_credentials
SET pin_hash = crypt('<PIN>', gen_salt('bf', 10)),   -- bcrypt $2a$, strength 10
    failed_attempts = 0, locked_until = NULL          -- also clears any lockout
WHERE user_id = (SELECT id FROM users WHERE phone_number='<PHONE>' AND user_type='ADMIN');
-- verify without printing the hash:
SELECT phone_number, admin_scope, status,
       (c.pin_hash = crypt('<PIN>', c.pin_hash)) AS pin_ok
FROM users u JOIN user_credentials c ON c.user_id=u.id WHERE phone_number='<PHONE>';
SQL
```
`pin_ok = t` means the PIN verifies. (Done 2026-07-21 for `9000000001` → PIN `123456`.)

### 12.3 Create a new admin (only scopes the enum allows)
On current prod that means `HOSPITAL_ADMIN` (SUPER_ADMIN already exists). Idempotent upsert:

```bash
kubectl --context $CTX -n prod exec -i psql-admin -- \
  env PGPASSWORD="$AUTH_PW" psql "sslmode=require host=$PG_HOST port=25060 dbname=auth_db user=yescare_app" -v ON_ERROR_STOP=1 <<'SQL'
CREATE EXTENSION IF NOT EXISTS pgcrypto;
WITH up AS (
  INSERT INTO users (phone_number, status, user_type, admin_scope)
  VALUES ('<PHONE>', 'ACTIVE'::user_status_enum, 'ADMIN'::user_type_enum, 'HOSPITAL_ADMIN')
  ON CONFLICT (phone_number) DO UPDATE SET user_type='ADMIN', status='ACTIVE'
  RETURNING id
)
INSERT INTO user_credentials (user_id, pin_hash, failed_attempts)
SELECT id, crypt('<PIN>', gen_salt('bf',10)), 0 FROM up
ON CONFLICT (user_id) DO UPDATE SET pin_hash=EXCLUDED.pin_hash, failed_attempts=0, locked_until=NULL;
SQL
```
Then clean up: `kubectl --context $CTX -n prod delete pod psql-admin`.

### 12.4 Verify login
```bash
curl -sS -X POST https://apiprod.yescare.co.in/bff/api/v1/auth/login/admin \
  -H 'Content-Type: application/json' \
  -d '{"phoneNumber":"9000000001","pin":"123456"}'
# expect a JWT / 200; 401 = wrong PIN or locked.
```

> 🔐 **Security:** `123456` (and the repo's `089908` / bcrypt placeholders) are **public
> defaults** — fine for first login, but rotate every prod admin PIN to a private value via
> §12.2 and don't commit real PINs. Consider unique PINs per admin.

---

## 13. Third-party secrets — HMS (100ms) & Razorpay

These live in **three** places. GitHub secrets are the source of truth for deploys; the live
k8s secrets are what running pods use; the website carries only the Razorpay **browser** key id.

| Secret | GitHub (`YesCare-Tech/yescare-backend`) | Live k8s (ns `prod`) | Website (`king-prawn-app`) |
|---|---|---|---|
| **HMS** (video) | `PROD_HMS_ACCESS_KEY`, `PROD_HMS_SECRET`, `PROD_HMS_MANAGEMENT_TOKEN` | `hospital-service-secret` → `HMS_ACCESS_KEY`, `HMS_SECRET`, `HMS_MANAGEMENT_TOKEN` | — |
| **Razorpay (server)** | `PROD_RAZORPAY_KEY_ID`, `PROD_RAZORPAY_KEY_SECRET` | `payment-service-secret` → `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` | — |
| **Razorpay (browser key id)** | `VITE_RAZORPAY_KEY_ID` (does NOT drive the live site) | — | build env `VITE_RAZORPAY_KEY_ID` |

### 13.1 Rotate — do BOTH GitHub and k8s (or the next deploy reverts a k8s-only change)
```bash
R=YesCare-Tech/yescare-backend
# 1) GitHub (durable)
gh secret set PROD_HMS_ACCESS_KEY       --repo $R --body '...'
gh secret set PROD_HMS_SECRET           --repo $R --body '...'
gh secret set PROD_HMS_MANAGEMENT_TOKEN --repo $R --body '...'
gh secret set PROD_RAZORPAY_KEY_ID      --repo $R --body '...'
gh secret set PROD_RAZORPAY_KEY_SECRET  --repo $R --body '...'

# 2) Live k8s (immediate) + restart
CTX=do-sgp1-yescare-prod-scale-k8s
kubectl --context $CTX -n prod patch secret hospital-service-secret -p \
 '{"stringData":{"HMS_ACCESS_KEY":"...","HMS_SECRET":"...","HMS_MANAGEMENT_TOKEN":"..."}}'
kubectl --context $CTX -n prod patch secret payment-service-secret -p \
 '{"stringData":{"RAZORPAY_KEY_ID":"...","RAZORPAY_KEY_SECRET":"..."}}'
kubectl --context $CTX -n prod rollout restart deploy/hospital-service deploy/payment-service
```
(Or skip step 2 and just redeploy: `gh workflow run deploy.yml --repo $R -f environment=prod
-f service=payment-service -f image_tag=latest`.)

### 13.2 Website Razorpay key (App Platform build env)
```bash
APPID=$(doctl apps list --no-header --format ID,Spec.Name | awk '/king-prawn-app/{print $1}')
doctl apps spec get "$APPID" > /tmp/spec.yaml
# set VITE_RAZORPAY_KEY_ID to the matching rzp_live_… key, then:
doctl apps update "$APPID" --spec /tmp/spec.yaml     # rebuilds the site
```

> ⚠️ **The prod website ships a Razorpay TEST key (`rzp_test_…`) by default** — real payments
> fail until you set the `rzp_live_…` **browser** key id here AND the matching server
> `PROD_RAZORPAY_KEY_ID` / `_SECRET` (§13.1). Both must be the same Razorpay account/mode.
> Changing the GitHub `VITE_RAZORPAY_KEY_ID` secret alone does nothing to the live site.

---

### Reference docs in this folder
- `terraform.tfvars.prod-tier0` — the config used here
- `prod-scripts/` — portable prod scripts (+ its README)
- `PROD_TIER0_CREATE.md` — condensed create steps
- `PROD_SCALABLE_ROADMAP_10_TO_10M.md` — tiers 10 users → 10M
- `monitoring/CAPACITY_MONITORING.md` — when/how to scale up
- `INCIDENT_2026-07-21_MONITORING_AND_S3_403.md` — full day-2 detail (monitoring + S3 403)
