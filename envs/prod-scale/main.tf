############################
# DigitalOcean Production (scale-ready) — Phase 1 defaults
#
# Stack:
#   - VPC (10.30.0.0/16, distinct from dev/legacy-prod)
#   - DOKS (autoscale, HA-capable control plane)
#   - Managed Postgres + Managed Redis (VPC-private)
#   - Spaces (S3-compat) + Container Registry + Cloud Firewall
#   - ingress-nginx (DO LB) + cert-manager (Let's Encrypt ClusterIssuer)
#   - Kafka via Bitnami Helm (KRaft combined, 3-broker HA, PLAINTEXT in-cluster)
#   - Optional DO DNS + Let's Encrypt LB certificate
#
# Phase-1 budget: ~$210-320/mo. See README.md for Phase 2-4 scaling knobs.
############################

############################
# Networking
############################
module "vpc" {
  source   = "../../modules/vpc"
  name     = "yescare-${var.env}-scale"
  region   = var.region
  ip_range = var.vpc_ip_range
}

############################
# DOKS — autoscaling, HA-capable
############################
module "kubernetes" {
  source = "../../modules/kubernetes"

  cluster_name = "yescare-${var.env}-scale-k8s"
  region       = var.region
  vpc_uuid     = module.vpc.id
  k8s_version  = var.k8s_version
  auto_upgrade = var.k8s_auto_upgrade

  node_size  = var.k8s_node_size
  auto_scale = true
  min_nodes  = var.k8s_min_nodes
  max_nodes  = var.k8s_max_nodes

  labels = {
    workload = "general"
  }
  cluster_tags = ["yescare", var.env, "scale", "terraform"]
  tags         = ["yescare", var.env, "scale", "worker"]
}

############################
# PostgreSQL (managed)
############################
/*module "postgres" {
  source = "../../modules/postgres"

  name                  = "yescare-${var.env}-scale-pg"
  region                = var.region
  vpc_uuid              = module.vpc.id
  kubernetes_cluster_id = module.kubernetes.cluster_id

  size          = var.db_size
  pg_version    = var.db_pg_version
  database_name = var.db_name
  username      = var.db_username
  node_count    = var.db_node_count

  tags = ["yescare", var.env, "scale", "terraform"]
}
*/
module "postgres" {
  source = "../../modules/postgres"

  name                  = "yescare-${var.env}-scale-pg"
  region                = var.region
  vpc_uuid              = module.vpc.id
  kubernetes_cluster_id = module.kubernetes.cluster_id

  size       = var.db_size
  pg_version = var.db_pg_version
  node_count = var.db_node_count

  services = var.services

  tags = ["yescare", var.env, "scale", "terraform"]
}

############################
# Redis (managed)
############################
module "redis" {
  source = "../../modules/redis"

  name                  = "yescare-${var.env}-scale-redis"
  region                = var.region
  vpc_uuid              = module.vpc.id
  kubernetes_cluster_id = module.kubernetes.cluster_id

  size            = var.redis_size
  eviction_policy = var.redis_eviction_policy
  tags            = ["yescare", var.env, "scale", "terraform"]
}

############################
# Spaces
############################
module "spaces" {
  count  = var.enable_spaces ? 1 : 0
  source = "../../modules/spaces"

  region              = var.spaces_region
  app_bucket_name     = "yescare-app-${var.env}-${var.spaces_bucket_suffix}"
  logs_bucket_name    = "yescare-logs-${var.env}-${var.spaces_bucket_suffix}"
  versioning_enabled  = true
  logs_retention_days = 90
  cors_allowed_origins = var.domain_name != "" ? [
    "https://${var.domain_name}",
    "https://www.${var.domain_name}",
    "https://api.${var.domain_name}",
  ] : ["*"]
}

############################
# Container Registry (optional — shared with dev env by default)
############################
module "registry" {
  count  = var.create_registry ? 1 : 0
  source = "../../modules/registry"

  name   = var.registry_name
  region = var.region
  tier   = var.registry_tier
}

############################
# Cloud Firewall — 80/443 inbound on worker nodes
############################
module "firewall" {
  source = "../../modules/firewall"

  name          = "yescare-${var.env}-scale-fw"
  apply_to_tags = ["yescare", var.env, "scale", "worker"]

  inbound_rules = [
    { protocol = "tcp", port_range = "80", source_addresses = ["0.0.0.0/0", "::/0"] },
    { protocol = "tcp", port_range = "443", source_addresses = ["0.0.0.0/0", "::/0"] },
  ]

