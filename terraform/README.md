# EMS Platform - Infrastructure as Code

Deploy EMS Platform lên Oracle Cloud và GCP sử dụng Terraform.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              EMS PLATFORM                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ORACLE CLOUD                              │  GOOGLE CLOUD                  │
│  ─────────────────────                     │  ──────────────                 │
│                                            │                                  │
│  ┌─────────────────────────────────┐     │  ┌─────────────────────────┐   │
│  │  ems-primary                    │     │  │  Cloud SQL (PostgreSQL) │   │
│  │  - Docker                       │────▶│  │  - ems_events DB       │   │
│  │  - Superset                     │     │  │  - Airflow DB          │   │
│  │  - Airflow                      │     │  └─────────────────────────┘   │
│  │  - Nginx (SSL)                 │     │                                  │
│  │  - MinIO                       │     │  ┌─────────────────────────┐   │
│  └─────────────────────────────────┘     │  │  Memorystore (Redis)   │   │
│                                          │  │  - Cache               │   │
│  ┌─────────────────────────────────┐     │  └─────────────────────────┘   │
│  │  ems-kafka                      │     │                                  │
│  │  - Kafka (KRaft mode)           │     │  ┌─────────────────────────┐   │
│  │  - Kafka UI                     │     │  │  Cloud Storage          │   │
│  └─────────────────────────────────┘     │  │  - Backups              │   │
│                                          │  │  - Datalake             │   │
│  ┌─────────────────────────────────┐     │  └─────────────────────────┘   │
│  │  Object Storage                  │     │                                  │
│  │  - Backups                       │     │                                  │
│  └─────────────────────────────────┘     │                                  │
│                                          │                                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Tools Required

```bash
# Install Terraform
brew install terraform          # macOS
# hoặc download từ https://terraform.io

# Install OCI CLI (Oracle Cloud)
brew install oci-cli            # macOS

# Install GCP CLI
brew install google-cloud-sdk   # macOS
# hoặc download từ https://cloud.google.com/sdk

# Install jq (for scripts)
brew install jq
```

### Cloud Accounts

1. **Oracle Cloud** - Always Free Tier
   - Đăng ký: https://www.oracle.com/cloud/free/
   - Cần: Tenancy OCID, User OCID

2. **GCP** - $300 Free Credits
   - Đăng ký: https://console.cloud.google.com
   - Cần: Project ID, Billing Account

## Quick Start

### 1. Setup Credentials

```bash
# Oracle Cloud OCI CLI
oci session authenticate --region ap-singapore-1

# GCP CLI
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```

### 2. Configure Variables

```bash
# Oracle Cloud
cp terraform/oracle/terraform.tfvars.example terraform/oracle/terraform.tfvars
# Chỉnh sửa terraform/oracle/terraform.tfvars với:
# - tenancy_ocid
# - user_ocid
# - ssh_public_key

# GCP
cp terraform/gcp/terraform.tfvars.example terraform/gcp/terraform.tfvars
# Chỉnh sửa terraform/gcp/terraform.tfvars với:
# - project_id
# - db_password
```

### 3. Deploy

```bash
# Deploy toàn bộ
cd terraform
./scripts/deploy.sh all

# Hoặc deploy từng phần
./scripts/deploy.sh oracle   # Oracle Cloud trước
./scripts/deploy.sh gcp      # Sau đó GCP

# Deploy services lên VM
./scripts/deploy.sh provision
./scripts/deploy.sh services
```

## Deployment Steps

### Step 1: Oracle Cloud

```bash
cd terraform/oracle

# Initialize
terraform init

# Plan
terraform plan -var-file="terraform.tfvars"

# Apply
terraform apply -var-file="terraform.tfvars"
```

**Outputs:**
- `primary_vm_ip` - IP của Primary VM
- `kafka_vm_ip` - IP của Kafka VM
- `backup_bucket` - Object Storage Bucket

### Step 2: GCP

```bash
cd terraform/gcp

# Initialize
terraform init

# Plan (cần Oracle VM IP)
terraform plan -var-file="terraform.tfvars" -var="oracle_vm_ip=xxx.xxx.xxx.xxx"

# Apply
terraform apply -var-file="terraform.tfvars" -var="oracle_vm_ip=xxx.xxx.xxx.xxx"
```

**Outputs:**
- `postgres_ip` - PostgreSQL IP
- `redis_ip` - Redis IP
- `backup_bucket` - Storage Bucket
- `service_account_email` - Service Account cho deploy

### Step 3: Provision VMs

```bash
# SSH vào Primary VM và chạy
./scripts/provision-vm.sh
```

### Step 4: Deploy Services

```bash
# Copy files lên VM
scp -i ~/.ssh/id_rsa docker-compose.prod.yml ubuntu@VM_IP:/home/ubuntu/
scp -i ~/.ssh/id_rsa .env ubuntu@VM_IP:/home/ubuntu/

# SSH vào VM và deploy
ssh -i ~/.ssh/id_rsa ubuntu@VM_IP
cd /home/ubuntu
docker compose up -d
```

## Service URLs

Sau khi deploy thành công:

| Service | URL | Default Login |
|---------|-----|---------------|
| Superset | http://VM_IP:8088 | admin / admin123 |
| Airflow | http://VM_IP:8085 | admin / admin123 |
| Kafka UI | http://VM_IP:8090 | - |
| Portainer | http://VM_IP:9000 | admin / admin123 |
| MinIO | http://VM_IP:9001 | minioadmin / minioadmin123 |

## Cost Estimation

### Always Free (Không tốn tiền)

