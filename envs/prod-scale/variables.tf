############################
# Credentials
############################
variable "do_token" {
  type        = string
  sensitive   = true
  description = "DigitalOcean API token (prod-only, never reuse dev token)"
}

variable "spaces_access_id" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Spaces access key — required when enable_spaces = true"
}

variable "spaces_secret_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Spaces secret — required when enable_spaces = true"
}

variable "kubeconfig_path" {
  type        = string
  default     = ""
  description = "Phase-1 apply: leave empty. Phase-2 apply: path to kubeconfig file."
}

############################
# Identity / placement
############################
variable "env" {
  type    = string
  default = "prod"
}

variable "region" {
  type        = string
  default     = "sgp1"
  description = "DigitalOcean region slug. sgp1 = Singapore — co-located with Spaces, ~30-50ms RTT from India users."
}

variable "vpc_ip_range" {
  type        = string
  default     = "10.30.0.0/16"
  description = "Distinct from dev (10.1/16) and legacy prod (10.22/16) to allow VPC peering later"
}

variable "project_id" {
  type        = string
  description = "DO Project UUID — REQUIRED. Run digitalocean/envs/bootstrap-prod first, then paste the project_id output here. All DOKS/Postgres/Redis/Spaces resources attach to this project for isolation from dev."

  validation {
    condition     = length(var.project_id) > 0
    error_message = "project_id is required. Run `cd ../bootstrap-prod && terraform apply` first and paste the project_id output."
  }
}

############################
# Kubernetes (DOKS)
# Defaults tuned for ~10K *concurrent* users (~1-3K RPS) in sgp1.
#  -> 3 nodes s-4vcpu-8gb (~$144/mo), autoscale to 6 for spikes
# To scale further:
#  100K concurrent  -> node_size s-4vcpu-8gb, min 5 max 12
#  1M concurrent    -> node_size s-8vcpu-16gb, min 8 max 20
#  10M concurrent   -> multi-pool, dedicated kafka pool, see README
############################
variable "k8s_version" {
  type        = string
  description = "Run: doctl kubernetes options versions --region sgp1"
}

variable "k8s_ha_control_plane" {
  type        = bool
  default     = true
  description = "HA control plane adds ~$40/mo. ON by default for production-grade."
}

variable "k8s_node_size" {
  type        = string
  default     = "s-4vcpu-8gb"
  description = "Production-grade default. 4 vCPU/8GB per node handles ~3-5K concurrent connections + room for Kafka/ingress/app pods."
}

variable "k8s_min_nodes" {
  type        = number
  default     = 3
  description = "Min 3 so 3-broker Kafka spreads across nodes (anti-affinity) and one node loss still leaves quorum."
}

variable "k8s_max_nodes" {
  type        = number
  default     = 6
  description = "Autoscale ceiling. At 10K concurrent users 6 nodes is comfortable headroom."
}

variable "k8s_auto_upgrade" {
  type    = bool
  default = true
}

############################
# PostgreSQL (managed)
# Production-grade defaults: HA (primary + standby), 2 vCPU / 4GB.
#   10K concurrent  -> db-s-2vcpu-4gb HA (~$100/mo) — current default
#   100K concurrent -> db-s-4vcpu-8gb HA
#   1M concurrent   -> larger + read replica (see README)
############################
variable "db_size" {
  type    = string
  default = "db-s-2vcpu-4gb"
}

variable "db_node_count" {
  type        = number
  default     = 2
  description = "2 = primary + standby (HA). Production-grade default. Drop to 1 only for cost-saving non-critical envs."
}

variable "db_pg_version" {
  type    = string
  default = "16"
}

variable "db_name" {
  type    = string
  default = "yescareprod"
}

variable "db_username" {
  type    = string
  default = "yescareprod"
}

variable "services" {
  type = any
}
############################
# Redis (managed)
# 10K concurrent users typically holds 2-5K active sessions.
# db-s-1vcpu-2gb (~$30/mo) gives 2x headroom over the 1gb tier.
############################
variable "redis_size" {
  type    = string
  default = "db-s-1vcpu-2gb"
}

