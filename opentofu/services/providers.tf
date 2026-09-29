provider "docker" {
  host     = "ssh://debian@192.168.1.30"
  ssh_opts = ["-o", "ProxyJump=root@${var.proxmox_host}", "-o", "BatchMode=yes"]
}

provider "vault" {}

data "vault_kv_secret_v2" "services" {
  for_each = toset(["caddy", "tailscale", "garage"])
  mount    = "kv"
  name     = "services/${each.key}"
}

locals {
  files   = "${path.module}/files"
  secrets = { for k, v in data.vault_kv_secret_v2.services : k => v.data }
}