| Resource | Oracle | GCP |
|----------|--------|-----|
| VMs | 2x (Always Free) | - |
| PostgreSQL | - | 1x (f1-micro) |
| Redis | - | 1GB Basic |
| Object Storage | 10GB | 5GB |
| Load Balancer | 1x | - |
| **Total** | **$0** | **$0** |

### With Credits

Với $400 SGD Oracle + $300 GCP:
- Tất cả resources trên
- Plus: Larger VMs, More storage, HA options
- Ước tính: 6-12 tháng miễn phí

## Maintenance

### Update Infrastructure

```bash
cd terraform/oracle
terraform apply -var-file="terraform.tfvars"

cd terraform/gcp
terraform apply -var-file="terraform.tfvars"
```

### Update Services

```bash
ssh ubuntu@VM_IP
cd /home/ubuntu
docker compose pull
docker compose up -d
```

### Backup

```bash
# PostgreSQL Backup
pg_dump -h $DB_HOST -U emsuser ems_events > backup_$(date +%Y%m%d).sql

# MinIO Backup
mc mirror minio/warehouse minio-backup/
```

## Troubleshooting

### Oracle Cloud Issues

```bash
# Check OCI CLI
oci session validate

# Check compartment
oci iam compartment get --compartment-id $COMPARTMENT_OCID
```

### GCP Issues

```bash
# Check gcloud
gcloud auth list
gcloud config list project

# Check APIs enabled
gcloud services list --enabled
```

### VM Issues

```bash
# SSH debug
ssh -v -i ~/.ssh/id_rsa ubuntu@VM_IP

# Check Docker
docker ps
docker logs <container_name>

# Check system
sudo systemctl status docker
sudo journalctl -u docker -n 50
```

## Destroy Resources

```bash
# GCP (trước)
cd terraform/gcp
terraform destroy -var-file="terraform.tfvars"

# Oracle Cloud (sau)
cd terraform/oracle
terraform destroy -var-file="terraform.tfvars"
```

## CI/CD - GitHub Actions

### Auto-Deploy Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Push to   │────▶│  GitHub    │────▶│ Terraform  │────▶│  Deploy    │
│   GitHub    │     │  Actions   │     │   Plan     │     │  Services   │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
                         │                   │
                         ▼                   ▼
                   ┌─────────────┐     ┌─────────────┐
                   │   PR/MR    │     │  Auto Apply │
                   │   Review   │     │  on Main   │
                   └─────────────┘     └─────────────┘
```

### GitHub Secrets Required

Cài đặt trong GitHub → Settings → Secrets and variables → Actions:

#### Oracle Cloud
| Secret | Description |
|--------|-------------|
| `OCI_TENANCY_OCID` | Oracle Cloud Tenancy OCID |
| `OCI_USER_OCID` | Oracle Cloud User OCID |
| `OCI_FINGERPRINT` | API Key Fingerprint |
| `OCI_PRIVATE_KEY` | Private Key (base64 encoded) |
| `OCI_REGION` | Region (e.g., ap-singapore-1) |

#### Google Cloud
| Secret | Description |
|--------|-------------|
| `GCP_CREDENTIALS` | Service Account JSON (base64 encoded) |

#### Deployment
| Secret | Description |
|--------|-------------|
| `SSH_PRIVATE_KEY` | Private SSH Key for VM access |
| `DB_PASSWORD` | PostgreSQL password |

#### GitHub Variables
Cài đặt trong GitHub → Settings → Secrets and variables → Actions → Variables:

| Variable | Description |
|----------|-------------|
| `PRIMARY_VM_IP` | Oracle VM Public IP |
| `VM_HOST` | VM hostname |
| `DOMAIN` | Domain name |
| `DISCORD_WEBHOOK` | Discord webhook URL |
| `SLACK_WEBHOOK_URL` | Slack webhook URL |

### Workflows

#### terraform-plan.yml
- Chạy trên **mọi PR** vào main
- Tự động comment plan vào PR
- Kiểm tra format, validate

#### terraform-apply.yml
- Chạy khi **push vào main**
- Tự động apply Terraform
- Deploy services lên VMs
- Gửi notification

#### docker-deploy.yml
- Chạy khi có **code changes** trong docker/ hoặc apps/
- Build Docker images
- Deploy lên VM
- Run health checks

### Setup GitHub Secrets

```bash
# 1. Encode OCI Private Key
base64 -i /path/to/oci_api_key.pem | pbcopy

# 2. Encode GCP Credentials
base64 -i /path/to/gcp-credentials.json | pbcopy

# 3. Add Secrets via GitHub CLI
gh secret set OCI_TENANCY_OCID --body "ocid1.tenancy.oc1.xxx"
gh secret set OCI_USER_OCID --body "ocid1.user.oc1.xxx"
gh secret set OCI_FINGERPRINT --body "xx:xx:xx:xx:xx"
gh secret set OCI_PRIVATE_KEY --body "$(cat /path/to/key.pem | base64)"
gh secret set GCP_CREDENTIALS --body "$(cat /path/to/gcp.json | base64)"
gh secret set SSH_PRIVATE_KEY --body "$(cat ~/.ssh/id_rsa | base64)"

# 4. Add Variables
gh variable set PRIMARY_VM_IP --body "xxx.xxx.xxx.xxx"
gh variable set VM_HOST --body "ems.yourdomain.com"
```

### Workflow History

Xem deployment history trong GitHub → Actions tab:

```
GitHub → Your Repo → Actions
├── Terraform CI          # PR checks
├── Terraform Deploy      # Main branch deploys
└── Deploy Services       # Code deploys
```

## License

MIT
