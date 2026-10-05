output "schematic_id" {
  value = talos_image_factory_schematic.this.id
}

output "image" {
  value = proxmox_download_file.talos.id
}
