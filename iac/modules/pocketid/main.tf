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

resource "pocketid_client" "proxmox" {
  name         = "Proxmox"
  client_id    = "proxmox"
  launch_url   = "https://pve.home.${var.domain}"
  is_public    = false
  pkce_enabled = false

  callback_urls = [
    "https://pve.home.${var.domain}",
    "https://proxmox.home.${var.domain}:8006",
  ]
}

resource "pocketid_client" "nas" {
  name         = "Proxmox NAS"
  client_id    = "pve-desktop"
  launch_url   = "https://pve-desktop.home.${var.domain}"
  is_public    = false
  pkce_enabled = false

  callback_urls = [
    "https://pve-desktop.home.${var.domain}",
    "https://proxmox-desktop.home.${var.domain}:8006",
  ]
}

resource "pocketid_client" "immich" {
  name         = "Immich"
  client_id    = "immich"
  launch_url   = "https://immich.home.${var.domain}"
  is_public    = false
  pkce_enabled = false

  callback_urls = [
    "https://immich.home.${var.domain}/auth/login",
    "https://immich.home.${var.domain}/user-settings",
    "app.immich:///oauth-callback",
    "https://power-tools.home.${var.domain}/api/auth/oauth/callback",
  ]
}
