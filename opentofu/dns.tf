resource "cloudflare_dns_record" "pve" {
  zone_id = local.config["cloudflare_zone_id"]
  name    = "pve.home.${local.domain}"
  type    = "A"
  content = local.config["services_tailnet_ip"]
  ttl     = 300
  proxied = false
}

resource "cloudflare_dns_record" "openbao" {
  zone_id = local.config["cloudflare_zone_id"]
  name    = "openbao.home.${local.domain}"
  type    = "A"
  content = local.config["services_tailnet_ip"]
  ttl     = 300
  proxied = false
}

resource "cloudflare_dns_record" "s3" {
  zone_id = local.config["cloudflare_zone_id"]
  name    = "s3.home.${local.domain}"
  type    = "A"
  content = local.config["services_tailnet_ip"]
  ttl     = 300
  proxied = false
}
