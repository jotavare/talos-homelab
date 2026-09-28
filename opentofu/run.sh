#!/bin/sh
set -eu
cd "$(dirname "$0")"

load() {
  value="$(sops decrypt --extract "[\"$3\"]" "../secrets/$2")" || exit 1
  export "$1=$value"
}

load TF_VAR_state_passphrase           opentofu.sops.yaml  state_passphrase

load TF_VAR_proxmox_host               env.sops.yaml       PROXMOX_HOST
load PROXMOX_VE_API_TOKEN              opentofu.sops.yaml  proxmox_api_token

load TF_VAR_domain                     env.sops.yaml       DOMAIN
load TF_VAR_cloudflare_zone_id         env.sops.yaml       CLOUDFLARE_ZONE_ID
load CLOUDFLARE_API_TOKEN              opentofu.sops.yaml  cloudflare_dns_token

load TF_VAR_services_tailnet_ip        env.sops.yaml       SERVICES_TAILNET_IP
load TF_VAR_cloudflare_pve_acme_token  opentofu.sops.yaml  cloudflare_pve_acme_token

exec tofu "$@"
