resource "docker_image" "pocket_id" {
  name         = "pocketid/pocket-id:v2.16.0@sha256:9366436f3fd21619ed7e5709fa0acac88130f73414ec8ee1caf768fc487111ea"
  keep_locally = true
}

resource "docker_container" "pocket_id" {
  name                  = "pocket-id"
  image                 = docker_image.pocket_id.image_id
  restart               = "unless-stopped"
  destroy_grace_seconds = 30

  env = [
    "APP_URL=https://auth.home.${var.domain}",
    "TRUST_PROXY=true",
    "ENCRYPTION_KEY_FILE=/run/secrets/encryption_key",
    "PUID=1000",
    "PGID=1000",
    "ANALYTICS_DISABLED=true",
    "VERSION_CHECK_DISABLED=true",
  ]

  upload {
    file        = "/run/secrets/encryption_key"
    content     = local.secrets["pocket-id"]["encryption_key"]
    permissions = "0600"
    owner       = 1000
    group       = 1000
  }

  volumes {
    host_path      = "/srv/pocket-id"
    container_path = "/app/data"
  }

  networks_advanced {
    name = docker_network.backend.name
  }
}
