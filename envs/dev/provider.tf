provider "digitalocean" {
  token             = var.do_token
  spaces_access_id  = var.spaces_access_id
  spaces_secret_key = var.spaces_secret_key
}

# Helm + Kubernetes providers use a kubeconfig file path.
# Phase 1 apply (cluster creation): leave kubeconfig_path="" — Helm resources are skipped via -target.
# Phase 2 apply (Helm charts):
#   terraform output -raw kubeconfig > kubeconfig-dev.yaml
#   terraform apply -var="kubeconfig_path=kubeconfig-dev.yaml" -var-file=terraform.tfvars
provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path != "" ? var.kubeconfig_path : null
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path != "" ? var.kubeconfig_path : null
}
