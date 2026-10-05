output "schematic_id" {
  value = talos_image_factory_schematic.this.id
}

output "image" {
  value = proxmox_download_file.talos.id
}

output "vm_ids" {
  value = { for k, v in proxmox_virtual_environment_vm.node : k => v.vm_id }
}
