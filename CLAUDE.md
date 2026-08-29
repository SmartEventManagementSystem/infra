# CLAUDE.md — EMS Platform Infrastructure

## Overview

This repo manages the production infrastructure for the EMS Platform on GKE (Google Kubernetes Engine) using GitOps with ArgoCD.

## Architecture

- **GKE Standard** — Private cluster with 3 nodepools (system, app, data)
- **Cloud SQL PostgreSQL 15** — Managed database (private IP)
- **Cloud Memorystore Redis 7** — Managed cache (Standard HA)
- **GCP Secret Manager** — Secrets via External Secrets Operator
- **ArgoCD** — GitOps deployment (App of Apps pattern)

## Directory Structure

```
terraform/gke/      # GKE cluster + managed services (Terraform)
argocd/             # ArgoCD bootstrap + app definitions
manifests/          # Kubernetes manifests (networking, ESO, dataplatform)
scripts/            # Deployment scripts
```

## Key Files

- `terraform/gke/main.tf` — Cluster, node pools, Cloud SQL, Redis, Secret Manager
- `argocd/root-app.yaml` — App of Apps root (syncs all child apps)
- `argocd/apps/` — Individual ArgoCD Applications per service
- `manifests/networking/` — cert-manager, ingress-nginx
- `manifests/external-secrets/` — GCP Secret Manager integration
- `manifests/dataplatform/` — Kafka StatefulSet, external service pointers

## GitOps Flow

```
Push to main → GitHub Actions build → GHCR push → commit kustomization tag bump
    → infra repo updated → ArgoCD syncs → Kubernetes updated
```

## Service Repos

Each service repo owns its own Kubernetes manifests:
- `web-client/k8s/overlays/prod/` — ArgoCD watches this
- `event-service-platform/k8s/overlays/prod/` — ArgoCD watches this
- `ai-platform/k8s/overlays/prod/` — ArgoCD watches this

## Terraform Apply

Only via git tag:
```bash
git tag infra-v1.0.0
git push origin infra-v1.0.0
```

## Secrets Management

Secrets are stored in GCP Secret Manager and synced to Kubernetes via External Secrets Operator:
- `ems-db-password`
- `ems-db-user`
- `ems-db-name`
- `ems-db-host`
- `ems-jwt-secret`
- `ems-redis-password`
- `ems-openai-api-key`

To update a secret:
```bash
gcloud secrets versions add ems-db-password --data-file=- <<< "new-password"
```

## Common Commands

```bash
# Get cluster credentials
gcloud container clusters get-credentials ems-cluster --region us-central1

# List all pods
kubectl get pods -A

# Check ArgoCD apps
kubectl get application -n argocd

# Sync all apps via ArgoCD CLI
argocd app sync --all

# Watch event-service rollout
kubectl argo rollouts get rollout event-service -n event-service --watch

# Rollback event-service
kubectl argo rollouts undo event-service -n event-service
```

## Terraform State

State is stored in GCS bucket: `ems-terraform-state`
