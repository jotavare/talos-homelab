provider "vault" {}

ephemeral "vault_kv_secret_v2" "opentofu" {
  mount = "kv"
  name  = "opentofu"
}

data "vault_kv_secret_v2" "services" {
  for_each = toset(["caddy", "tailscale", "garage"])
  mount    = "kv"
  name     = "services/${each.key}"
}

data "vault_kv_secret_v2" "config" {
  mount = "kv"
  name  = "config"
}

locals {
  config  = nonsensitive(data.vault_kv_secret_v2.config.data)
  domain  = var.domain
  files   = "${path.module}/files"
  secrets = { for k, v in data.vault_kv_secret_v2.services : k => v.data }
}

provider "proxmox" {
  endpoint  = "https://proxmox.home.${local.domain}:8006/"
  api_token = ephemeral.vault_kv_secret_v2.opentofu.data["proxmox_api_token"]
}

provider "cloudflare" {
  api_token = ephemeral.vault_kv_secret_v2.opentofu.data["cloudflare_dns_token"]
}

provider "docker" {
  host     = "ssh://debian@192.168.1.30"
  ssh_opts = ["-o", "ProxyJump=root@${var.proxmox_host}", "-o", "BatchMode=yes"]
}
