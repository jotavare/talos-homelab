ephemeral "vault_kv_secret_v2" "opentofu" {
  mount = "kv"
  name  = "opentofu"
}

data "vault_kv_secret_v2" "config" {
  mount = "kv"
  name  = "config"
}

data "vault_kv_secret_v2" "services" {
  for_each = toset(["caddy", "tailscale", "garage", "pocket-id"])
  mount    = "kv"
  name     = "services/${each.key}"
}

locals {
  config  = nonsensitive(data.vault_kv_secret_v2.config.data)
  secrets = { for k, v in data.vault_kv_secret_v2.services : k => v.data }
}
