# DO Container Registry — replaces AWS ECR
# tier: starter (free, 1 repo, 500MB) | basic ($5/mo, 5 repos, 5GB) | professional ($20/mo, unlimited)

resource "digitalocean_container_registry" "main" {
  name                   = var.name
  subscription_tier_slug = var.tier
  region                 = var.region
}

# Docker credentials for CI/CD push (write) and K8s pull (read)
resource "digitalocean_container_registry_docker_credentials" "ci" {
  registry_name = digitalocean_container_registry.main.name
  write         = true
  expiry_seconds = var.ci_credential_ttl
}

resource "digitalocean_container_registry_docker_credentials" "k8s" {
  registry_name = digitalocean_container_registry.main.name
  write         = false
}
