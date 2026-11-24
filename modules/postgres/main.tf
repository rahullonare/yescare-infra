/*resource "digitalocean_database_cluster" "postgres" {
  name                   = var.name
  engine                 = "pg"
  version                = var.pg_version
  size                   = var.size
  region                 = var.region
  node_count           = var.node_count
  private_network_uuid = var.vpc_uuid
  tags                 = var.tags
}

resource "digitalocean_database_db" "app" {
  cluster_id = digitalocean_database_cluster.postgres.id
  name       = var.database_name
}
}

resource "digitalocean_database_user" "app" {
  cluster_id = digitalocean_database_cluster.postgres.id
  name       = var.username
}

resource "digitalocean_database_firewall" "postgres" {
  cluster_id = digitalocean_database_cluster.postgres.id

  rule {
    type  = "k8s"
    value = var.kubernetes_cluster_id
  }
}

# Per-service databases
resource "digitalocean_database_db" "hospital" {
  cluster_id = digitalocean_database_cluster.postgres.id
  name       = "hospital_db"
}
resource "digitalocean_database_db" "payment" {
  cluster_id = digitalocean_database_cluster.postgres.id
  name       = "payment_db"
}
resource "digitalocean_database_db" "notification" {
  cluster_id = digitalocean_database_cluster.postgres.id
  name       = "notification_service_db"
}

# Per-service users
resource "digitalocean_database_user" "hospital" {
  cluster_id = digitalocean_database_cluster.postgres.id
  name       = "hospital_user"
}
resource "digitalocean_database_user" "payment" {
  cluster_id = digitalocean_database_cluster.postgres.id
  name       = "payment_user"
}
resource "digitalocean_database_user" "notification" {
  cluster_id = digitalocean_database_cluster.postgres.id
  name       = "notification_user"
}

# Auth service database
resource "digitalocean_database_db" "auth" {
  cluster_id = digitalocean_database_cluster.postgres.id
  name       = "auth_db"
}
*/
# ============================================================
# PRE-PROD PostgreSQL Cluster
# ============================================================

resource "digitalocean_database_cluster" "postgres" {
  name                 = var.name
  engine               = "pg"
  version              = var.pg_version
  size                 = var.size
  region               = var.region
  node_count           = var.node_count
  private_network_uuid = var.vpc_uuid
  tags                 = var.tags
}

# ============================================================
# Application Databases
#
# Creates one database for each service defined in var.services
# ============================================================

resource "digitalocean_database_db" "service" {
  for_each = var.services

  cluster_id = digitalocean_database_cluster.postgres.id
  name       = each.value.database
}

# ============================================================
# Application Database Users
#
# Creates one user for each service defined in var.services
# ============================================================

resource "digitalocean_database_user" "service" {
  for_each = var.services

  cluster_id = digitalocean_database_cluster.postgres.id
  name       = each.value.username
}

# ============================================================
# PostgreSQL Firewall
#
# Allow access from the PRE-PROD DOKS cluster only
# ============================================================

resource "digitalocean_database_firewall" "postgres" {
  cluster_id = digitalocean_database_cluster.postgres.id

  rule {
    type  = "k8s"
    value = var.kubernetes_cluster_id
  }
}