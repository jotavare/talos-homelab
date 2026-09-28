resource "cloudflare_dns_record" "pve" {
  zone_id = var.cloudflare_zone_id
  name    = "pve.home.${var.domain}"
  type    = "A"
  content = var.services_tailnet_ip
  ttl     = 300
  proxied = false
}

resource "cloudflare_dns_record" "openbao" {
  zone_id = var.cloudflare_zone_id
  name    = "openbao.home.${var.domain}"
  type    = "A"
  content = var.services_tailnet_ip
  ttl     = 300
  proxied = false
}

resource "cloudflare_dns_record" "s3" {
  zone_id = var.cloudflare_zone_id
  name    = "s3.home.${var.domain}"
  type    = "A"
  content = var.services_tailnet_ip
  ttl     = 300
  proxied = false
}
