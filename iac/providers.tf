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
  scopes              = ["all"]
}

provider "pocketid" {
  base_url  = "https://auth.home.${var.domain}"
  api_token = local.secrets["pocket-id"]["api_key"]
}

provider "helm" {
  kubernetes = {
    host                   = module.talos.kubernetes.host
    cluster_ca_certificate = base64decode(module.talos.kubernetes.ca_certificate)
    client_certificate     = base64decode(module.talos.kubernetes.client_certificate)
    client_key             = base64decode(module.talos.kubernetes.client_key)
  }
}
