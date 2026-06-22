# MLOps K8s Cluster

RKE2 기반 MLOps 클러스터. AWS EC2 테스트 환경 → 온프레미스 동일 구조로 이식 가능.

## 스택

| 컴포넌트 | 역할 |
|---------|------|
| RKE2 | Kubernetes 배포판 |
| Rook-Ceph | 분산 스토리지 (block / filesystem / object) |
| Harbor | 컨테이너 레지스트리 |
| CloudNativePG | PostgreSQL 오퍼레이터 |
| MLflow | ML 실험 추적 |
| Argo Workflows | ML 파이프라인 |
| Argo CD | GitOps 배포 |
| GitHub ARC | Self-hosted runner |
| Prometheus + Grafana + Loki + OTel | 모니터링 / 로깅 |
| ingress-nginx | Ingress (hostNetwork, EIP) |
| cert-manager | TLS 인증서 자동화 |

## 노드 구성 (AWS EC2)

| 역할 | 인스턴스 | 대수 |
|------|---------|------|
| Control Plane | m5.large (2c/8GB) | 3 |
| Ceph OSD | m5.xlarge (4c/16GB) + EBS 200GB | 3 |
| Worker (ingress-0 포함) | m5.xlarge (4c/16GB) | 2 |

---

## 사전 준비

### 0. 로컬 도구 설치

```bash
# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# terraform
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y terraform
```

### 1. AWS CLI 설정

```bash
aws configure
# AWS Access Key ID, Secret, region: ap-northeast-2
```

### 2. EC2 키 페어 등록

```bash
# 기존 .pem 파일을 AWS에 import
aws ec2 import-key-pair \
  --key-name personal_aws \
  --public-key-material fileb://<(ssh-keygen -y -f ~/.ssh/personal_aws.pem) \
  --region ap-northeast-2
```

### 3. terraform.tfvars 작성

```bash
# 토큰 생성
openssl rand -hex 16
```

`terraform/aws/terraform.tfvars`:
```hcl
aws_region   = "ap-northeast-2"
cluster_name = "mlops-test"
key_name     = "personal_aws"
rke2_token   = "<생성한 토큰>"

allowed_ssh_cidrs = ["0.0.0.0/0"]   # 실제 운영 시 VPN IP로 제한
allowed_api_cidrs = ["0.0.0.0/0"]
```

---

## 클러스터 배포

```bash
# 1. Terraform 초기화
make tf-init

# 2. EC2 인스턴스 생성 (약 3-5분)
make tf-apply

# 3. nip.io 도메인 세팅 (EIP → helm values 자동 치환)
make setup-domain

# 4. kubeconfig 가져오기
make kubeconfig

# 5. 노드 Ready 확인 (RKE2 부팅 대기)
make nodes
# 8개 노드 모두 Ready 확인 후 진행

# 6. ArgoCD 설치 + 전체 스택 배포
make bootstrap-argocd
```

### ArgoCD 초기 비밀번호 확인

```bash
make argocd-password
```

접속: `https://argocd.<EIP>.nip.io`
### 앱 배포 상태 확인

```bash
make status
```

---

## 클러스터 종료

```bash
make tf-destroy
# 클러스터 이름 재입력 확인 후 전체 삭제 (EIP 포함)
```

---

## 온프레미스 이식

노드 프로비저닝만 수동으로 대체. RKE2 설치, Helm values, ArgoCD 앱은 동일.

### Control Plane

```bash
# cp-0 (초기화)
NODE_INDEX=0 RKE2_TOKEN=<토큰> bash scripts/bootstrap-rke2-server.sh

# cp-1, cp-2 (join)
NODE_INDEX=1 FIRST_CP_IP=<cp-0 IP> RKE2_TOKEN=<토큰> bash scripts/bootstrap-rke2-server.sh
NODE_INDEX=2 FIRST_CP_IP=<cp-0 IP> RKE2_TOKEN=<토큰> bash scripts/bootstrap-rke2-server.sh
```

### Worker / Ceph OSD 노드

```bash
# Ceph OSD 노드 (×3)
NODE_ROLE=ceph-osd FIRST_CP_IP=<cp-0 IP> RKE2_TOKEN=<토큰> bash scripts/bootstrap-rke2-agent.sh

# Worker 노드 (×2)
NODE_ROLE=worker FIRST_CP_IP=<cp-0 IP> RKE2_TOKEN=<토큰> bash scripts/bootstrap-rke2-agent.sh
```

### 온프레미스 스토리지 설정

`helm/values/rook-ceph-cluster.yaml`에서 디바이스 이름 수정:
```yaml
# AWS: xvdf  →  온프레미스: sdb (실제 디스크 이름으로 변경)
devices:
  - name: "sdb"
```

### 온프레미스 Ingress

`helm/values/ingress-nginx.yaml`에서 노드 IP를 도메인으로 사용:
- nip.io: `<노드 고정 IP>.nip.io`
- 또는 내부 DNS에 A 레코드 등록

---

## 파일 구조

```
k8s_clusters/
├── Makefile
├── terraform/aws/          # EC2 프로비저닝
├── scripts/                # 온프레미스 RKE2 부트스트랩
├── helm/values/            # 전체 컴포넌트 Helm values
├── manifests/cnpg/         # CloudNativePG 클러스터 정의
└── argocd/
    ├── bootstrap/          # app-of-apps 진입점
    └── apps/
        ├── infrastructure/ # cert-manager, ingress, rook-ceph, monitoring
        └── platform/       # harbor, mlops, cicd
```

---

## 주의사항

- `terraform/aws/terraform.tfvars` — 토큰 포함, git 커밋 금지 (`.gitignore` 등록 필요)
- EIP는 `tf-destroy` 시 반납 → 재apply 시 새 IP 발급 → `make setup-domain` 재실행 필요
- Ceph OSD 노드에 `storage=ceph:NoSchedule` taint 적용 — 일반 워크로드 스케줄링 안 됨
- ArgoCD app-of-apps의 `YOUR_ORG/k8s-clusters` → 실제 git repo로 변경 필요

### RKE2 내장 ingress-nginx 비활성화

RKE2는 기본으로 `kube-system`에 자체 ingress-nginx를 배포함. 이 클러스터는 worker-0(EIP)에 hostNetwork 방식의 커스텀 ingress-nginx를 사용하므로 내장 ingress-nginx를 비활성화.

비활성화하지 않으면 ArgoCD Helm 설치 시 아래 에러 발생:
```
failed calling webhook "validate.nginx.ingress.kubernetes.io": no endpoints available for service "rke2-ingress-nginx-controller-admission"
```

`control-plane.sh.tpl` 및 `bootstrap-rke2-server.sh`에 `disable: rke2-ingress-nginx` 포함되어 있으므로 `tf-apply` 시 자동 적용됨.
