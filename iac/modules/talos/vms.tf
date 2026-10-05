resource "proxmox_virtual_environment_vm" "node" {
  for_each = var.nodes

  node_name   = "pve"
  vm_id       = 100 + tonumber(split(".", each.value.ip)[3])
  name        = each.key
  description = "Talos ${each.value.role}, managed by OpenTofu (talos-homelab)"
  tags        = ["talos", each.value.role]
  on_boot     = true

  machine       = "q35"
  bios          = "ovmf"
  scsi_hardware = "virtio-scsi-single"

  startup {
    order = each.value.role == "controlplane" ? 2 : 3
  }

  agent {
    enabled = false
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
    floating  = 0
  }

  efi_disk {
    datastore_id = "local-lvm"
    type         = "4m"
  }

  disk {
    datastore_id = "local-lvm"
    import_from  = proxmox_download_file.talos.id
    interface    = "scsi0"
    size         = each.value.disk
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge   = "vmbr0"
    model    = "virtio"
    firewall = true
  }

  operating_system {
    type = "l26"
  }

  initialization {
    datastore_id = "local-lvm"

    dns {
      servers = ["1.1.1.1"]
    }

    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = "192.168.1.1"
      }
    }
  }

  lifecycle {
    ignore_changes = [disk[0].import_from]
  }
}

resource "proxmox_virtual_environment_firewall_options" "node" {
  for_each = var.nodes

  node_name     = "pve"
  vm_id         = proxmox_virtual_environment_vm.node[each.key].vm_id
  enabled       = true
  input_policy  = "DROP"
  output_policy = "ACCEPT"
  ipfilter      = false
}

resource "proxmox_virtual_environment_firewall_rules" "node" {
  for_each = var.nodes

  node_name = "pve"
  vm_id     = proxmox_virtual_environment_vm.node[each.key].vm_id

  rule {
    type   = "in"
    action = "ACCEPT"
    source = "192.168.1.15-192.168.1.29"
  }

  rule {
    type   = "in"
    action = "ACCEPT"
    proto  = "tcp"
    dport  = "50000"
    source = "192.168.1.0/24"
  }

  rule {
    type   = "in"
    action = "ACCEPT"
    proto  = "tcp"
    dport  = "6443"
    source = "192.168.1.0/24"
  }

  rule {
    type   = "in"
    action = "ACCEPT"
    proto  = "udp"
    dport  = "41641"
  }

  rule {
    type   = "in"
    action = "ACCEPT"
    proto  = "icmp"
    source = "192.168.1.0/24"
  }
}
