output "cluster_id" {
  value       = digitalocean_kubernetes_cluster.main.id
  description = "Cluster UUID (for database firewall k8s rule)"
}

output "endpoint" {
  value = digitalocean_kubernetes_cluster.main.endpoint
}

output "kubeconfig_raw" {
  value       = digitalocean_kubernetes_cluster.main.kube_config[0].raw_config
  sensitive   = true
  description = "Full kubeconfig YAML for kubectl"
}

output "kube_token" {
  value       = digitalocean_kubernetes_cluster.main.kube_config[0].token
  sensitive   = true
  description = "Bearer token — used by Helm/K8s Terraform providers"
}

output "cluster_ca_certificate" {
  value       = digitalocean_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate
  sensitive   = true
  description = "Base64-encoded CA cert — used by Helm/K8s Terraform providers"
}

output "host" {
  value       = digitalocean_kubernetes_cluster.main.kube_config[0].host
  description = "API server URL — used by Helm/K8s Terraform providers"
}
