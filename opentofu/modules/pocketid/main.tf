data "pocketid_user" "admin" {
  username = var.admin
}

resource "pocketid_client" "openbao" {
  name         = "OpenBao"
  client_id    = "openbao"
  launch_url   = "https://openbao.home.${var.domain}"
  is_public    = false
  pkce_enabled = false

  callback_urls = [
    "https://openbao.home.${var.domain}/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback",
  ]
}
