resource "proxmox_virtual_environment_container" "garage" {
  node_name     = "pve"
  vm_id         = 140
  description   = "Garage, managed by OpenTofu (talos-homelab)"
  tags          = ["garage"]
  unprivileged  = true
  start_on_boot = true
  started       = true

  startup {
    order = 1
  }

  operating_system {
    template_file_id = proxmox_download_file.debian_13_lxc.id
    type             = "debian"
  }

  cpu {
    cores = 1
  }

  memory {
    dedicated = 512
    swap      = 0
  }

  disk {
    datastore_id = "local-lvm"
    size         = 4
  }

  mount_point {
    volume = "local-lvm"
    size   = "10G"
    path   = "/var/lib/garage/data"
    backup = true
  }

  features {
    nesting = true
  }

  network_interface {
    name     = "eth0"
    bridge   = "vmbr0"
    firewall = true
  }

  initialization {
    hostname = "garage"

    dns {
      servers = ["1.1.1.1"]
    }

    ip_config {
      ipv4 {
        address = "192.168.1.40/24"
        gateway = "192.168.1.1"
      }
    }
  }
}

resource "proxmox_virtual_environment_firewall_options" "garage" {
  node_name     = "pve"
  container_id  = proxmox_virtual_environment_container.garage.vm_id
  enabled       = true
  input_policy  = "DROP"
  output_policy = "ACCEPT"
}

resource "proxmox_virtual_environment_firewall_rules" "garage" {
  node_name    = "pve"
  container_id = proxmox_virtual_environment_container.garage.vm_id

  rule {
    type   = "in"
    action = "ACCEPT"
    proto  = "tcp"
    dport  = "3900"
    source = "192.168.1.30"
  }
}
