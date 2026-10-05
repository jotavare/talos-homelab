resource "proxmox_acme_dns_plugin" "cloudflare" {
  plugin           = "cloudflare"
  api              = "cf"
  validation_delay = 30

  data_wo = {
    CF_Token   = var.cloudflare_acme_token
    CF_Zone_ID = var.cloudflare_zone_id
  }
  data_wo_version = 1
}

resource "proxmox_acme_certificate" "pve" {
  node_name = "pve"
  account   = "default"
  force     = true

  domains = [for d in var.acme_domains : {
    domain = d
    plugin = proxmox_acme_dns_plugin.cloudflare.plugin
  }]
}
