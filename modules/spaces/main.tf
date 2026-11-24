resource "digitalocean_spaces_bucket" "app" {
  force_destroy = true
  name   = var.app_bucket_name
  region = var.region
  acl    = "private"

  versioning {
    enabled = var.versioning_enabled
  }
}

resource "digitalocean_spaces_bucket_cors_configuration" "app" {
  bucket = digitalocean_spaces_bucket.app.id
  region = var.region

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = var.cors_allowed_origins
    max_age_seconds = 3000
  }
}

resource "digitalocean_spaces_bucket" "logs" {
  force_destroy = true
  name   = var.logs_bucket_name
  region = var.region
  acl    = "private"

  lifecycle_rule {
    id      = "expire-old-logs"
    enabled = true

    expiration {
      days = var.logs_retention_days
    }
  }
}
