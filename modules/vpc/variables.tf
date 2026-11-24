variable "name" {
  type        = string
  description = "VPC name"
}

variable "region" {
  type        = string
  description = "DigitalOcean region slug (e.g. blr1)"
}

variable "ip_range" {
  type        = string
  description = "Private RFC1918 range for the VPC"
  default     = "10.20.0.0/16"
}
