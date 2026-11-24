variable "do_token" {
  type        = string
  sensitive   = true
  description = "DigitalOcean API token (prod-only — never reuse dev token)"
}

variable "spaces_access_id" {
  type        = string
  sensitive   = true
  description = "Spaces access key — created under API > Spaces Keys in the DO control panel"
}

variable "spaces_secret_key" {
  type        = string
  sensitive   = true
  description = "Spaces secret key — paired with spaces_access_id"
}

variable "project_name" {
  type        = string
  default     = "YesCare Production"
  description = "DO Project name. Resources from prod-scale env will be attached here."
}

variable "project_description" {
  type    = string
  default = "YesCare production infrastructure — DOKS, managed Postgres/Redis, Kafka, Spaces. Isolated from dev."
}

variable "project_purpose" {
  type    = string
  default = "Web Application"
}

variable "project_environment" {
  type        = string
  default     = "Production"
  description = "DO Project environment label. Allowed: Development | Staging | Production"
}

variable "spaces_region" {
  type        = string
  default     = "sgp1"
  description = "Region for the state bucket. sgp1 = Singapore (closest Spaces region for India workloads)."
}

variable "state_bucket_name" {
  type        = string
  default     = "yescare-tfstate-prod"
  description = "Globally unique Spaces bucket name for prod Terraform state. Will hold envs/prod-scale/terraform.tfstate."
}
