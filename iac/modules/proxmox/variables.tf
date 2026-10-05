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

variable "oidc_issuer" {
  description = "Pocket ID issuer URL."
  type        = string
}

variable "oidc_client_id" {
  description = "Pocket ID client for Proxmox."
  type        = string
}

variable "oidc_client_secret" {
  description = "Secret of the Pocket ID client."
  type        = string
  sensitive   = true
}
