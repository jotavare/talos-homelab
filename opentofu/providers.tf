provider "vault" {}

provider "proxmox" {
  endpoint  = "https://proxmox.home.${var.domain}:8006/"
  api_token = ephemeral.vault_kv_secret_v2.opentofu.data["proxmox_api_token"]
}

provider "cloudflare" {
  api_token = ephemeral.vault_kv_secret_v2.opentofu.data["cloudflare_dns_token"]
}

provider "docker" {
  host     = "ssh://debian@192.168.1.30"
  ssh_opts = ["-o", "ProxyJump=root@${var.proxmox_host}", "-o", "BatchMode=yes"]
}

provider "tailscale" {
  oauth_client_id     = ephemeral.vault_kv_secret_v2.opentofu.data["tailscale_oauth_client_id"]
  oauth_client_secret = ephemeral.vault_kv_secret_v2.opentofu.data["tailscale_oauth_client_secret"]
  scopes              = ["policy_file"]
}
