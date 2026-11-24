variable "name" {
  type        = string
  description = "Database cluster name"
}

variable "region" {
  type = string
}

variable "vpc_uuid" {
  type = string
}

variable "kubernetes_cluster_id" {
  type        = string
  description = "DOKS cluster UUID — firewall allows inbound from this cluster only"
}

variable "redis_version" {
  type    = string
  default = "8"
}

variable "size" {
  type        = string
  description = "Size slug: db-s-1vcpu-1gb ($15/mo) | db-s-1vcpu-2gb ($30/mo)"
  default     = "db-s-1vcpu-1gb"
}

variable "eviction_policy" {
  type        = string
  description = "allkeys-lru | volatile-lru | noeviction | allkeys-random"
  default     = "allkeys-lru"
}

variable "tags" {
  type    = list(string)
  default = []
}
