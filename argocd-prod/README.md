# ============================================
# ArgoCD Setup for Docker Compose (No Kubernetes)
# ============================================

## Option 1: ArgoCD with Docker Runner (Recommended)

ArgoCD có thể sync Docker Compose files thay vì Kubernetes manifests.

### Setup

```bash
# On your VM, install ArgoCD CLI and server
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Or use Docker Compose version
docker run -d \
  --name argocd \
  -p 8080:8080 \
  -p 8081:8081 \
  -v ~/argocd:/data \
  argoproj/argocd:latest
```

### ArgoCD Application for Docker Compose

```yaml
# argocd-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ems-platform
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/SmartEventManagementSystem/infra.git
    targetRevision: main
    path: terraform/oracle
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Option 2: Simple GitOps with Webhooks (No ArgoCD)

Nếu chỉ cần auto-deploy khi push, dùng webhook đơn giản hơn.

### Setup Webhook

```bash
# On VM, create a webhook receiver
cat > /home/ubuntu/webhook-receiver.sh << 'EOF'
#!/bin/bash
read -r event
if [[ "$event" == "push" ]]; then
    cd /home/ubuntu/ems-platform
    git pull
    docker compose pull
    docker compose up -d
fi
EOF
chmod +x /home/ubuntu/webhook-receiver.sh
```

## Option 3: Watchtower (Auto-Update Containers)

Dùng Watchtower để auto-update containers khi image thay đổi.

```yaml
# docker-compose.yml thêm:
watchtower:
  image: containrrr/watchtower
  container_name: watchtower
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock
    - ~/.docker/config.json:/config.json:ro
  command: --interval 300 --include-stopped --pull
  restart: unless-stopped
```

---

## Recommended: GitHub Actions + SSH (Simplest)

Thay vì ArgoCD, dùng GitHub Actions đã setup:

```yaml
# .github/workflows/docker-deploy.yml
# Đã configured sẵn - push lên main = auto deploy
```

### To Enable:

1. Add GitHub Variables:
   ```bash
   gh variable set VM_HOST --body "your-vm-ip"
   ```

2. Add Secrets:
   ```bash
   gh secret set SSH_PRIVATE_KEY --body "$(cat ~/.ssh/id_rsa | base64)"
   ```

3. Push code → Auto deploy!

---

## Quick Start Guide

### Step 1: SSH Access to VM

```bash
# Generate SSH key
ssh-keygen -t rsa -b 4096

# Copy to VM
ssh-copy-id ubuntu@your-vm-ip
```

### Step 2: Setup VM

```bash
ssh ubuntu@your-vm-ip

# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker ubuntu

# Clone repo
git clone https://github.com/SmartEventManagementSystem/infra.git
cd infra/terraform/oracle

# Setup environment
cp .env.example .env
nano .env  # Edit with real values

# Start services
docker compose up -d
```

### Step 3: Setup GitHub Actions

```bash
# Add VM host
gh variable set VM_HOST --body "your-vm-ip"

# Add SSH key
gh secret set SSH_PRIVATE_KEY --body "$(cat ~/.ssh/id_rsa | base64)"
```

---

## Services URLs (After Deployment)

| Service | URL | Default |
|---------|-----|---------|
| Superset | http://VM_IP:8088 | admin/admin123 |
| Airflow | http://VM_IP:8085 | admin/admin123 |
| Kafka UI | http://VM_IP:8090 | - |
| MinIO | http://VM_IP:9001 | minioadmin/minioadmin123 |
| Elasticsearch | http://VM_IP:9200 | elastic/elastic123 |
| Qdrant | http://VM_IP:6333 | - |
| Flink | http://VM_IP:8084 | - |

---

## Troubleshooting

### Can't SSH to VM?

```bash
# Check SSH service
ssh ubuntu@your-vm-ip "sudo systemctl status ssh"

# Check firewall
ssh ubuntu@your-vm-ip "sudo ufw status"
```

### Docker not running?

```bash
ssh ubuntu@your-vm-ip "sudo systemctl start docker"
ssh ubuntu@your-vm-ip "sudo systemctl enable docker"
```

### Containers not starting?

```bash
ssh ubuntu@your-vm-ip
cd ~/ems-platform
docker compose logs --tail=100
docker compose ps
```
