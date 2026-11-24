variable "do_token" {
  type        = string
  sensitive   = true
  description = "DigitalOcean API token"
}

variable "kubeconfig_path" {
  type        = string
  description = "Path to kubeconfig for Helm/K8s provider. Leave empty during phase-1 apply."
  default     = ""
}

variable "spaces_access_id" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Spaces access key; required when enable_spaces is true"
}

variable "spaces_secret_key" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Spaces secret; required when enable_spaces is true"
}

variable "region" {
  type    = string
  default = "blr1"
}

variable "env" {
  type    = string
  default = "prod"
}

variable "vpc_ip_range" {
  type    = string
  default = "10.22.0.0/16"
}

variable "k8s_version" {
  type        = string
  description = "Run: doctl kubernetes options versions --region YOUR_REGION"
}

variable "k8s_node_size" {
  type    = string
  default = "s-2vcpu-4gb"
}

variable "k8s_node_count" {
  type    = number
  default = 2
}

variable "db_username" {
  type    = string
  default = "yescare_app"
}

variable "db_size" {
  type    = string
  default = "db-s-2vcpu-4gb"
}

variable "db_name" {
  type    = string
  default = "yescareprod"
}

variable "enable_spaces" {
  type    = bool
  default = true
}

variable "spaces_bucket_suffix" {
  type        = string
  description = "Globally unique suffix for Spaces bucket names"
}

variable "k8s_min_nodes" {
  type    = number
  default = 2
}

variable "k8s_max_nodes" {
  type    = number
  default = 5
}

variable "db_node_count" {
  type        = number
  description = "1 = single node, 2 = primary + standby (HA)"
  default     = 1
}

variable "redis_size" {
  type    = string
  default = "db-s-1vcpu-1gb"
}

variable "create_registry" {
  type        = bool
  description = "Set to false after registry is already provisioned"
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

variable "rabbitmq_chart_version" {
  type    = string
  default = "14.4.4"
}

variable "rabbitmq_username" {
  type    = string
  default = "yescare"
}

variable "rabbitmq_password" {
  type      = string
  sensitive = true
}

variable "domain_name" {
  type        = string
  description = "Root domain (e.g. yescare.in) — leave empty to skip DNS setup"
  default     = ""
}

variable "load_balancer_ip" {
  type        = string
  description = "DO LB IP from: kubectl get svc ingress-nginx-controller -n ingress-nginx — set after first apply"
  default     = ""
}
