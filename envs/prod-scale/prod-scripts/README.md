# PROD (Tier 0) scripts — the handover "bible", one command, no manual steps

These scripts build the **entire** prod environment end to end. A new operator only
needs to install the CLIs, authenticate, export three secrets, and run **one** script.

> The scripts in the *parent* dir (`setup-kafka.sh`, `setup-db.sh`, …) are the old
> **preprod-hardcoded, Linux-only** versions — do NOT use them. Everything here is
> prod-targeted and macOS/Linux portable. All config lives in `prod.env`.

## TL;DR — build all of prod
```bash
# 1. Install: doctl, kubectl, helm, gh, psql, aws, terraform, python3
# 2. Authenticate:
doctl auth init
gh auth login
# 3. Export secrets (the only manual input):
export TF_VAR_do_token=...            # DigitalOcean API token
export TF_VAR_spaces_access_id=...    # Spaces key for the terraform state backend
export TF_VAR_spaces_secret_key=...
export ADMIN_PIN=<private-pin>        # optional (default 123456 — rotate!)
# 4. Run everything:
cd digitalocean/envs/prod-scale/prod-scripts
./setup-prod.sh
```
`./setup-prod.sh --list` shows the stages; `--from N` resumes; `--only N` runs one.

## What runs, in order (`setup-prod.sh`)
| # | Script | Does |
|---|--------|------|
| 0 | `00-preflight.sh` | verify tools / auth / secrets |
| 1 | `01-terraform-apply.sh` | `terraform init` (isolated state key) + `apply` → cluster, PG, Redis, Spaces bucket, VPC; saves kubeconfig |
| 2 | `02-platform-addons.sh` | helm: ingress-nginx + cert-manager + `letsencrypt-prod` ClusterIssuer |
| 3 | `03-app-spaces-key.sh` | create the app Spaces key → `prod.secrets` (gitignored) |
| 4 | `setup-kafka-prod.sh` | in-cluster Kafka (3-broker KRaft, **RF=3**) + topics |
| 5 | `setup-db-prod.sh` | per-service Postgres schema grants |
| 6 | `db-config-prod.sh` | managed-DB tuning (Valkey `valkey_timeout=0`, no idle disconnect) |
| 7 | `update-secrets-prod.sh` | **CD cutover** — GitHub secrets → new cluster (incl. Spaces creds) |
| 8 | `deploy-services-prod.sh` | deploy the 6 backend services |
| 9 | `04-monitoring.sh` | scale nodes + Prometheus/Grafana/Loki/Tempo/Promtail/otel |
| 10 | `05-ingress-dns-tls.sh` | LB IP → `apiprod` + `grafana` DNS → auto TLS |
| 11 | `06-seed-admin.sh` | SUPER_ADMIN login in `auth_db` |
| 12 | `07-point-web.sh` | website (App Platform) → prod backend |
| 13 | `08-upload-assets.sh` | seed app assets into the bucket (fixes icons) |
| 14 | `verify-prod.sh` | read-only verification |

## ⚠️ Notes for the operator
- **Stage 7 is the live cutover.** It overwrites the `YesCare-Tech/yescare-backend`
  `PROD_*` / `KUBE_CONFIG_PROD` / `DOKS_PROD_CLUSTER_NAME` / Spaces secrets to point at
  this cluster. After it runs, every `environment=prod` deploy targets here.
- **`prod.secrets`** (app Spaces key) is created by stage 3 and gitignored. Keep it safe;
  don't revoke that Spaces key in future cleanups (it's the app upload key).
- **`ADMIN_PIN`** defaults to `123456` — set a private one before running, or reset later
  with `ADMIN_PIN=xxxxxx ./06-seed-admin.sh`.
- **`apiprod` ingress host**: the durable home for the `apiprod.yescare.co.in` host is the
  backend repo's ingress template (see RUNBOOK §8). Stage 9 handles DNS + TLS.
- Re-run any single stage idempotently, e.g. `./setup-prod.sh --only 12` to re-seed assets.

Full narrative + gotchas: `../RUNBOOK_PROD_TIER0_FROM_SCRATCH.md`.
