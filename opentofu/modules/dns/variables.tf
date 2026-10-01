variable "domain" {
  description = "Lab domain."
  type        = string
}

variable "zone_id" {
  description = "Cloudflare zone of the domain."
  type        = string
}

variable "services_ip" {
  description = "Tailnet address of the services VM."
  type        = string
}

variable "proxmox_ip" {
  description = "Tailnet address of pve."
  type        = string
}
