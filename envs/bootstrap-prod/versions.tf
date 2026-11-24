terraform {
  required_version = ">= 1.5.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.34"
    }
  }

  # Bootstrap intentionally uses LOCAL state. It runs ONCE per AWS account
  # equivalent (DO account) to create the project + state bucket the rest of
  # the envs use. Commit the resulting terraform.tfstate to a *private* repo
  # or back it up to 1Password — do NOT commit publicly.
}
