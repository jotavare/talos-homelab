data "proxmox_virtual_environment_version" "pve" {}

data "proxmox_virtual_environment_nodes" "all" {}

output "proxmox_version" {
  value = data.proxmox_virtual_environment_version.pve.version
}

output "nodes" {
  value = data.proxmox_virtual_environment_nodes.all.names
}
