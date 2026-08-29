# EMS Platform — Enterprise GitOps on GKE

## Architecture

```
GitHub (web-client / event-service-platform / ai-platform)
  │  push to main → CI builds → pushes to GHCR → commits tag bump to k8s overlay
  ▼
infra repo (k8s overlays updated by CI)
  │
ArgoCD (App of Apps on GKE)
  ├── web-client     ──▶ web-client/k8s/overlays/prod
  ├── event-service  ──▶ event-service-platform/k8s/overlays/prod
  ├── ai-service    ──▶ ai-platform/k8s/overlays/prod
  ├── dataplatform  ──▶ infra/manifests/dataplatform/overlays/prod
  └── networking    ──▶ infra/manifests/networking

GKE Standard (Private Cluster)
  ├── system-pool  (g1-standard-2, 2 nodes) — ArgoCD, ESO, ingress
  ├── app-pool      (n2-standard-4, 2-10)  — services
  └── data-pool     (n2-standard-8, 1-3)   — Kafka

GCP Managed Services
  ├── Cloud SQL PostgreSQL 15 (private IP, HA)
  ├── Cloud Memorystore Redis 7 (Standard HA)
  └── Cloud Storage (backups, datalake)
```

## Quick Start

### 1. Create Terraform State Bucket (one-time)

```bash
gcloud init
gcloud auth application-default login

PROJECT_ID="your-gcp-project-id"
REGION="us-central1"

gsutil mb -l $REGION gs://${PROJECT_ID}-ems-terraform-state
```

### 2. Configure Terraform

```bash
cd infra/terraform/gke
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project_id, region, db_password, etc.

terraform init
terraform plan
terraform apply
```

### 3. Seed Secrets to GCP Secret Manager

```bash
# Get PostgreSQL IP from terraform output
terraform output postgres_ip

# Create secrets
gcloud secrets create ems-db-password --data-file=- <<< "your-db-password"
gcloud secrets create ems-db-user --data-file=- <<< "emsuser"
gcloud secrets create ems-db-name --data-file=- <<< "ems_events"
gcloud secrets create ems-db-host --data-file=- <<< "<POSTGRES_PRIVATE_IP>"
gcloud secrets create ems-jwt-secret --data-file=- <<< "your-jwt-secret-change-in-production"
gcloud secrets create ems-redis-password --data-file=- <<< "your-redis-password"
gcloud secrets create ems-hf-api-token --data-file=- <<< "your-hf-token"
gcloud secrets create ems-openai-api-key --data-file=- <<< "your-openai-key"
```

### 4. Bootstrap ArgoCD

```bash
gcloud container clusters get-credentials ems-cluster --region us-central1

kubectl apply -f manifests/networking/cert-manager/
kubectl apply -f argocd/bootstrap/
kubectl apply -f argocd/root-app.yaml

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d

# Port-forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### 5. Add GitHub Repo Credentials to ArgoCD

```bash
brew install argocd
argocd login localhost:8080 --username admin --password <PASSWORD>

argocd repo add https://github.com/smarteventmanagementsystem/infra.git \
  --username <github-username> \
  --password <github-pat>

argocd repo add https://github.com/smarteventmanagementsystem/web-client.git \
  --username <github-username> \
  --password <github-pat>

argocd repo add https://github.com/smarteventmanagementsystem/event-service-platform.git \
  --username <github-username> \
  --password <github-pat>

argocd repo add https://github.com/smarteventmanagementsystem/ai-platform.git \
  --username <github-username> \
  --password <github-pat>
```

### 6. Sync All Apps

```bash
argocd app sync --all
argocd app wait --all
```

### 7. Get LoadBalancer IP & Setup DNS

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Create DNS A records:
# app.ems.example.com        → <LB_IP>
# api-events.ems.example.com → <LB_IP>
# api-ai.ems.example.com      → <LB_IP>
```

## GitHub Secrets Required

**Each service repo** (web-client, event-service-platform, ai-platform):
- `PAT` — GitHub Personal Access Token with `repo` scope

**infra repo**:
- `GCP_CREDENTIALS` — GCP service account JSON key

**infra repo GitHub Variables**:
- `GCP_PROJECT_ID` — your GCP project ID
- `GCP_REGION` — us-central1
- `DOMAIN` — ems.example.com

## Directory Structure

```
infra/
├── terraform/gke/              # GKE + managed services
├── argocd/
│   ├── bootstrap/              # ArgoCD installation
│   ├── apps/                   # Individual ArgoCD Applications
│   └── root-app.yaml           # App of Apps root
├── manifests/
│   ├── networking/              # cert-manager, ingress-nginx
│   ├── external-secrets/        # GCP Secret Manager integration
│   └── dataplatform/           # Kafka, external services
└── scripts/
    └── bootstrap-argocd.sh
```

## CI/CD Flow

```
Developer pushes to main
    │
    ▼
GitHub Actions (build.yml)
    │  docker buildx push to GHCR
    │  git commit tag bump to k8s/overlays/prod/kustomization.yaml
    ▼
infra repo (kustomization files updated)
    │
ArgoCD detects changes (watches all 3 repos)
    │
    ├── web-client     → updates Deployment image
    ├── event-service → updates Rollout image + canary rollout
    └── ai-service    → updates Deployment image
```

## Manual Deployment

```bash
# Sync specific app
argocd app sync web-client

# Watch canary rollout
kubectl argo rollouts get rollout event-service -n event-service --watch

# Pause / resume
kubectl argo rollouts pause event-service -n event-service
kubectl argo rollouts resume event-service -n event-service

# Full promotion
kubectl argo rollouts promote event-service -n event-service

# Rollback
argocd app rollback event-service
kubectl argo rollouts undo event-service -n event-service
```
