resource "digitalocean_kubernetes_cluster" "main" {
  name         = var.cluster_name
  region       = var.region
  version      = var.k8s_version
  vpc_uuid     = var.vpc_uuid
  auto_upgrade = var.auto_upgrade

  maintenance_policy {
    day        = var.maintenance_day
    start_time = var.maintenance_start_time
  }

  node_pool {
    name   = var.node_pool_name
    size   = var.node_size
    tags   = var.tags
    labels = var.labels

    # auto_scale and node_count are mutually exclusive on DOKS
    auto_scale = var.auto_scale
    node_count = var.auto_scale ? null : var.node_count
    min_nodes  = var.auto_scale ? var.min_nodes : null
    max_nodes  = var.auto_scale ? var.max_nodes : null
  }

  tags = var.cluster_tags
}
