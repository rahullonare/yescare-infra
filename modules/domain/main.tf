# DO DNS zone + Let's Encrypt certificate + A records
# Replaces: AWS ACM + Route53

resource "digitalocean_domain" "main" {
  name = var.domain_name
}

# Let's Encrypt certificate managed by DO — auto-renews
resource "digitalocean_certificate" "main" {
  name    = "${replace(var.domain_name, ".", "-")}-cert"
  type    = "lets_encrypt"
  domains = concat([var.domain_name], var.additional_domains)

  lifecycle {
    create_before_destroy = true
  }
}

# Apex A record → Load Balancer IP
resource "digitalocean_record" "apex" {
  domain = digitalocean_domain.main.name
  type   = "A"
  name   = "@"
  value  = var.load_balancer_ip
  ttl    = var.ttl
}

# www subdomain
resource "digitalocean_record" "www" {
  count  = var.add_www ? 1 : 0
  domain = digitalocean_domain.main.name
  type   = "A"
  name   = "www"
  value  = var.load_balancer_ip
  ttl    = var.ttl
}

# api subdomain (optional)
resource "digitalocean_record" "api" {
  count  = var.add_api ? 1 : 0
  domain = digitalocean_domain.main.name
  type   = "A"
  name   = "api"
  value  = var.load_balancer_ip
  ttl    = var.ttl
}
