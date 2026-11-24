output "cluster_id" {
  value = digitalocean_database_cluster.postgres.id
}

output "database_host" {
  value = digitalocean_database_cluster.postgres.host
}

output "database_port" {
  value = digitalocean_database_cluster.postgres.port
}

output "database_names" {
  value = {
    for service, db in digitalocean_database_db.service :
    service => db.name
  }
}

output "database_users" {
  value = {
    for service, user in digitalocean_database_user.service :
    service => user.name
  }
}

output "database_passwords" {
  value = {
    for service, user in digitalocean_database_user.service :
    service => user.password
  }

  sensitive = true
}

# ------------------------------------------------------------
# Backward-compatible outputs used by root module
# ------------------------------------------------------------

output "database_name" {
  value = digitalocean_database_db.service["auth"].name
}

output "database_user" {
  value = digitalocean_database_user.service["auth"].name
}

output "database_password" {
  value     = digitalocean_database_user.service["auth"].password
  sensitive = true
}

output "hospital_user_password" {
  value     = digitalocean_database_user.service["hospital"].password
  sensitive = true
}

output "payment_user_password" {
  value     = digitalocean_database_user.service["payment"].password
  sensitive = true
}

output "notification_user_password" {
  value     = digitalocean_database_user.service["notification"].password
  sensitive = true
}