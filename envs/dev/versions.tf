terraform {
  required_version = ">= 1.5.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.34"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }

  # Terraform state in DO Spaces (S3-compatible backend)
  # Init:  terraform init \
  #          -backend-config="access_key=$SPACES_ACCESS_KEY" \
  #          -backend-config="secret_key=$SPACES_SECRET_KEY"
  backend "s3" {
    endpoints = {
      s3 = "https://sgp1.digitaloceanspaces.com"
    }
    bucket = "yescare-tf-state"
    key    = "envs/dev/terraform.tfstate"
    region = "us-east-1" # dummy — required field, ignored by Spaces

    skip_credentials_validation  = true
    skip_metadata_api_check      = true
    skip_region_validation       = true
    skip_requesting_account_id   = true
    use_path_style               = true
  }
}
