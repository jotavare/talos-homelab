output "schematic_id" {
  value = talos_image_factory_schematic.this.id
}

output "image" {
  value = proxmox_download_file.talos.id
}

output "vm_ids" {
  value = { for k, v in proxmox_virtual_environment_vm.node : k => v.vm_id }
}

output "talosconfig" {
  value     = data.talos_client_configuration.this.talos_config
  sensitive = true
}

output "kubeconfig" {
  value     = replace(talos_cluster_kubeconfig.this.kubeconfig_raw, local.endpoint, "https://${local.api}:6443")
  sensitive = true
}

output "kubernetes" {
  value     = merge(talos_cluster_kubeconfig.this.kubernetes_client_configuration, { host = "https://${local.api}:6443" })
  sensitive = true
}
