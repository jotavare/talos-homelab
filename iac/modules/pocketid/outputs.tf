output "admin_id" {
  value = data.pocketid_user.admin.id
}

output "openbao_client_id" {
  value = pocketid_client.openbao.client_id
}

output "openbao_client_secret" {
  value     = pocketid_client.openbao.client_secret
  sensitive = true
}

output "proxmox_client_id" {
  value = pocketid_client.proxmox.client_id
}

output "proxmox_client_secret" {
  value     = pocketid_client.proxmox.client_secret
  sensitive = true
}

output "nas_client_id" {
  value = pocketid_client.nas.client_id
}

output "nas_client_secret" {
  value     = pocketid_client.nas.client_secret
  sensitive = true
}

output "immich_client_id" {
  value = pocketid_client.immich.client_id
}

output "immich_client_secret" {
  value     = pocketid_client.immich.client_secret
  sensitive = true
}
