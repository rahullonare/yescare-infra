# DO Cloud Firewall — stateful, tag-based
# Applied to any Droplet/resource that carries one of var.apply_to_tags.
# For DOKS nodes the cluster's built-in firewall is the primary control;
# this resource adds an extra perimeter layer for public-facing ingress.

resource "digitalocean_firewall" "main" {
  name = var.name
  tags = var.apply_to_tags

  dynamic "inbound_rule" {
    for_each = var.inbound_rules
    content {
      protocol         = inbound_rule.value.protocol
      port_range       = inbound_rule.value.port_range
      source_addresses = lookup(inbound_rule.value, "source_addresses", [])
      source_tags      = lookup(inbound_rule.value, "source_tags", [])
    }
  }

  dynamic "outbound_rule" {
    for_each = var.outbound_rules
    content {
      protocol              = outbound_rule.value.protocol
      port_range            = outbound_rule.value.protocol != "icmp" ? coalesce(outbound_rule.value.port_range, "1-65535") : null
      destination_addresses = coalesce(outbound_rule.value.destination_addresses, ["0.0.0.0/0", "::/0"])
    }
  }
}
