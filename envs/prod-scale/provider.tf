provider "digitalocean" {
  token             = var.do_token
  spaces_access_id  = var.spaces_access_id
  spaces_secret_key = var.spaces_secret_key
}

provider "helm" {
  repository_config_path = "${path.module}/.helm/repositories.yaml"
  repository_cache       = "${path.module}/.helm/cache"
  kubernetes {
    host                   = module.kubernetes.host
    token                  = module.kubernetes.kube_token
    cluster_ca_certificate = base64decode(module.kubernetes.cluster_ca_certificate)
  }
}

provider "kubernetes" {
  host                   = module.kubernetes.host
  token                  = module.kubernetes.kube_token
  cluster_ca_certificate = base64decode(module.kubernetes.cluster_ca_certificate)
}
