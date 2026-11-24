output "app_bucket_name" {
  value = digitalocean_spaces_bucket.app.name
}

output "logs_bucket_name" {
  value = digitalocean_spaces_bucket.logs.name
}

output "app_bucket_urn" {
  value = digitalocean_spaces_bucket.app.urn
}

output "logs_bucket_urn" {
  value = digitalocean_spaces_bucket.logs.urn
}
