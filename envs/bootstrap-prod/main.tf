############################
# YesCare Prod Bootstrap (DigitalOcean)
#
# Run ONCE before any other prod env. Creates:
#   - DO Project "YesCare Production"
#   - Spaces bucket for prod Terraform state
#   - Attaches the state bucket to the project (per user requirement)
#
# After this apply, copy the outputs into:
#   digitalocean/envs/prod-scale/terraform.tfvars
#     project_id           = "<output: project_id>"
#     state_bucket_name    = "<output: state_bucket_name>"   # already wired in versions.tf
#
# This env uses LOCAL state — keep terraform.tfstate safe and out of public git.
############################

############################
# DO Project — isolation boundary for billing + access control + safety
############################
resource "digitalocean_project" "prod" {
  name        = var.project_name
  description = var.project_description
  purpose     = var.project_purpose
  environment = var.project_environment
}

############################
# Spaces bucket — Terraform remote state for prod-scale env
# Versioning ON so we never lose state on a bad apply.
############################
resource "digitalocean_spaces_bucket" "tf_state" {
  name   = var.state_bucket_name
  region = var.spaces_region
  acl    = "private"

  versioning {
    enabled = true
  }

  # Expire old versions after 90 days — keeps bucket size in check.
  lifecycle_rule {
    id      = "expire-old-tfstate-versions"
    enabled = true

    noncurrent_version_expiration {
      days = 90
    }
  }
}

############################
# Attach the state bucket to the prod project.
# This is the "even terraform state saved in the same project" requirement.
# DOKS / Postgres / Redis / Spaces created by prod-scale env attach themselves
# via the digitalocean_project_resources block in that env's main.tf.
############################
resource "digitalocean_project_resources" "tf_state_bucket" {
  project   = digitalocean_project.prod.id
  resources = [digitalocean_spaces_bucket.tf_state.urn]
}

############################
# Outputs — paste these into prod-scale/terraform.tfvars
############################
output "project_id" {
  value       = digitalocean_project.prod.id
  description = "Set this as project_id in prod-scale/terraform.tfvars"
}

output "project_name" {
  value = digitalocean_project.prod.name
}

output "state_bucket_name" {
  value = digitalocean_spaces_bucket.tf_state.name
}

output "state_bucket_region" {
  value = digitalocean_spaces_bucket.tf_state.region
}

output "state_backend_endpoint" {
  value = "https://${var.spaces_region}.digitaloceanspaces.com"
}

output "next_steps" {
  value = <<-EOT

  Bootstrap done. Now:

  1. cd ../prod-scale
  2. cp terraform.tfvars.example terraform.tfvars
  3. Edit terraform.tfvars and set:
        project_id           = "${digitalocean_project.prod.id}"
        spaces_bucket_suffix = "<your random 6-char suffix>"
        k8s_version          = "$(doctl kubernetes options versions --region sgp1 | head -2 | tail -1 | awk '{print $1}')"
        letsencrypt_email    = "<ops email>"
        domain_name          = "<your domain or leave blank>"

  4. export TF_VAR_do_token="$TF_VAR_do_token"
     export TF_VAR_spaces_access_id="$TF_VAR_spaces_access_id"
     export TF_VAR_spaces_secret_key="$TF_VAR_spaces_secret_key"

  5. terraform init \\
        -backend-config="access_key=$TF_VAR_spaces_access_id" \\
        -backend-config="secret_key=$TF_VAR_spaces_secret_key"

  6. Follow the Phase-1 apply procedure in prod-scale/README.md §4.

  EOT
}
