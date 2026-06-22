#!/bin/bash
# Run after `terraform apply` to substitute the nip.io domain into all helm values.
# Usage: bash scripts/setup-domain.sh
# Or:    bash scripts/setup-domain.sh 1.2.3.4   (skip terraform lookup)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform/aws"

if [ -n "${1:-}" ]; then
  EIP="$1"
else
  EIP=$(terraform -chdir="$TF_DIR" output -raw ingress_eip 2>/dev/null)
fi

if [ -z "$EIP" ]; then
  echo "ERROR: Could not determine EIP. Run terraform apply first, or pass IP as argument." >&2
  exit 1
fi

DOMAIN="${EIP}.nip.io"
echo "Setting domain: $DOMAIN"

# Replace in all helm values and argocd app manifests
find "$REPO_ROOT/helm" "$REPO_ROOT/argocd" "$REPO_ROOT/manifests" \
  -type f -name "*.yaml" \
  -exec sed -i "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" {} +

echo "Done. All DOMAIN_PLACEHOLDER → $DOMAIN"
echo ""
echo "Verify with:"
echo "  grep -r '$DOMAIN' $REPO_ROOT/helm/ | head -5"