  depends_on = [module.kubernetes]
}

############################
# Attach all resources to the prod DO Project.
# project_id is REQUIRED (see variables.tf validation) — comes from
# bootstrap-prod/outputs.project_id. LBs created by DOKS services
# (ingress-nginx) auto-attach via the cluster.
############################
resource "digitalocean_project_resources" "prod_scale" {
  project = var.project_id

  # DO URN format: https://docs.digitalocean.com/reference/api/api-reference/#section/Introduction/URNs
  resources = compact([
    "do:kubernetes:${module.kubernetes.cluster_id}",
    "do:dbaas:${module.postgres.cluster_id}",
    "do:dbaas:${module.redis.cluster_id}",
    try(module.spaces[0].app_bucket_urn, ""),
    try(module.spaces[0].logs_bucket_urn, ""),
  ])
}

############################
# ingress-nginx
############################
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.ingress_nginx_version
  namespace        = "ingress-nginx"
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [
    templatefile("${path.module}/../../helm-values/prod/ingress-nginx-values.yaml.tpl", {
      replica_count = var.ingress_replica_count
    })
  ]

  depends_on = [module.kubernetes]
}

############################
# cert-manager
############################
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_version
  namespace        = "cert-manager"
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [file("${path.module}/../../helm-values/prod/cert-manager-values.yaml")]

  depends_on = [module.kubernetes]
}

# Let's Encrypt prod ClusterIssuer — created only if email is supplied
# # resource "kubernetes_manifest" "letsencrypt_prod_issuer" {
# #   count = var.letsencrypt_email != "" ? 1 : 0
# # 
# #   manifest = {
# #     apiVersion = "cert-manager.io/v1"
# #     kind       = "ClusterIssuer"
# #     metadata = {
# #       name = "letsencrypt-prod"
# #     }
# #     spec = {
# #       acme = {
# #         server = "https://acme-v02.api.letsencrypt.org/directory"
# #         email  = var.letsencrypt_email
# #         privateKeySecretRef = {
# #           name = "letsencrypt-prod-account-key"
# #         }
# #         solvers = [
# #           {
# #             http01 = {
# #               ingress = {
# #                 class = "nginx"
# #               }
# #             }
# #           }
# #         ]
# #       }
# # #     }
# #   }
# # 
# #   depends_on = [helm_release.cert_manager]
# # }

############################
# Kafka — Bitnami KRaft combined mode (3 nodes by default)
############################
# resource "helm_release" "kafka" {
#   name             = "kafka"
#   repository       = "oci://registry-1.docker.io/bitnamicharts"
#   chart            = "kafka"
#   version          = var.kafka_chart_version
#   namespace        = "messaging"
#   create_namespace = true
#   wait             = true
#   timeout          = 900
# 
#   values = [
#     templatefile("${path.module}/../../helm-values/prod/kafka-values.yaml.tpl", {
#       replica_count            = var.kafka_replica_count
#       storage_size             = var.kafka_storage_size
#       cpu_request              = var.kafka_resources_request_cpu
#       memory_request           = var.kafka_resources_request_memory
#       memory_limit             = var.kafka_resources_limit_memory
#       topic_partitions         = var.kafka_topic_partitions
#       topic_replication_factor = var.kafka_topic_replication_factor
#       topics                   = var.kafka_topics
#     })
#   ]
# 
#   depends_on = [module.kubernetes]
# }

############################
# Optional: DO DNS + LB certificate (Phase 2 cutover)
# Apply after ingress-nginx provisions the LB and you set load_balancer_ip in tfvars.
############################
module "domain" {
  count  = var.domain_name != "" && var.load_balancer_ip != "" ? 1 : 0
  source = "../../modules/domain"

