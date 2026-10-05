variable "domain" {
  description = "Lab domain."
  type        = string
}

variable "oidc_client_id" {
  description = "Pocket ID client for OpenBao."
  type        = string
}

variable "oidc_client_secret" {
  description = "Secret of the Pocket ID client."
  type        = string
  sensitive   = true
}

variable "admin_subject" {
  description = "Pocket ID user ID that gets the admin policy."
  type        = string
}

variable "k8s_issuer" {
  description = "Service account token issuer of the Talos cluster."
  type        = string
}

variable "k8s_service_account_public_key" {
  description = "Public key that signs the cluster's service account tokens."
  type        = string
}
