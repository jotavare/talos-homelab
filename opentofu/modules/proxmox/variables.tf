variable "cloudflare_zone_id" {
  description = "Cloudflare zone for the ACME DNS plugin."
  type        = string
}

variable "cloudflare_acme_token" {
  description = "Cloudflare token for the ACME DNS plugin."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "acme_domains" {
  description = "Names on the Proxmox certificate."
  type        = list(string)
}
