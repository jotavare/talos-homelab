#!/bin/sh
set -eu
cd "$(dirname "$0")"
TF_VAR_proxmox_host="$(sops decrypt --extract '["PROXMOX_HOST"]' ../secrets/env.sops.yaml)"
PROXMOX_VE_API_TOKEN="$(sops decrypt --extract '["proxmox_api_token"]' ../secrets/opentofu.sops.yaml)"
TF_VAR_state_passphrase="$(sops decrypt --extract '["state_passphrase"]' ../secrets/opentofu.sops.yaml)"
export PROXMOX_VE_API_TOKEN TF_VAR_state_passphrase TF_VAR_proxmox_host
exec tofu "$@"
