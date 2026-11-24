resource "digitalocean_database_cluster" "redis" {
  name                 = var.name
  engine               = "valkey"
  version              = var.redis_version
  size                 = var.size
  region               = var.region
  node_count           = 1
  private_network_uuid = var.vpc_uuid
  tags                 = var.tags

}

resource "digitalocean_database_firewall" "redis" {
  cluster_id = digitalocean_database_cluster.redis.id

  rule {
    type  = "k8s"
    value = var.kubernetes_cluster_id
  }
}
