variable "domain_name" {
  type        = string
  description = "Root domain (e.g. yescare.in)"
}

variable "additional_domains" {
  type        = list(string)
  description = "Extra SANs on the certificate (e.g. www.yescare.in, api.yescare.in)"
  default     = []
}

variable "load_balancer_ip" {
  type        = string
  description = "Public IP of the DO Load Balancer (from ingress-nginx kubectl get svc)"
}

variable "ttl" {
  type    = number
  default = 300
}

variable "add_www" {
  type    = bool
  default = true
}

variable "add_api" {
  type    = bool
  default = true
}
