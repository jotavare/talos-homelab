resource "proxmox_virtual_environment_vm" "services" {
  node_name   = "pve"
  vm_id       = 130
  name        = "services"
  description = "Services VM, managed by OpenTofu (talos-homelab)"
  tags        = ["services"]
  on_boot     = true

  machine       = "q35"
  bios          = "ovmf"
  scsi_hardware = "virtio-scsi-single"

  startup {
    order = 1
  }

  agent {
    enabled = false
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 1536
    floating  = 0
  }

  efi_disk {
    datastore_id = "local-lvm"
    type         = "4m"
  }

  disk {
    datastore_id = "local-lvm"
    import_from  = proxmox_download_file.debian_13_cloud.id
    interface    = "scsi0"
    size         = 32
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

  serial_device {}

  initialization {
    datastore_id = "local-lvm"

    dns {
      servers = ["1.1.1.1"]
    }

    ip_config {
      ipv4 {
        address = "192.168.1.30/24"
        gateway = "192.168.1.1"
      }
    }

    user_account {
      username = "debian"
      keys     = [trimspace(file(pathexpand("~/.ssh/id_ed25519.pub")))]
    }
  }
}

resource "proxmox_virtual_environment_firewall_options" "services" {
  node_name     = "pve"
  vm_id         = proxmox_virtual_environment_vm.services.vm_id
  enabled       = true
  input_policy  = "DROP"
  output_policy = "ACCEPT"
}

resource "proxmox_virtual_environment_firewall_rules" "services" {
  node_name = "pve"
  vm_id     = proxmox_virtual_environment_vm.services.vm_id

  rule {
    type   = "in"
    action = "ACCEPT"
    proto  = "tcp"
    dport  = "22"
    source = "192.168.1.10"
  }

  rule {
    type   = "in"
    action = "ACCEPT"
    proto  = "udp"
    dport  = "41641"
  }
}
