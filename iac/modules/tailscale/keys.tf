resource "tailscale_tailnet_key" "talos" {
  description   = "talos nodes"
  reusable      = true
  ephemeral     = false
  preauthorized = true
  tags          = ["tag:talos"]
}
