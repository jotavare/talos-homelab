variable "settings" {
  description = "Non-secret values Flux substitutes into the manifests."
  type        = map(string)
}

variable "cloudflare_token" {
  description = "Cloudflare DNS token for cert-manager DNS-01."
  type        = string
  sensitive   = true
}

variable "immich_oauth" {
  description = "Pocket ID client for Immich."
  type        = object({ client_id = string, client_secret = string })
  sensitive   = true
}
