resource "proxmox_realm_openid" "pocket_id" {
  realm                 = "pocket-id"
  comment               = "Pocket ID"
  issuer_url            = var.oidc_issuer
  client_id             = var.oidc_client_id
  client_key_wo         = var.oidc_client_secret
  client_key_wo_version = 1
  username_claim        = "username"
  scopes                = "openid profile email"
  autocreate            = false
  default               = true
}
