#!/bin/bash
# On-prem RKE2 agent bootstrap
# Usage:
#   NODE_ROLE=ceph-osd  RKE2_TOKEN=xxx FIRST_CP_IP=<ip> bash bootstrap-rke2-agent.sh
#   NODE_ROLE=worker    RKE2_TOKEN=xxx FIRST_CP_IP=<ip> bash bootstrap-rke2-agent.sh
set -euo pipefail

: "${RKE2_VERSION:=v1.30.4+rke2r1}"
: "${RKE2_TOKEN:?RKE2_TOKEN required}"
: "${FIRST_CP_IP:?FIRST_CP_IP required}"
: "${NODE_ROLE:?NODE_ROLE required (ceph-osd|worker)}"

export INSTALL_RKE2_VERSION="$RKE2_VERSION"
export INSTALL_RKE2_TYPE="agent"

mkdir -p /etc/rancher/rke2

cat > /etc/rancher/rke2/config.yaml <<EOF
server: https://$FIRST_CP_IP:9345
token: $RKE2_TOKEN
EOF

case "$NODE_ROLE" in
  ceph-osd)
    cat >> /etc/rancher/rke2/config.yaml <<EOF
node-label:
  - "node-role.rook-ceph/osd=true"
node-taint:
  - "storage=ceph:NoSchedule"
EOF
    ;;
  worker)
    cat >> /etc/rancher/rke2/config.yaml <<EOF
node-label:
  - "node-role.kubernetes.io/worker=true"
EOF
    ;;
  *)
    echo "Unknown NODE_ROLE: $NODE_ROLE" >&2
    exit 1
    ;;
esac

until curl -sk "https://$FIRST_CP_IP:9345/ping" &>/dev/null; do
  echo "Waiting for RKE2 server..."
  sleep 10
done

curl -sfL https://get.rke2.io | sh -

systemctl enable rke2-agent
systemctl start rke2-agent
echo "RKE2 agent ($NODE_ROLE) ready."
