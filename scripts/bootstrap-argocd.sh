#!/bin/bash
# ArgoCD Bootstrap Script
# Run this AFTER terraform apply creates the GKE cluster

set -euo pipefail

NAMESPACE="argocd"
ROOT_APP="infra/argocd/root-app.yaml"

echo "=== ArgoCD Bootstrap ==="

# 1. Get cluster credentials
echo "[1/6] Configuring kubectl..."
gcloud container clusters get-credentials ems-cluster --region "${GCP_REGION:-us-central1}"

# 2. Install cert-manager CRDs first (required before deploying cert-manager)
echo "[2/6] Installing cert-manager CRDs..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.3/cert-manager.crds.yaml

# 3. Apply networking layer (cert-manager + ingress-nginx)
echo "[3/6] Deploying networking layer..."
kubectl apply -k manifests/networking

# 4. Apply ArgoCD bootstrap
echo "[4/6] Deploying ArgoCD..."
kubectl apply -f argocd/bootstrap/

# 5. Wait for ArgoCD to be ready
echo "[5/6] Waiting for ArgoCD to be ready..."
kubectl wait --namespace "$NAMESPACE" \
  --for=condition=ready pod \
  -l app=argocd-server \
  --timeout=300s

# 6. Get admin password
echo "[6/6] ArgoCD admin password:"
kubectl -n "$NAMESPACE" get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d

# 7. Apply root app (creates all child apps)
echo ""
echo "Applying root app..."
kubectl apply -f "$ROOT_APP"

echo ""
echo "=== ArgoCD is ready! ==="
echo "Port-forward to access UI:"
echo "  kubectl port-forward svc/argocd-server -n $NAMESPACE 8080:443"
echo ""
echo "Then open: https://localhost:8080"
echo "Username: admin"
echo ""
echo "List apps:"
echo "  argocd app list"
