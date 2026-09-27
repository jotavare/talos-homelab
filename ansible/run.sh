#!/bin/sh
set -eu
cd "$(dirname "$0")"
exec sops exec-env ../secrets/env.sops.yaml "$(printf '%s ' ansible-playbook "$@")"
