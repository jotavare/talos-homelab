variable "state_passphrase" {
  description = "State encryption passphrase, kept in Bitwarden."
  type        = string
  sensitive   = true
}

variable "proxmox_host" {
  description = "Tailnet address of pve, the SSH jump host to the services VM."
  type        = string
}

variable "domain" {
  description = "Lab domain."
  type        = string
}

variable "acme_email" {
  description = "Let's Encrypt contact for Caddy."
  type        = string
}
