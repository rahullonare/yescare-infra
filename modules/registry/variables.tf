variable "name" {
  type        = string
  description = "Registry name — must be globally unique on DO (e.g. yescare)"
}

variable "region" {
  type        = string
  description = "Registry region slug (blr1 recommended for Mumbai-region workloads)"
}

variable "tier" {
  type        = string
  description = "starter | basic | professional"
  default     = "basic"
}

variable "ci_credential_ttl" {
  type        = number
  description = "CI push credential TTL in seconds (0 = never expires)"
  default     = 0
}