variable "redis_eviction_policy" {
  type    = string
  default = "allkeys-lru"
}

############################
# Spaces (S3-compatible)
# Co-located with workloads in sgp1 — no cross-region egress.
############################
variable "enable_spaces" {
  type    = bool
  default = true
}

variable "spaces_region" {
  type        = string
  default     = "sgp1"
  description = "Spaces region — must be a Spaces-enabled DO region. blr1 not supported as of 2026."
}

variable "spaces_bucket_suffix" {
  type        = string
  description = "Random suffix for global uniqueness (e.g. a1b2c3)"
}

############################
# Container Registry
############################
variable "create_registry" {
  type        = bool
  default     = false
  description = "Set true on first apply if registry does not exist. False otherwise to avoid name conflicts with the dev env's registry."
}

variable "registry_name" {
  type    = string
  default = "yescare"
}

variable "registry_tier" {
  type        = string
  default     = "basic"
  description = "starter (free) | basic ($5/mo) | professional ($20/mo). Upgrade to professional at Phase 2."
}

############################
# Kafka (Bitnami Helm, KRaft combined mode)
# Phase 1 -> 3 nodes, 20Gi PVC each (combined controller+broker)
# Phase 2 -> 5 nodes, 50Gi PVC each, enable SASL
# Phase 3 -> split mode (3 controllers + 5 brokers), TLS, dedicated node pool
# Phase 4 -> consider managed (Confluent Cloud / Aiven)
############################
variable "kafka_chart_version" {
  type    = string
  default = "31.5.0"
}

variable "kafka_replica_count" {
  type        = number
  default     = 3
  description = "Number of KRaft combined nodes (each = controller + broker). 3 is the minimum for HA with RF=3."
}

variable "kafka_storage_size" {
  type        = string
  default     = "20Gi"
  description = "PVC size per Kafka node. Block storage on DO is ~$0.10/GB/mo, so 3x20Gi = ~$6/mo."
}

variable "kafka_resources_request_cpu" {
  type    = string
  default = "250m"
}

variable "kafka_resources_request_memory" {
  type    = string
  default = "1Gi"
}

variable "kafka_resources_limit_memory" {
  type    = string
  default = "2Gi"
}

variable "kafka_topic_partitions" {
  type        = number
  default     = 6
  description = "Default partitions per provisioned topic. Bump to 12-24 at Phase 2 for parallelism."
}

variable "kafka_topic_replication_factor" {
  type        = number
  default     = 3
  description = "Must be <= kafka_replica_count. RF=3 is the durability/cost sweet spot."
}

variable "kafka_topics" {
  type        = list(string)
  default     = ["prod-events", "prod-notifications", "prod-jobs", "prod-audit"]
  description = "Topics auto-created at install. Extend as your app needs."
}

############################
# Ingress
############################
variable "ingress_nginx_version" {
  type    = string
  default = "4.10.1"
}

variable "ingress_replica_count" {
  type        = number
  default     = 2
  description = "ingress-nginx pods. Bump to 3+ at Phase 2."
}

############################
# cert-manager (Let's Encrypt via cluster issuer)
############################
variable "cert_manager_version" {
  type    = string
  default = "v1.15.3"
}

variable "letsencrypt_email" {
  type        = string
  description = "Contact email for Let's Encrypt ACME registration. Leave empty to skip cluster issuer creation."
  default     = ""
}

############################
# DNS / TLS at the LB
# Set load_balancer_ip AFTER first apply:
#   kubectl get svc ingress-nginx-controller -n ingress-nginx \
#     -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
############################
variable "domain_name" {
  type        = string
  default     = ""
  description = "Root domain (e.g. yescare.in). Empty = skip DNS module."
}

variable "load_balancer_ip" {
  type    = string
  default = ""
}
