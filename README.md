# EMS Platform - Infrastructure

Infrastructure as Code và CI/CD cho EMS Platform deployment.

## CI/CD Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  SERVICE REPOS                    │  INFRA REPO                             │
│  ─────────────────────────────────│──────────────────────────────────────│
│                                   │                                        │
│  web-client/ ──── Build ────▶  │  ghcr.io/.../web-client:v1.0.0        │
│  ai-platform/ ──── Build ────▶ │  ghcr.io/.../ai-service:v1.0.0         │
│  event-service/ ── Build ────▶  │  ghcr.io/.../event-service:v1.0.0     │
│                                   │                                        │
│                                   │         ┌─────────────────────┐       │
│                                   │         │  Production VM      │       │
│                                   │         │  Pull from GHCR     │       │
│                                   │         │  docker compose up  │       │
│                                   │         └─────────────────────┘       │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Deployment Flow

### Step 1: Service Repos → Build & Push to GHCR

Mỗi service repo tự build và push lên GHCR:

| Repo | Image |
|------|-------|
| web-client | ghcr.io/smarteventmanagementsystem/web-client |
| ai-platform | ghcr.io/smarteventmanagementsystem/ai-service |
| event-service-platform | ghcr.io/smarteventmanagementsystem/event-service |

### Step 2: Infra Repo → Pull & Deploy

Push tag trong infra repo để deploy:

```bash
git tag v1.0.0
git push origin v1.0.0
```

## GitHub Setup

### Variables (Settings → Variables → Actions)

```bash
gh variable set VM_HOST --body "your-vm-ip"
gh variable set DB_HOST --body "gcp-cloud-sql-ip"
gh variable set REDIS_HOST --body "gcp-redis-ip"
gh variable set KAFKA_BROKERS --body "kafka:29092"
```

### Secrets (Settings → Secrets → Actions)

```bash
gh secret set SSH_PRIVATE_KEY --body "$(cat ~/.ssh/id_rsa | base64)"
gh secret set DB_USER --body "your_db_user"
gh secret set DB_PASSWORD --body "your_db_password"
gh secret set DB_NAME --body "ems_events"
gh secret set REDIS_PASSWORD --body "your_redis_password"
gh secret set JWT_SECRET --body "generate-with-openssl-rand-base64-32"
```

## Services

| Service | Port | URL |
|---------|------|-----|
| Nginx Proxy Manager UI | 81 | http://VM_IP:81 |
| Web Client | 3000 | http://VM_IP |
| Event Service | 8080 | http://VM_IP:8080 |
| AI Service | 8081 | http://VM_IP:8081 |
| Kafka UI | 8090 | http://VM_IP:8090 |
| PostgreSQL | 5432 | Internal |
| Redis | 6379 | Internal |
| Kafka | 9092 | Internal |

## Setup VM

```bash
# SSH vào VM
ssh ubuntu@vm-ip

# Clone repo
git clone https://github.com/SmartEventManagementSystem/infra.git
cd infra/terraform/oracle

# Setup environment
cp .env.example .env
nano .env  # Edit with real values

# Start services
docker compose up -d

# Check status
docker ps
```

## Nginx Proxy Manager

Sau khi deploy, setup proxy hosts qua UI:

1. Mở http://VM_IP:81
2. Login: admin@example.com / changeme
3. Proxy Hosts → Add Proxy Host
4. Thêm domain vào DNS trỏ về VM_IP
