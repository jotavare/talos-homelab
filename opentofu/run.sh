#!/bin/sh
set -eu
cd "$(dirname "$0")"

: "${BAO_ADDR:?set BAO_ADDR to https://openbao.home.<domain> and run bao login}"

load() {
  value="$(bao kv get -mount=kv -field="$3" "$2")" || exit 1
  export "$1=$value"
}

load TF_VAR_state_passphrase           opentofu  state_passphrase
load AWS_ACCESS_KEY_ID                 opentofu  garage_access_key_id
load AWS_SECRET_ACCESS_KEY             opentofu  garage_secret_access_key

load TF_VAR_proxmox_host               config    proxmox_host
load PROXMOX_VE_API_TOKEN              opentofu  proxmox_api_token

load TF_VAR_domain                     config    domain
load TF_VAR_cloudflare_zone_id         config    cloudflare_zone_id
load CLOUDFLARE_API_TOKEN              opentofu  cloudflare_dns_token

load TF_VAR_services_tailnet_ip        config    services_tailnet_ip
load TF_VAR_cloudflare_pve_acme_token  opentofu  cloudflare_pve_acme_token

if [ "${1:-}" = init ]; then
  shift
  exec tofu init -backend-config="endpoints={s3=\"https://s3.home.$TF_VAR_domain\"}" "$@"
fi

exec tofu "$@"
