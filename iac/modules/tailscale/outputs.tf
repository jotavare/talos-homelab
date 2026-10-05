output "gateway_ip" {
  value = [for a in data.tailscale_device.gateway.addresses : a if !strcontains(a, ":")][0]
}

output "talos_auth_key" {
  value     = tailscale_tailnet_key.talos.key
  sensitive = true
}
