variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_uuid" {
  type        = string
  description = "digitalocean_vpc id"
}

variable "k8s_version" {
  type    = string
  default = "1.31.2-do.0"
}

variable "auto_upgrade" {
  type    = bool
  default = false
}

variable "maintenance_day" {
  type        = string
  description = "e.g. sunday"
  default     = "sunday"
}

variable "maintenance_start_time" {
  type    = string
  default = "04:00"
}

variable "node_pool_name" {
  type    = string
  default = "default"
}

variable "node_size" {
  type        = string
  description = "Droplet slug for worker nodes (e.g. s-1vcpu-2gb)"
}

variable "node_count" {
  type        = number
  description = "Fixed node count — ignored when auto_scale = true"
  default     = 1
}

variable "auto_scale" {
  type        = bool
  description = "Enable DOKS cluster autoscaler"
  default     = false
}

variable "min_nodes" {
  type        = number
  description = "Minimum nodes when auto_scale = true"
  default     = 1
}

variable "max_nodes" {
  type        = number
  description = "Maximum nodes when auto_scale = true"
  default     = 3
}

variable "tags" {
  type    = list(string)
  default = []
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "cluster_tags" {
  type    = list(string)
  default = []
}
