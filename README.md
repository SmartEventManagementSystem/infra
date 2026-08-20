# EMS Infrastructure

Kubernetes manifests for EMS platform deployment on minikube.

## Prerequisites

```bash
# Install tools
brew install kubectl helm minikube kustomize

# Start minikube
minikube start --driver=docker --cpus=6 --memory=12g --disk-size=80g

# Enable addons
minikube addons enable ingress
minikube addons enable metrics-server
```

## Quick Start

```bash
# Apply all manifests
kubectl apply -k .

# Or use the setup script
chmod +x setup-minikube.sh
./setup-minikube.sh
```

## Services

| Service | Namespace | Port | Description |
|---------|-----------|------|-------------|
| Event Service | event-service | 8080 | Core event API |
| AI Service | ai-service | 8081 | AI/RAG services |
| Web Client | web-client | 80 | Frontend |
| ArgoCD | argocd | 8080 | GitOps dashboard |
| Argo Rollouts | argo-rollouts | 3100 | Progressive delivery |

## Access

```bash
# Add to /etc/hosts
echo "127.0.0.1 argocd.local" | sudo tee -a /etc/hosts
echo "127.0.0.1 api-events.ems.local" | sudo tee -a /etc/hosts
echo "127.0.0.1 api-ai.ems.local" | sudo tee -a /etc/hosts
echo "127.0.0.1 web.ems.local" | sudo tee -a /etc/hosts

# ArgoCD UI
# URL: https://argocd.local
# User: admin
# Pass: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d

# Argo Rollouts Dashboard
kubectl port-forward -n argo-rollouts svc/argo-rollouts-dashboard 3100:3100
```

## ArgoCD Setup

```bash
# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.0/notifications.yaml
helm repo add argo https://argoproj.github.io/argo-helm
helm upgrade --install argocd argo/argo-cd -n argocd

# Install Argo Rollouts
kubectl create namespace argo-rollouts
kubectl apply -f https://github.com/argoproj/argo-rollouts/releases/download/v1.8.2/install.yaml
```

## Rollout Strategy

### Event Service (Canary)
```
5% → 1m pause → 20% → 2m pause → 50% → 2m pause → 80% → 1m pause → 100%
```

### AI Service (Blue-Green)
```
Active: production traffic
Preview: canary testing
Auto-promotion: disabled (manual approval)
```

## Environment

| Variable | Description |
|----------|-------------|
| `DB_HOST` | PostgreSQL host |
| `KAFKA_BROKERS` | Kafka brokers |
| `REDIS_HOST` | Redis host |
| `AI_SERVICE_URL` | AI service endpoint |

## License

MIT
