output "domain_urn" {
  value = digitalocean_domain.main.urn
}

output "certificate_id" {
  value       = digitalocean_certificate.main.uuid
  description = "Pass to digitalocean_loadbalancer.certificate_id for TLS termination at LB"
}

output "certificate_name" {
  value = digitalocean_certificate.main.name
}

output "apex_record_fqdn" {
  value = digitalocean_record.apex.fqdn
}
