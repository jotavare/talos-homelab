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
  oidc_issuer           = "https://auth.home.${var.domain}"
  oidc_client_id        = module.pocketid.proxmox_client_id
  oidc_client_secret    = module.pocketid.proxmox_client_secret
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

module "talos" {
  source        = "./modules/talos"
  talos_version = "v1.14.2"

  nodes = {
    talos-cp-1 = { role = "controlplane", ip = "192.168.1.15", cores = 2, memory = 4096, disk = 32 }
    talos-w-1  = { role = "worker", ip = "192.168.1.21", cores = 4, memory = 8192, disk = 80 }
    talos-w-2  = { role = "worker", ip = "192.168.1.22", cores = 4, memory = 8192, disk = 80 }
  }
}

output "proxmox_version" {
  value = module.proxmox.version
}
