CLUSTER_NAME ?= mlops-test
TF_DIR       := terraform/aws
KUBECONFIG   ?= ~/.kube/config-$(CLUSTER_NAME)
SSH_KEY      ?= ~/.ssh/personal_aws.pem

# ─── Terraform ────────────────────────────────────────────────────────────────

.PHONY: tf-init tf-plan tf-apply tf-destroy

tf-init:
	terraform -chdir=$(TF_DIR) init

tf-plan:
	terraform -chdir=$(TF_DIR) plan

tf-apply:
	terraform -chdir=$(TF_DIR) apply -auto-approve

tf-destroy:
	@echo "WARNING: This will destroy all nodes and data."
	@read -p "Type cluster name to confirm [$(CLUSTER_NAME)]: " confirm && [ "$$confirm" = "$(CLUSTER_NAME)" ]
	terraform -chdir=$(TF_DIR) destroy -auto-approve

# ─── Kubeconfig ───────────────────────────────────────────────────────────────

.PHONY: kubeconfig

kubeconfig:
	$(eval CP_IP := $(shell terraform -chdir=$(TF_DIR) output -json control_plane_public_ips | python3 -c "import sys,json; print(json.load(sys.stdin)[0])"))
	mkdir -p ~/.kube
	ssh -i $(SSH_KEY) -o StrictHostKeyChecking=no ubuntu@$(CP_IP) \
	  'sudo cat /etc/rancher/rke2/rke2.yaml' \
	  | sed 's/127.0.0.1/$(CP_IP)/g' \
	  > $(KUBECONFIG)
	chmod 600 $(KUBECONFIG)
	@echo "KUBECONFIG=$(KUBECONFIG)"

# ─── Bootstrap ArgoCD ─────────────────────────────────────────────────────────

.PHONY: bootstrap-argocd

bootstrap-argocd: kubeconfig
	KUBECONFIG=$(KUBECONFIG) helm repo add argo https://argoproj.github.io/argo-helm
	KUBECONFIG=$(KUBECONFIG) helm repo update
	KUBECONFIG=$(KUBECONFIG) helm upgrade --install argocd argo/argo-cd \
	  -n argocd --create-namespace \
	  -f helm/values/argocd.yaml \
	  --wait
	KUBECONFIG=$(KUBECONFIG) kubectl apply -f argocd/bootstrap/app-of-apps.yaml

# ─── Helpers ──────────────────────────────────────────────────────────────────

.PHONY: argocd-password nodes status

argocd-password:
	KUBECONFIG=$(KUBECONFIG) kubectl -n argocd get secret argocd-initial-admin-secret \
	  -o jsonpath="{.data.password}" | base64 -d && echo

setup-domain:
	bash scripts/setup-domain.sh

nodes:
	KUBECONFIG=$(KUBECONFIG) kubectl get nodes -o wide

status:
	KUBECONFIG=$(KUBECONFIG) kubectl get applications -n argocd

# ─── On-prem shortcut ─────────────────────────────────────────────────────────
# Usage: make onprem-server NODE_INDEX=0 FIRST_CP_IP= RKE2_TOKEN=xxx
.PHONY: onprem-server onprem-agent

onprem-server:
	NODE_INDEX=$(NODE_INDEX) FIRST_CP_IP=$(FIRST_CP_IP) RKE2_TOKEN=$(RKE2_TOKEN) \
	  bash scripts/bootstrap-rke2-server.sh

onprem-agent:
	NODE_ROLE=$(NODE_ROLE) FIRST_CP_IP=$(FIRST_CP_IP) RKE2_TOKEN=$(RKE2_TOKEN) \
	  bash scripts/bootstrap-rke2-agent.sh
