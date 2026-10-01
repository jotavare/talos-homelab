module "dns" {
  source      = "./modules/dns"
  domain      = var.domain
  zone_id     = local.config["cloudflare_zone_id"]
  services_ip = local.config["services_tailnet_ip"]
  proxmox_ip  = var.proxmox_host
}

module "proxmox" {
  source                = "./modules/proxmox"
  cloudflare_zone_id    = local.config["cloudflare_zone_id"]
  cloudflare_acme_token = ephemeral.vault_kv_secret_v2.opentofu.data["cloudflare_pve_acme_token"]
  acme_domains          = [module.dns.names["pve"], module.dns.names["proxmox"]]
}

module "services" {
  source     = "./modules/services"
  domain     = var.domain
  acme_email = var.acme_email
  secrets    = local.secrets
}

module "pocketid" {
  source = "./modules/pocketid"
  domain = var.domain
  admin  = "jotavare"
}

module "openbao" {
  source             = "./modules/openbao"
  domain             = var.domain
  oidc_client_id     = module.pocketid.openbao_client_id
  oidc_client_secret = module.pocketid.openbao_client_secret
  admin_subject      = module.pocketid.admin_id
}

module "tailscale" {
  source = "./modules/tailscale"
  policy = file("${path.root}/../tailscale/policy.hujson")
}

output "proxmox_version" {
  value = module.proxmox.version
}
