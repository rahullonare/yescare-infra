variable "name" {
  type        = string
  description = "Managed cluster name"
}

variable "services" {
  type = any
}

variable "region" {
  type = string
}

variable "vpc_uuid" {
  type = string
}

variable "kubernetes_cluster_id" {
  type        = string
  description = "DOKS cluster UUID for firewall k8s rule"
}

variable "pg_version" {
  type    = string
  default = "16"
}

variable "size" {
  type        = string
  description = "Size slug e.g. db-s-1vcpu-1gb"
}

variable "node_count" {
  type    = number
  default = 1
}

variable "tags" {
  type    = list(string)
  default = []
}