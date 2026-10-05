variable "oidc_issuer" {
  description = "Pocket ID issuer URL."
  type        = string
}

variable "oidc_client_id" {
  description = "Pocket ID client for the NAS host."
  type        = string
}

variable "oidc_client_secret" {
  description = "Secret of the Pocket ID client."
  type        = string
  sensitive   = true
}
