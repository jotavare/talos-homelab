#!/bin/sh
set -e
cd "$(git rev-parse --show-toplevel)"

echo "== pre-commit, every file"
pre-commit run --all-files

echo "== gitleaks, full history"
gitleaks git --redact --no-banner .

echo "== trufflehog, full history"
trufflehog git file://. --no-verification --no-update --fail

echo "== flux-schema, gitops/"
flux-schema validate gitops \
  --schema-location default \
  --schema-location ecosystem \
  --envsubst-file .github/flux-schema.env \
  --envsubst-strict

echo "== all checks passed"
