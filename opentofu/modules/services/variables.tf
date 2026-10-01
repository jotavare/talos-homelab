variable "domain" {
  description = "Lab domain."
  type        = string
}

variable "acme_email" {
  description = "Let's Encrypt contact for Caddy."
  type        = string
}

variable "secrets" {
  description = "Service secrets from OpenBao, by service name."
  type        = map(map(string))
  sensitive   = true
}
