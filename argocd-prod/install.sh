#!/bin/bash
# ============================================
# ArgoCD Installation for Production
# Deploys ArgoCD on the production VM
# ============================================

set -e

NAMESPACE="argocd"
DOMAIN="argocd.$DOMAIN"

echo "Installing ArgoCD..."

# Create namespace
kubectl create namespace argocd || true

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
echo "Waiting for ArgoCD to be ready..."
kubectl wait --namespace argocd \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=argocd-server \
  --timeout=300s

# Get initial password
ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "=========================================="
echo "   ArgoCD Installed Successfully!        "
echo "=========================================="
echo ""
echo "URL: https://$DOMAIN"
echo "Username: admin"
echo "Password: $ADMIN_PASSWORD"
echo ""
echo "To change password:"
echo "  argocd account update-password"
echo ""
echo "To install CLI:"
echo "  brew install argocd"
echo ""

# Create Ingress (optional)
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-ingress
  namespace: argocd
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - $DOMAIN
      secretName: argocd-tls
  rules:
    - host: $DOMAIN
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 443
EOF

echo "✅ ArgoCD setup complete!"
