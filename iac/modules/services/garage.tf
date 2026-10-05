resource "docker_image" "garage" {
  name         = "dxflrs/garage:v2.4.1@sha256:9c96caa2612d3411acc5b0e6701fb238dbfba33e533a6d7d3d811a4b12d0d020"
  keep_locally = true
}

resource "docker_container" "garage" {
  name                  = "garage"
  image                 = docker_image.garage.image_id
  command               = ["/garage", "server", "--single-node"]
  restart               = "unless-stopped"
  destroy_grace_seconds = 30

  upload {
    file    = "/etc/garage.toml"
    content = file("${path.module}/garage/garage.toml")
  }

  upload {
    file        = "/run/secrets/garage_rpc_secret"
    content     = var.secrets["garage"]["rpc_secret"]
    permissions = "0600"
  }

  volumes {
    host_path      = "/srv/garage/meta"
    container_path = "/var/lib/garage/meta"
  }

  volumes {
    host_path      = "/srv/garage/data"
    container_path = "/var/lib/garage/data"
  }

  networks_advanced {
    name = docker_network.backend.name
  }
}
