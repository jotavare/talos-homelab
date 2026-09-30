provider "tailscale" {
  oauth_client_id     = ephemeral.vault_kv_secret_v2.opentofu.data["tailscale_oauth_client_id"]
  oauth_client_secret = ephemeral.vault_kv_secret_v2.opentofu.data["tailscale_oauth_client_secret"]
  scopes              = ["policy_file"]
}

resource "tailscale_acl" "policy" {
  acl = file("${path.module}/../tailscale/policy.hujson")
}
