resource "docker_image" "tailscale" {
  name         = "tailscale/tailscale:v1.102.5@sha256:c507f3a2a6ab1cabd8d809b98edeb41edbd5c3fb6ad9632ffd098b4c7d0b4065"
  keep_locally = true
}

resource "docker_image" "caddy" {
  name         = "caddy-cloudflare:2.11.4"
  keep_locally = true

  build {
    context            = "${local.files}/caddy"
    use_legacy_builder = true
  }

  triggers = {
    dockerfile = filesha256("${local.files}/caddy/Dockerfile")
  }
}

resource "docker_container" "tailscale" {
  name                  = "tailscale"
  image                 = docker_image.tailscale.image_id
  hostname              = "services"
  restart               = "unless-stopped"
  destroy_grace_seconds = 30

  env = [
    "TS_AUTHKEY=file:/run/secrets/tailscale_auth_key",
    "TS_AUTH_ONCE=true",
    "TS_STATE_DIR=/var/lib/tailscale",
    "TS_HOSTNAME=services",
    "TS_EXTRA_ARGS=--advertise-tags=tag:services",
    "TS_TAILSCALED_EXTRA_ARGS=--port=41641",
    "TS_ACCEPT_DNS=false",
  ]

  upload {
    file        = "/run/secrets/tailscale_auth_key"
    content     = local.secrets["tailscale"]["auth_key"]
    permissions = "0600"
  }

  volumes {
    volume_name    = docker_volume.tailscale.name
    container_path = "/var/lib/tailscale"
  }

  ports {
    internal = 41641
    external = 41641
    protocol = "udp"
  }

  networks_advanced {
    name = docker_network.services.name
  }

  networks_advanced {
    name = docker_network.backend.name
  }
}

resource "docker_container" "caddy" {
  name                  = "caddy"
  image                 = docker_image.caddy.image_id
  restart               = "unless-stopped"
  destroy_grace_seconds = 30
  network_mode          = "container:${docker_container.tailscale.id}"

  env = [
    "DOMAIN=${var.domain}",
    "ACME_EMAIL=${var.acme_email}",
  ]

  upload {
    file    = "/etc/caddy/Caddyfile"
    content = file("${local.files}/caddy/Caddyfile")
  }

  upload {
    file        = "/run/secrets/cloudflare_token"
    content     = local.secrets["caddy"]["cloudflare_token"]
    permissions = "0600"
  }

  volumes {
    volume_name    = docker_volume.caddy_data.name
    container_path = "/data"
  }

  volumes {
    volume_name    = docker_volume.caddy_config.name
    container_path = "/config"
  }
}
