resource "docker_image" "openbao" {
  name         = "openbao/openbao:2.7.0@sha256:71156a1c6623a5fa3f5e61b0c6a8ead0faf0df29a778339188443551995d1315"
  keep_locally = true
}

resource "docker_container" "openbao" {
  name                  = "openbao"
  image                 = docker_image.openbao.image_id
  command               = ["server", "-config=/openbao/config/openbao.hcl"]
  restart               = "unless-stopped"
  destroy_grace_seconds = 30
  env                   = ["BAO_API_ADDR=https://openbao.home.${var.domain}"]

  upload {
    file    = "/openbao/config/openbao.hcl"
    content = file("${path.module}/openbao/openbao.hcl")
  }

  volumes {
    host_path      = "/srv/openbao"
    container_path = "/openbao/data"
  }

  networks_advanced {
    name = docker_network.backend.name
  }
}
