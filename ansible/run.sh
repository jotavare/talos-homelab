#!/bin/sh
set -eu
cd "$(dirname "$0")"

: "${BAO_ADDR:?set BAO_ADDR to https://openbao.home.<domain> and run bao login}"

load() {
  value="$(bao kv get -mount=kv -field="$3" "$2")" || exit 1
  export "$1=$value"
}

load PROXMOX_HOST  config  proxmox_host
load DOMAIN        config  domain
load ACME_EMAIL    config  acme_email

exec ansible-playbook "$@"
