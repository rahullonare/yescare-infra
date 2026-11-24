variable "do_token" {
  type        = string
  sensitive   = true
  description = "DigitalOcean API token"
}

variable "kubeconfig_path" {
  type        = string
  description = "Path to kubeconfig for Helm/K8s provider. Leave empty during phase-1 apply. Set after cluster is created."
  default     = ""
}

variable "spaces_access_id" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Spaces access key — required when enable_spaces is true"
}

variable "spaces_secret_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Spaces secret — required when enable_spaces is true"
}

variable "region" {
  type        = string
  description = "DigitalOcean region slug (blr1, nyc3, sgp1, …)"
  default     = "blr1"
}

variable "env" {
  type    = string
  default = "dev"
}

variable "vpc_ip_range" {
  type    = string
  default = "10.1.0.0/16"
}

variable "k8s_version" {
  type        = string
  description = "Run: doctl kubernetes options versions --region YOUR_REGION"
}

variable "k8s_node_size" {
  type        = string
  description = "DOKS worker size — use s-4vcpu-8gb if running Kafka+RabbitMQ+ingress on one node"
  default     = "s-4vcpu-8gb"
}

variable "k8s_node_count" {
  type    = number
  default = 1
}

variable "db_username" {
  type    = string
  default = "yescare_admin"
}

variable "db_name" {
  type    = string
  default = "yescaredev"
}

variable "db_size" {
  type    = string
  default = "db-s-1vcpu-1gb"
}

variable "db_pg_version" {
  type    = string
  default = "16"
}

variable "db_node_count" {
  type    = number
  default = 1
}

variable "enable_spaces" {
  type        = bool
  description = "Create Spaces buckets (S3-compatible storage for the app)"
  default     = true
}

variable "spaces_app_bucket_name" {
  type        = string
  description = "Globally unique bucket name on Spaces"
  default     = "yescare-app-bucket-dev"
}

variable "spaces_logs_bucket_name" {
  type    = string
  default = "dev-yescare-logs-bucket"
}

variable "github_repo_url" {
  type    = string
  default = "https://github.com/yescaretechdev-glitch/yescare-backend"
}

variable "runner_secret_name" {
  type    = string
  default = "yescare/dev/github-runner"
}

variable "rds_secret_name" {
  type    = string
  default = "yescare/dev/db"
}

variable "create_registry" {
  type        = bool
  description = "Set to false after first apply if registry already exists"
  default     = true
}

variable "registry_name" {
  type        = string
  description = "Globally unique DO registry name (e.g. yescare)"
  default     = "yescare"
}

variable "ingress_nginx_version" {
  type    = string
  default = "4.10.1"
}
