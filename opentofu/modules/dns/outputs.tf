output "names" {
  value = { for k, r in cloudflare_dns_record.home : k => r.name }
}
