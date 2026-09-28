variable "proxmox_host" {
  description = "Proxmox address on the tailnet, from secrets/env.sops.yaml through run.sh."
  type        = string
}

variable "state_passphrase" {
  description = "State encryption passphrase, from SOPS through run.sh."
  type        = string
  sensitive   = true
}

variable "domain" {
  description = "Lab domain, from secrets/env.sops.yaml through run.sh."
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone of the lab domain, from secrets/env.sops.yaml through run.sh."
  type        = string
}

variable "services_tailnet_ip" {
  description = "Services stack address on the tailnet, from secrets/env.sops.yaml through run.sh."
  type        = string
}

variable "cloudflare_pve_acme_token" {
  description = "Cloudflare token Proxmox uses to renew its certificate, from SOPS through run.sh."
  type        = string
  sensitive   = true
}
