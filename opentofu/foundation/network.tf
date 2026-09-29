resource "docker_network" "backend" {
  name     = "backend"
  internal = true
}

resource "docker_network" "services" {
  name = "services"
}

resource "docker_volume" "tailscale" {
  name = "caddy_tailscale"
}

resource "docker_volume" "caddy_data" {
  name = "caddy_caddy-data"
}

resource "docker_volume" "caddy_config" {
  name = "caddy_caddy-config"
}
