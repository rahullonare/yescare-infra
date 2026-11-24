############################
# DigitalOcean Dev Environment
#
# - VPC + DOKS + Managed PostgreSQL
# - Spaces (S3-compatible) — app uses endpoint + keys
# - DO Container Registry (shared between dev/prod)
# - DO Cloud Firewall
# - ingress-nginx via Helm (creates DO Load Balancer)
# - In-cluster Redis, RabbitMQ via scripts/do-dev-stack-install.sh
############################

module "vpc" {
  source   = "../../modules/vpc"
  name     = "yescare-${var.env}"
  region   = var.region
  ip_range = var.vpc_ip_range
}

module "kubernetes" {
  source = "../../modules/kubernetes"

  cluster_name = "yescare-${var.env}-k8s"
  region       = var.region
  vpc_uuid     = module.vpc.id
  k8s_version  = var.k8s_version

  node_size    = var.k8s_node_size
  node_count   = var.k8s_node_count
  auto_scale   = false
  cluster_tags = ["yescare", var.env, "terraform"]
  tags         = ["yescare", var.env, "worker"]
}

module "postgres" {
  source = "../../modules/postgres"

  name                  = "yescare-${var.env}-pg"
  region                = var.region
  vpc_uuid              = module.vpc.id
  kubernetes_cluster_id = module.kubernetes.cluster_id

  size          = var.db_size
  database_name = var.db_name
  username      = var.db_username
  pg_version    = var.db_pg_version
  node_count    = var.db_node_count

  tags = ["yescare", var.env, "terraform"]
}

module "spaces" {
  count  = var.enable_spaces ? 1 : 0
  source = "../../modules/spaces"

  region = var.region

  app_bucket_name     = var.spaces_app_bucket_name
  logs_bucket_name    = var.spaces_logs_bucket_name
  versioning_enabled  = false
  logs_retention_days = 30
}

# Container Registry — shared across envs; created once (basic tier)
module "registry" {
  count  = var.create_registry ? 1 : 0
  source = "../../modules/registry"

  name   = var.registry_name
  region = var.region
  tier   = "basic"
}

# Cloud Firewall — must run after DOKS cluster so the node tags exist
module "firewall" {
  source = "../../modules/firewall"

  name          = "yescare-${var.env}-fw"
  apply_to_tags = ["yescare", var.env, "worker"]

  inbound_rules = [
    {
      protocol         = "tcp"
      port_range       = "80"
      source_addresses = ["0.0.0.0/0", "::/0"]
    },
    {
      protocol         = "tcp"
      port_range       = "443"
      source_addresses = ["0.0.0.0/0", "::/0"]
    },
  ]

  depends_on = [module.kubernetes]
}

# ingress-nginx — creates a DO Load Balancer automatically
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.ingress_nginx_version
  namespace        = "ingress-nginx"
  create_namespace = true
  wait             = true
  timeout          = 600

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.service.annotations.kubernetes\\.digitalocean\\.com/load-balancer-id"
    value = ""
  }

  depends_on = [module.kubernetes]
}
