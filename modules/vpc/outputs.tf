output "id" {
  value       = digitalocean_vpc.main.id
  description = "VPC UUID for digitalocean_kubernetes_cluster.vpc_uuid and database private_network_uuid"
}

output "name" {
  value = digitalocean_vpc.main.name
}
