resource "proxmox_backup_job" "containers" {
  id            = "daily-containers"
  node          = "pve"
  vmid          = [tostring(proxmox_virtual_environment_vm.services.vm_id)]
  schedule      = "03:00"
  storage       = "local"
  mode          = "snapshot"
  compress      = "zstd"
  enabled       = true
  repeat_missed = true

  prune_backups = {
    keep-last = "5"
  }
}
