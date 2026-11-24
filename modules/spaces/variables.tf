variable "region" {
  type        = string
  description = "Spaces region slug (often same as droplet region, e.g. blr1)"
}

variable "app_bucket_name" {
  type        = string
  description = "Globally unique bucket name (lowercase)"
}

variable "logs_bucket_name" {
  type = string
}

variable "versioning_enabled" {
  type        = bool
  description = "Enable object versioning on the app bucket"
  default     = false
}

variable "logs_retention_days" {
  type        = number
  description = "Auto-delete logs objects after N days"
  default     = 30
}

variable "cors_allowed_origins" {
  type        = list(string)
  description = "Origins allowed for CORS on the app bucket"
  default     = ["*"]
}
