#!/bin/bash
# On-prem RKE2 server bootstrap
# Usage:
#   NODE_INDEX=0 RKE2_TOKEN=xxx FIRST_CP_IP=<ip> bash bootstrap-rke2-server.sh
#   NODE_INDEX=1 RKE2_TOKEN=xxx FIRST_CP_IP=<first-cp-private-ip> bash bootstrap-rke2-server.sh
set -euo pipefail

: "${RKE2_VERSION:=v1.30.4+rke2r1}"
: "${RKE2_TOKEN:?RKE2_TOKEN required}"
: "${NODE_INDEX:=0}"
: "${FIRST_CP_IP:=}"
: "${PUBLIC_IP:=$(hostname -I | awk '{print $1}')}"

export INSTALL_RKE2_VERSION="$RKE2_VERSION"
export INSTALL_RKE2_TYPE="server"

mkdir -p /etc/rancher/rke2

cat > /etc/rancher/rke2/config.yaml <<EOF
token: $RKE2_TOKEN
tls-san:
  - $PUBLIC_IP
  - $(hostname -I | awk '{print $1}')
  - $(hostname -f)
node-taint:
  - "CriticalAddonsOnly=true:NoExecute"
etcd-expose-metrics: true
cni: canal
disable:
  - rke2-ingress-nginx
EOF

if [ "$NODE_INDEX" -ne 0 ]; then
  : "${FIRST_CP_IP:?FIRST_CP_IP required for non-init servers}"
  echo "server: https://$FIRST_CP_IP:9345" >> /etc/rancher/rke2/config.yaml

  until curl -sk "https://$FIRST_CP_IP:9345/ping" &>/dev/null; do
    echo "Waiting for first control-plane at $FIRST_CP_IP..."
    sleep 10
  done
fi

curl -sfL https://get.rke2.io | sh -

systemctl enable rke2-server
systemctl start rke2-server

ln -sf /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl
echo 'export KUBECONFIG=/etc/rancher/rke2/rke2.yaml' >> /root/.bashrc
echo "RKE2 server node $NODE_INDEX ready."
