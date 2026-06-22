#!/bin/bash
set -euo pipefail

RKE2_VERSION="${rke2_version}"
RKE2_TOKEN="${rke2_token}"
SERVER_URL="${server_url}"
NODE_LABELS="${node_labels}"
NODE_TAINTS="${node_taints}"

export INSTALL_RKE2_VERSION="$RKE2_VERSION"
export INSTALL_RKE2_TYPE="agent"

mkdir -p /etc/rancher/rke2

cat > /etc/rancher/rke2/config.yaml <<EOF
server: $SERVER_URL
token: $RKE2_TOKEN
EOF

# Apply labels
if [ -n "$NODE_LABELS" ]; then
  echo "node-label:" >> /etc/rancher/rke2/config.yaml
  IFS=',' read -ra LABELS <<< "$NODE_LABELS"
  for label in "$${LABELS[@]}"; do
    echo "  - \"$label\"" >> /etc/rancher/rke2/config.yaml
  done
fi

# Apply taints
if [ -n "$NODE_TAINTS" ]; then
  echo "node-taint:" >> /etc/rancher/rke2/config.yaml
  IFS=',' read -ra TAINTS <<< "$NODE_TAINTS"
  for taint in "$${TAINTS[@]}"; do
    echo "  - \"$taint\"" >> /etc/rancher/rke2/config.yaml
  done
fi

# Wait for server API to be reachable
until curl -sk "$SERVER_URL/ping" &>/dev/null; do
  echo "Waiting for RKE2 server..."
  sleep 10
done

curl -sfL https://get.rke2.io | sh -

systemctl enable rke2-agent
systemctl start rke2-agent
