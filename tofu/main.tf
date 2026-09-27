data "proxmox_version" "pve" {}

output "proxmox_version" {
  value = data.proxmox_version.pve.version
}
