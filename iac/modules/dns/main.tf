locals {
  records = {
    pve               = var.services_ip
    openbao           = var.services_ip
    s3                = var.services_ip
    auth              = var.services_ip
    proxmox           = var.proxmox_ip
    "pve-desktop"     = var.services_ip
    "proxmox-desktop" = var.nas_ip
  }
}

resource "cloudflare_dns_record" "cluster" {
  for_each = toset(var.cluster_apps)
  zone_id  = var.zone_id
  name     = "${each.key}.home.${var.domain}"
  type     = "A"
  content  = var.gateway_ip
  ttl      = 300
  proxied  = false
}

resource "cloudflare_dns_record" "home" {
  for_each = local.records
  zone_id  = var.zone_id
  name     = "${each.key}.home.${var.domain}"
  type     = "A"
  content  = each.value
  ttl      = 300
  proxied  = false
}
