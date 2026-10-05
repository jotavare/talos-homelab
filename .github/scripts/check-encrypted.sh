#!/bin/sh
status=0
for f in "$@"; do
  case "$f" in
    .sops.yaml | */.sops.yaml) ;;
    *.sops.yaml | *.sops.yml)
      if ! grep -q '^sops:' "$f" || ! grep -q 'ENC\[' "$f"; then
        echo "$f is not encrypted, run: sops encrypt -i $f" >&2
        status=1
      fi
      ;;
    *terraform.tfstate | *terraform.tfstate.backup)
      if ! grep -q '"encrypted_data"' "$f"; then
        echo "$f is not encrypted, check the encryption block in iac/versions.tf" >&2
        status=1
      fi
      ;;
  esac
done
exit $status
