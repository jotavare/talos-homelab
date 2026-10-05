output "talos_auth_key" {
  value     = tailscale_tailnet_key.talos.key
  sensitive = true
}