  domain_name      = var.domain_name
  load_balancer_ip = var.load_balancer_ip
  add_www          = true
  add_api          = true
  additional_domains = [
    "www.${var.domain_name}",
    "api.${var.domain_name}",
  ]
}
/*
# Auto-update GitHub secrets after every apply
resource "null_resource" "update_github_secrets" {
  triggers = {
    pg_host    = module.postgres.database_host
    redis_host = module.redis.host
  }

  provisioner "local-exec" {
    command     = "bash ${path.module}/update-secrets.sh"
    working_dir = path.module
  }
  depends_on = [
    module.postgres,
    module.redis,
    module.kubernetes,
    null_resource.deploy_kafka
  ]
}
*/
resource "null_resource" "update_preprod_env" {
  triggers = {
    pg_host    = module.postgres.database_host
    pg_port    = module.postgres.database_port
    redis_host = module.redis.host
    redis_port = module.redis.port
  }

  provisioner "local-exec" {
    command = "bash ./update-preprod-env.sh \"${module.postgres.database_host}\" \"${module.postgres.database_port}\" \"${module.redis.host}\" \"${module.redis.port}\""

    working_dir = path.module
  }

  depends_on = [
    module.postgres,
    module.redis,
    module.kubernetes,
    null_resource.deploy_kafka
  ]
}
/*
# Deploy Kafka and create topics automatically
resource "null_resource" "deploy_kafka" {
  triggers = {
    cluster_id = module.kubernetes.cluster_id
  }
  provisioner "local-exec" {
    command     = "bash ${path.module}/pre-prod-kafka.sh"
    working_dir = path.module
  }
  depends_on = [
    module.kubernetes,
    helm_release.ingress_nginx
  ]
}
*/
resource "null_resource" "deploy_kafka" {
  triggers = {
    cluster_id = module.kubernetes.cluster_id
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/pre-prod-kafka.sh"

    working_dir = path.module

    environment = {
      DOCTL_PATH = "doctl"
      KUBECONFIG = "C:/Users/HP 745 G6/.kube/config"
    }
  }

  depends_on = [
    module.kubernetes,
    helm_release.ingress_nginx
  ]
}
/*
# Verify everything after apply
resource "null_resource" "verify" {
  triggers = {
    cluster_id = module.kubernetes.cluster_id
  }
  provisioner "local-exec" {
    command     = "bash ${path.module}/verify.sh"
    working_dir = path.module
  }
  depends_on = [
    null_resource.deploy_kafka,
    null_resource.update_github_secrets
  ]
}
*/
# Verify everything after apply
# Verify everything after apply
resource "null_resource" "verify" {
  triggers = {
    cluster_id    = module.kubernetes.cluster_id
    postgres_host = module.postgres.database_host
    redis_host    = module.redis.host
    ingress_nginx = var.ingress_nginx_version
    cert_manager  = var.cert_manager_version
  }

  provisioner "local-exec" {
    command     = "bash ${path.module}/pre-prod-verify.sh"
    working_dir = path.module

    environment = {
      KUBECONFIG = "C:\\Users\\HP 745 G6\\.kube\\config"
    }
  }

  depends_on = [
    null_resource.deploy_kafka,
    null_resource.update_preprod_env,
    helm_release.ingress_nginx,
    helm_release.cert_manager
  ]
}

/*
# Setup DB permissions automatically
resource "null_resource" "setup_db" {
  triggers = {
    cluster_id = module.kubernetes.cluster_id
    pg_cluster = module.postgres.cluster_id
  }
  provisioner "local-exec" {
    command     = "bash ${path.module}/setup-db.sh"
    working_dir = path.module
  }
  depends_on = [
    null_resource.deploy_kafka,
    module.postgres
  ]   
}*/
resource "null_resource" "pre-prod-db" {
  triggers = {
    cluster_id = module.kubernetes.cluster_id
    pg_cluster = module.postgres.cluster_id
    script     = filesha256("${path.module}/pre-prod-db.sh")
  }

  provisioner "local-exec" {
    command     = "bash ${path.module}/pre-prod-db.sh"
    working_dir = path.module
  }

  depends_on = [
    null_resource.deploy_kafka,
    module.postgres
  ]
}
/*
# Deploy all services automatically
resource "null_resource" "deploy_services" {
  triggers = {
    cluster_id = module.kubernetes.cluster_id
  }
  provisioner "local-exec" {
    command     = "bash ${path.module}/deploy-services.sh"
    working_dir = path.module
  }
  depends_on = [
    null_resource.setup_db,
    null_resource.update_github_secrets,
    null_resource.verify
  ]
}
*/
/*
resource "null_resource" "pre-prod-deploy-services" {
  triggers = {
    cluster_id = module.kubernetes.cluster_id
  }

  provisioner "local-exec" {
    command     = "bash ${path.module}/pre-prod-deploy-services.sh "
    working_dir = path.module
  }

  depends_on = [
    null_resource.pre-prod-db,
    null_resource.update_preprod_env,
    null_resource.verify
  ]
}*/