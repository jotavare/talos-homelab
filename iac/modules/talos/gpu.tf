resource "proxmox_hardware_mapping_pci" "igpu" {
  name    = "igpu"
  comment = "Intel UHD 770, passed to the Talos GPU worker"

  map = [
    {
      node         = "pve"
      path         = "0000:00:02.0"
      id           = "8086:4690"
      subsystem_id = "103c:8955"
      iommu_group  = 0
    },
  ]
}
