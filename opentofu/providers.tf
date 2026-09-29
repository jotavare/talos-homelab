provider "vault" {}

ephemeral "vault_kv_secret_v2" "opentofu" {
  mount = "kv"
  name  = "opentofu"
}

data "vault_kv_secret_v2" "config" {
  mount = "kv"
  name  = "config"
}

locals {
  config = nonsensitive(data.vault_kv_secret_v2.config.data)
  domain = local.config["domain"]
}

provider "proxmox" {
  endpoint  = "https://pve.home.${local.domain}/"
  api_token = ephemeral.vault_kv_secret_v2.opentofu.data["proxmox_api_token"]
}

provider "cloudflare" {
  api_token = ephemeral.vault_kv_secret_v2.opentofu.data["cloudflare_dns_token"]
}
