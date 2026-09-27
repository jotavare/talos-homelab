resource "proxmox_download_file" "debian_13_lxc" {
  node_name          = "pve"
  datastore_id       = "local"
  content_type       = "vztmpl"
  url                = "http://download.proxmox.com/images/system/debian-13-standard_13.6-1_amd64.tar.zst"
  checksum           = "4c0c27ca6ceab5ef0b84db57825a00f26157ef1854bafe97297813e1cbe8ecb8cc9c453cab6b3b0efe1ba193a50c47ece1e41d950e411b8730b835b71e9e754b"
  checksum_algorithm = "sha512"
}

resource "proxmox_virtual_environment_container" "openbao" {
  node_name     = "pve"
  vm_id         = 130
  description   = "OpenBao, managed by OpenTofu (talos-homelab)"
  tags          = ["openbao"]
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
    size         = 8
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
    hostname = "openbao"

    dns {
      servers = ["1.1.1.1"]
    }

    ip_config {
      ipv4 {
        address = "192.168.1.30/24"
        gateway = "192.168.1.1"
      }
    }
  }
}

resource "proxmox_virtual_environment_firewall_options" "openbao" {
  node_name     = "pve"
  container_id  = proxmox_virtual_environment_container.openbao.vm_id
  enabled       = true
  input_policy  = "DROP"
  output_policy = "ACCEPT"
}

resource "proxmox_virtual_environment_firewall_rules" "openbao" {
  node_name    = "pve"
  container_id = proxmox_virtual_environment_container.openbao.vm_id

  rule {
    type   = "in"
    action = "ACCEPT"
    proto  = "udp"
    dport  = "41641"
  }
}
