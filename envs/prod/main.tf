############################
# DigitalOcean Production Environment
#
# Stack: VPC + DOKS (autoscale) + Managed Postgres + Managed Redis
#        + Spaces + Container Registry + Firewall + ingress-nginx
#        + DO DNS + Let's Encrypt Certificate + RabbitMQ (Helm)
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
  auto_upgrade = true

  node_size  = var.k8s_node_size
  auto_scale = true
  min_nodes  = var.k8s_min_nodes
  max_nodes  = var.k8s_max_nodes

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
  node_count    = var.db_node_count

  tags = ["yescare", var.env, "terraform"]
}

module "redis" {
  source = "../../modules/redis"

  name                  = "yescare-${var.env}-redis"
  region                = var.region
  vpc_uuid              = module.vpc.id
  kubernetes_cluster_id = module.kubernetes.cluster_id

  size            = var.redis_size
  eviction_policy = "allkeys-lru"
  tags            = ["yescare", var.env, "terraform"]
}

module "spaces" {
  count  = var.enable_spaces ? 1 : 0
  source = "../../modules/spaces"

  region = var.region

  app_bucket_name     = "yescare-app-${var.env}-${var.spaces_bucket_suffix}"
  logs_bucket_name    = "yescare-logs-${var.env}-${var.spaces_bucket_suffix}"
  versioning_enabled  = true
  logs_retention_days = 90
  cors_allowed_origins = ["https://${var.domain_name}", "https://www.${var.domain_name}"]
}

module "registry" {
  count  = var.create_registry ? 1 : 0
  source = "../../modules/registry"

  name   = var.registry_name
  region = var.region
  tier   = "basic"
}

# Cloud Firewall — public HTTP/HTTPS to DOKS worker nodes
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
}

# ingress-nginx — creates DO Load Balancer, exposes apps on 80/443
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
    name  = "controller.replicaCount"
    value = "2"
  }

  depends_on = [module.kubernetes]
}

# RabbitMQ — replaces AWS SQS (events, notifications, jobs queues)
resource "helm_release" "rabbitmq" {
  name             = "rabbitmq"
  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "rabbitmq"
  version          = var.rabbitmq_chart_version
  namespace        = "messaging"
  create_namespace = true
  wait             = true
  timeout          = 600

  set {
    name  = "auth.username"
    value = var.rabbitmq_username
  }

  set_sensitive {
    name  = "auth.password"
    value = var.rabbitmq_password
  }

  set {
    name  = "persistence.enabled"
    value = "true"
  }

  set {
    name  = "persistence.size"
    value = "5Gi"
  }

  set {
    name  = "replicaCount"
    value = "1"
  }

  depends_on = [module.kubernetes]
}

# DO DNS domain + Let's Encrypt certificate
# NOTE: apply domain AFTER getting the LB IP from ingress-nginx
# set load_balancer_ip var in terraform.tfvars after first apply
module "domain" {
  count  = var.domain_name != "" && var.load_balancer_ip != "" ? 1 : 0
  source = "../../modules/domain"

  domain_name    = var.domain_name
  load_balancer_ip = var.load_balancer_ip
  add_www        = true
  add_api        = true
  additional_domains = ["www.${var.domain_name}", "api.${var.domain_name}"]
}
