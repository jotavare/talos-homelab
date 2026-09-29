resource "proxmox_acme_dns_plugin" "cloudflare" {
  plugin           = "cloudflare"
  api              = "cf"
  validation_delay = 30

  data_wo = {
    CF_Token   = ephemeral.vault_kv_secret_v2.opentofu.data["cloudflare_pve_acme_token"]
    CF_Zone_ID = local.config["cloudflare_zone_id"]
  }
  data_wo_version = 1
}

resource "proxmox_acme_certificate" "pve" {
  node_name = "pve"
  account   = "default"

  domains = [
    {
      domain = cloudflare_dns_record.pve.name
      plugin = proxmox_acme_dns_plugin.cloudflare.plugin
    },
  ]
}
