#!/bin/bash
set -euo pipefail

RKE2_VERSION="${rke2_version}"
RKE2_TOKEN="${rke2_token}"
CLUSTER_NAME="${cluster_name}"
INIT_SERVER="${init_server}"
FIRST_CP_IP="${first_cp_ip}"

export INSTALL_RKE2_VERSION="$RKE2_VERSION"
export INSTALL_RKE2_TYPE="server"

mkdir -p /etc/rancher/rke2

cat > /etc/rancher/rke2/config.yaml <<EOF
token: $RKE2_TOKEN
tls-san:
  - $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
  - $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
node-taint:
  - "CriticalAddonsOnly=true:NoExecute"
etcd-expose-metrics: true
kube-apiserver-arg:
  - "audit-log-path=/var/log/kube-audit.log"
  - "audit-log-maxage=30"
cni: canal
disable:
  - rke2-ingress-nginx
EOF

if [ "$INIT_SERVER" = "false" ]; then
  until curl -sk "https://$FIRST_CP_IP:9345/ping" &>/dev/null; do
    echo "Waiting for first control-plane at $FIRST_CP_IP..."
    sleep 10
  done
  echo "server: https://$FIRST_CP_IP:9345" >> /etc/rancher/rke2/config.yaml
fi

curl -sfL https://get.rke2.io | sh -

systemctl enable rke2-server
systemctl start rke2-server

# Symlink kubectl
ln -sf /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl
echo 'export KUBECONFIG=/etc/rancher/rke2/rke2.yaml' >> /root/.bashrc
