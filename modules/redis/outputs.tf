output "cluster_id" {
  value = digitalocean_database_cluster.redis.id
}

output "host" {
  value       = digitalocean_database_cluster.redis.private_host != "" ? digitalocean_database_cluster.redis.private_host : digitalocean_database_cluster.redis.host
  description = "Private host (within VPC) — use as REDIS_HOST env var"
}

output "port" {
  value = digitalocean_database_cluster.redis.port
}

output "password" {
  value     = digitalocean_database_cluster.redis.password
  sensitive = true
}

output "uri" {
  value     = digitalocean_database_cluster.redis.private_uri != "" ? digitalocean_database_cluster.redis.private_uri : digitalocean_database_cluster.redis.uri
  sensitive = true
}
