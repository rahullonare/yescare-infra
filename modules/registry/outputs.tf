output "server_url" {
  value       = digitalocean_container_registry.main.server_url
  description = "registry.digitalocean.com/<name> — use as image prefix in K8s manifests"
}

output "registry_name" {
  value = digitalocean_container_registry.main.name
}

output "endpoint" {
  value = "registry.digitalocean.com/${digitalocean_container_registry.main.name}"
}

output "ci_docker_credentials" {
  value       = digitalocean_container_registry_docker_credentials.ci.docker_credentials
  sensitive   = true
  description = "JSON for CI: echo $VALUE | base64 -d > ~/.docker/config.json"
}

output "k8s_docker_credentials" {
  value       = digitalocean_container_registry_docker_credentials.k8s.docker_credentials
  sensitive   = true
  description = "JSON to create K8s imagePullSecret: kubectl create secret docker-registry"
}
