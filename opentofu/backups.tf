resource "proxmox_backup_job" "containers" {
  id       = "daily-containers"
  node     = "pve"
  vmid     = [tostring(proxmox_virtual_environment_container.garage.vm_id)]
  schedule = "03:00"
  storage  = "local"
  mode     = "snapshot"
  compress = "zstd"
  enabled  = true

  prune_backups = {
    keep-last = "7"
  }
}
