#!/bin/bash
# EMS Infrastructure Setup Script
# Run: chmod +x setup-minikube.sh && ./setup-minikube.sh

set -e

echo "🚀 EMS Infrastructure Setup"
echo "==========================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check prerequisites
command -v minikube >/dev/null 2>&1 || { echo "❌ minikube not found. Install: brew install minikube"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl not found. Install: brew install kubectl"; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "❌ helm not found. Install: brew install helm"; exit 1; }

# Start minikube if not running
if ! minikube status | grep -q "Running"; then
    echo -e "${YELLOW}⚠️  Minikube not running. Starting...${NC}"
    minikube start \
        --driver=docker \
        --cpus=6 \
        --memory=12288 \
        --disk-size=80g \
        --addons=ingress \
        --addons=metrics-server \
        --kubernetes-version=v1.29.0 \
        --profile=ems
else
    echo -e "${GREEN}✅ Minikube is running${NC}"
fi

# Point shell to minikube's docker daemon
echo -e "${YELLOW}📦 Setting up Docker environment for minikube...${NC}"
eval $(minikube docker-env)

# Install ArgoCD via Helm
echo -e "${YELLOW}🔄 Installing ArgoCD...${NC}"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --set server.ingress.enabled=true \
    --set server.ingress.ingressClassName=nginx \
    --set server.ingress.annotations."cert-manager\.io/cluster-issuer"=letsencrypt-prod \
    --set server.ingress.hosts[0]=argocd.local \
    --set server.admin.enabled=true \
    --set server.config.admin.enabled=true \
    --create-namespace \
    --wait

# Install Argo Rollouts
echo -e "${YELLOW}🔄 Installing Argo Rollouts...${NC}"
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install argo-rollouts argo/argo-rollouts \
    --namespace argo-rollouts \
    --set dashboard.ingress.enabled=true \
    --set dashboard.ingress.ingressClassName=nginx \
    --create-namespace \
    --wait

# Install Ingress Nginx
echo -e "${YELLOW}🔄 Installing Ingress Nginx...${NC}"
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx \
    --create-namespace \
    --set controller.service.type=NodePort \
    --wait

# Install Cert Manager
echo -e "${YELLOW}🔄 Installing Cert Manager...${NC}"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml

# Wait for deployments
echo -e "${YELLOW}⏳ Waiting for deployments to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s || true
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argo-rollouts -n argo-rollouts --timeout=300s || true
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=ingress-nginx-controller -n ingress-nginx --timeout=300s || true

# Get ArgoCD admin password
echo ""
echo -e "${GREEN}✅ Setup Complete!${NC}"
echo ""
echo "📋 ArgoCD UI: https://argocd.local (add to /etc/hosts)"
echo "   Admin password: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
echo ""
echo "📋 Argo Rollouts Dashboard: kubectl port-forward -n argo-rollouts svc/argo-rollouts-dashboard 3100:3100"
echo ""
echo "📋 To apply manifests:"
echo "   kubectl apply -k infra/manifests/event-service/"
echo "   kubectl apply -k infra/manifests/ai-service/"
echo ""

# Add hosts entry
if ! grep -q "argocd.local" /etc/hosts 2>/dev/null; then
    echo "127.0.0.1 argocd.local" | sudo tee -a /etc/hosts
    echo "127.0.0.1 api-events.ems.local" | sudo tee -a /etc/hosts
    echo "127.0.0.1 api-ai.ems.local" | sudo tee -a /etc/hosts
    echo "127.0.0.1 web.ems.local" | sudo tee -a /etc/hosts
fi

echo -e "${GREEN}🎉 EMS Infrastructure is ready!${NC}"
