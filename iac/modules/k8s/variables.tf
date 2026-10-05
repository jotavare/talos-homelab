variable "settings" {
  description = "Non-secret values Flux substitutes into the manifests."
  type        = map(string)
}

variable "cloudflare_token" {
  description = "Cloudflare DNS token for cert-manager DNS-01."
  type        = string
  sensitive   = true
}
