provider "proxmox" {
  endpoint = "https://${var.proxmox_host}:8006/"
  insecure = true
}

provider "cloudflare" {}
