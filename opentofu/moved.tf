moved {
  from = proxmox_download_file.debian_13_cloud
  to   = module.proxmox.proxmox_download_file.debian_13_cloud
}

moved {
  from = proxmox_virtual_environment_vm.services
  to   = module.proxmox.proxmox_virtual_environment_vm.services
}

moved {
  from = proxmox_virtual_environment_firewall_options.services
  to   = module.proxmox.proxmox_virtual_environment_firewall_options.services
}

moved {
  from = proxmox_virtual_environment_firewall_rules.services
  to   = module.proxmox.proxmox_virtual_environment_firewall_rules.services
}

moved {
  from = proxmox_backup_job.containers
  to   = module.proxmox.proxmox_backup_job.containers
}

moved {
  from = proxmox_acme_dns_plugin.cloudflare
  to   = module.proxmox.proxmox_acme_dns_plugin.cloudflare
}

moved {
  from = proxmox_acme_certificate.pve
  to   = module.proxmox.proxmox_acme_certificate.pve
}

moved {
  from = cloudflare_dns_record.pve
  to   = module.dns.cloudflare_dns_record.home["pve"]
}

moved {
  from = cloudflare_dns_record.openbao
  to   = module.dns.cloudflare_dns_record.home["openbao"]
}

moved {
  from = cloudflare_dns_record.s3
  to   = module.dns.cloudflare_dns_record.home["s3"]
}

moved {
  from = cloudflare_dns_record.auth
  to   = module.dns.cloudflare_dns_record.home["auth"]
}

moved {
  from = cloudflare_dns_record.proxmox
  to   = module.dns.cloudflare_dns_record.home["proxmox"]
}

moved {
  from = docker_network.backend
  to   = module.services.docker_network.backend
}

moved {
  from = docker_network.services
  to   = module.services.docker_network.services
}

moved {
  from = docker_volume.tailscale
  to   = module.services.docker_volume.tailscale
}

moved {
  from = docker_volume.caddy_data
  to   = module.services.docker_volume.caddy_data
}

moved {
  from = docker_volume.caddy_config
  to   = module.services.docker_volume.caddy_config
}

moved {
  from = docker_image.openbao
  to   = module.services.docker_image.openbao
}

moved {
  from = docker_container.openbao
  to   = module.services.docker_container.openbao
}

moved {
  from = docker_image.garage
  to   = module.services.docker_image.garage
}

moved {
  from = docker_container.garage
  to   = module.services.docker_container.garage
}

moved {
  from = docker_image.tailscale
  to   = module.services.docker_image.tailscale
}

moved {
  from = docker_image.caddy
  to   = module.services.docker_image.caddy
}

moved {
  from = docker_container.tailscale
  to   = module.services.docker_container.tailscale
}

moved {
  from = docker_container.caddy
  to   = module.services.docker_container.caddy
}

moved {
  from = docker_image.pocket_id
  to   = module.services.docker_image.pocket_id
}

moved {
  from = docker_container.pocket_id
  to   = module.services.docker_container.pocket_id
}

moved {
  from = vault_mount.kv
  to   = module.openbao.vault_mount.kv
}

moved {
  from = vault_auth_backend.userpass
  to   = module.openbao.vault_auth_backend.userpass
}

moved {
  from = vault_policy.admin
  to   = module.openbao.vault_policy.admin
}

moved {
  from = vault_generic_endpoint.admin_user
  to   = module.openbao.vault_generic_endpoint.admin_user
}

moved {
  from = tailscale_acl.policy
  to   = module.tailscale.tailscale_acl.policy
}
