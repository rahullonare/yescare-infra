variable "name" {
  type        = string
  description = "Firewall name"
}

variable "apply_to_tags" {
  type        = list(string)
  description = "Tags identifying the resources this firewall protects"
  default     = []
}

variable "inbound_rules" {
  type = list(object({
    protocol         = string
    port_range       = string
    source_addresses = optional(list(string), [])
    source_tags      = optional(list(string), [])
  }))
  description = "List of inbound firewall rules"
  default     = []
}

variable "outbound_rules" {
  type = list(object({
    protocol              = string
    port_range            = optional(string)   # omit for icmp
    destination_addresses = optional(list(string), ["0.0.0.0/0", "::/0"])
  }))
  description = "List of outbound firewall rules. Use '1-65535' for all TCP/UDP ports. Omit port_range for icmp."
  default = [
    { protocol = "tcp", port_range = "1-65535", destination_addresses = ["0.0.0.0/0", "::/0"] },
    { protocol = "udp", port_range = "1-65535", destination_addresses = ["0.0.0.0/0", "::/0"] },
    { protocol = "icmp",                        destination_addresses = ["0.0.0.0/0", "::/0"] },
  ]
}
