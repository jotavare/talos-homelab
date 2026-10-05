resource "kubernetes_secret_v1" "cluster_settings" {
  metadata {
    name      = "cluster-settings"
    namespace = "flux-system"
  }
  data = var.settings
}

resource "tailscale_oauth_client" "operator" {
  description = "talos-homelab k8s operator"
  scopes      = ["devices:core", "auth_keys", "services"]
  tags        = ["tag:k8s-operator"]
}

resource "vault_kv_secret_v2" "tailscale_operator" {
  mount = "kv"
  name  = "k8s/tailscale-operator"
  data_json = jsonencode({
    client_id     = tailscale_oauth_client.operator.id
    client_secret = tailscale_oauth_client.operator.key
  })
}

resource "vault_kv_secret_v2" "cert_manager" {
  mount = "kv"
  name  = "k8s/cert-manager"
  data_json = jsonencode({
    cloudflare_token = var.cloudflare_token
  })
}
