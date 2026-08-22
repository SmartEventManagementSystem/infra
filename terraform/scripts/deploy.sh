#!/bin/bash
# ============================================
# EMS Platform - Production Deployment Script
# Deploys infrastructure using Terraform
# ============================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"

# ============================================
# FUNCTIONS
# ============================================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform not found. Install from https://terraform.io"
        exit 1
    fi

    # Check AWS CLI (for Oracle OCI)
    if ! command -v oci &> /dev/null; then
        log_warn "OCI CLI not found. Install from https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm"
    fi

    # Check GCP CLI
    if ! command -v gcloud &> /dev/null; then
        log_warn "GCP CLI not found. Install from https://cloud.google.com/sdk"
    fi

    log_info "Prerequisites check complete"
}

# ============================================
# DEPLOY ORACLE CLOUD
# ============================================

deploy_oracle() {
    log_info "Deploying Oracle Cloud Infrastructure..."

    cd "${TERRAFORM_DIR}/oracle"

    # Initialize Terraform
    terraform init

    # Plan
    terraform plan \
        -var-file="terraform.tfvars" \
        -out="terraform.tfplan"

    # Apply
    read -p "Apply Oracle Cloud changes? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        terraform apply "terraform.tfplan"

        # Get outputs
        ORACLE_VM_IP=$(terraform output -raw primary_vm_ip)
        ORACLE_KAFKA_IP=$(terraform output -raw kafka_vm_ip)

        echo ""
        log_info "Oracle Cloud deployed!"
        log_info "Primary VM IP: ${ORACLE_VM_IP}"
        log_info "Kafka VM IP: ${ORACLE_KAFKA_IP}"
    fi

    cd "${PROJECT_ROOT}"
}

# ============================================
# DEPLOY GCP
# ============================================

deploy_gcp() {
    log_info "Deploying GCP Infrastructure..."

    cd "${TERRAFORM_DIR}/gcp"

    # Authenticate
    if ! gcloud auth print-access-token &> /dev/null; then
        log_info "Please authenticate with GCP:"
        gcloud auth login
    fi

    # Set project
    gcloud config set project $(terraform show -json | jq -r '.variables.project_id.value')

    # Initialize Terraform
    terraform init

    # Plan
    terraform plan \
        -var-file="terraform.tfvars" \
        -var="oracle_vm_ip=${ORACLE_VM_IP}" \
        -out="terraform.tfplan"

    # Apply
    read -p "Apply GCP changes? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        terraform apply "terraform.tfplan"

        # Get outputs
        GCP_POSTGRES_IP=$(terraform output -raw postgres_ip)
        GCP_REDIS_IP=$(terraform output -raw redis_ip)
        GCP_BUCKET=$(terraform output -raw backup_bucket)

        echo ""
        log_info "GCP deployed!"
        log_info "PostgreSQL IP: ${GCP_POSTGRES_IP}"
        log_info "Redis IP: ${GCP_REDIS_IP}"
        log_info "Backup Bucket: ${GCP_BUCKET}"
    fi

    cd "${PROJECT_ROOT}"
}

# ============================================
# PROVISION VMs
# ============================================

provision_vms() {
    log_info "Provisioning VMs with Docker and Apps..."

    if [ -z "${ORACLE_VM_IP}" ]; then
        log_error "Oracle VM IP not set. Run deploy_oracle first."
        exit 1
    fi

    # Install Docker on Primary VM
    log_info "Installing Docker on Primary VM..."
    ssh -o StrictHostKeyChecking=no -i "${SSH_KEY}" ubuntu@${ORACLE_VM_IP} << 'ENDSSH'
        # Update system
        sudo apt update && sudo apt upgrade -y

        # Install Docker
        curl -fsSL https://get.docker.com | sh
        sudo usermod -aG docker ubuntu

        # Install Docker Compose
        sudo apt install -y docker-compose

        # Install Caddy
        docker run -d \
            --name caddy \
            --restart always \
            -p 80:80 \
            -p 443:443 \
            -v /home/ubuntu/Caddyfile:/etc/caddy/Caddyfile \
            -v /home/ubuntu/caddy_data:/data \
            abiosoft/caddy:latest

        # Install Portainer
        docker run -d \
            --name portainer \
            --restart always \
            -p 9000:9000 \
            -p 8000:8000 \
            -v /var/run/docker.sock:/var/run/docker.sock \
            portainer/portainer-ce:latest

        echo "Docker installed successfully"
ENDSSH

    # Install Kafka on Kafka VM
    if [ -n "${ORACLE_KAFKA_IP}" ]; then
        log_info "Installing Kafka on Kafka VM..."
        ssh -o StrictHostKeyChecking=no -i "${SSH_KEY}" ubuntu@${ORACLE_KAFKA_IP} << 'ENDSSH'
            # Update system
            sudo apt update && sudo apt upgrade -y

            # Install Java (required for Kafka)
            sudo apt install -y openjdk-17-jre-headless

            # Download and install Kafka
            KAFKA_VERSION="3.6.0"
            curl -sL https://downloads.apache.org/kafka/${KAFKA_VERSION}/kafka_2.13-${KAFKA_VERSION}.tgz -o kafka.tgz
            tar -xzf kafka.tgz -C /opt
            rm kafka.tgz
            ln -s /opt/kafka_2.13-${KAFKA_VERSION} /opt/kafka

            # Create Kafka user
            sudo useradd -r -s /sbin/nologin kafka || true

            # Setup Kafka in KRaft mode (no Zookeeper)
            KAFKA_CLUSTER_ID=$(/opt/kafka/bin/kafka-storage.sh random-uuid)
            /opt/kafka/bin/kafka-storage.sh format -t $KAFKA_CLUSTER_ID -p /var/lib/kafka/data

            # Create systemd service
            sudo tee /etc/systemd/system/kafka.service << 'EOF'
[Unit]
Description=Apache Kafka
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties
ExecStop=/opt/kafka/bin/kafka-server-stop.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

            sudo systemctl daemon-reload
            sudo systemctl enable kafka
            sudo systemctl start kafka

            echo "Kafka installed successfully"
ENDSSH
    fi

    log_info "VMs provisioned successfully!"
}

# ============================================
# DEPLOY EMS SERVICES
# ============================================

deploy_services() {
    log_info "Deploying EMS Services..."

    if [ -z "${ORACLE_VM_IP}" ]; then
        log_error "Oracle VM IP not set."
        exit 1
    fi

    # Create EMS deployment directory
    ssh -o StrictHostKeyChecking=no -i "${SSH_KEY}" ubuntu@${ORACLE_VM_IP} << 'ENDSSH'
        mkdir -p /home/ubuntu/ems-platform
        mkdir -p /home/ubuntu/certs
    ENDSSH

    # Copy docker-compose
    scp -o StrictHostKeyChecking=no -i "${SSH_KEY}" \
        "${PROJECT_ROOT}/docker-compose.prod.yml" \
        ubuntu@${ORACLE_VM_IP}:/home/ubuntu/ems-platform/

    # Copy environment file
    scp -o StrictHostKeyChecking=no -i "${SSH_KEY}" \
        "${PROJECT_ROOT}/.env.production" \
        ubuntu@${ORACLE_VM_IP}:/home/ubuntu/ems-platform/

    # Copy Caddyfile
    scp -o StrictHostKeyChecking=no -i "${SSH_KEY}" \
        "${PROJECT_ROOT}/Caddyfile" \
        ubuntu@${ORACLE_VM_IP}:/home/ubuntu/

    # Start services
    ssh -o StrictHostKeyChecking=no -i "${SSH_KEY}" ubuntu@${ORACLE_VM_IP} << 'ENDSSH'
        cd /home/ubuntu/ems-platform
        docker compose up -d
        echo "EMS Services deployed!"
    ENDSSH

    log_info "Services deployed successfully!"
}

# ============================================
# SHOW STATUS
# ============================================

show_status() {
    echo ""
    echo "=========================================="
    echo "         EMS PLATFORM - DEPLOYED        "
    echo "=========================================="
    echo ""
    echo "ORACLE CLOUD:"
    echo "  Primary VM:   ${ORACLE_VM_IP:-'Not deployed'}"
    echo "  Kafka VM:      ${ORACLE_KAFKA_IP:-'Not deployed'}"
    echo ""
    echo "GCP:"
    echo "  PostgreSQL:    ${GCP_POSTGRES_IP:-'Not deployed'}"
    echo "  Redis:        ${GCP_REDIS_IP:-'Not deployed'}"
    echo "  Bucket:       ${GCP_BUCKET:-'Not deployed'}"
    echo ""
    echo "SERVICES:"
    echo "  Superset:     https://${DOMAIN:-'ems.yourdomain.com'}"
    echo "  Airflow:      https://airflow.${DOMAIN:-'yourdomain.com'}"
    echo "  Kafka UI:     https://kafka.${DOMAIN:-'yourdomain.com'}"
    echo ""
}

# ============================================
# MAIN
# ============================================

main() {
    echo "=========================================="
    echo "    EMS Platform - Production Deploy     "
    echo "=========================================="
    echo ""

    check_prerequisites

    # Parse arguments
    DEPLOY_TARGET="${1:-all}"

    case "${DEPLOY_TARGET}" in
        oracle)
            deploy_oracle
            ;;
        gcp)
            deploy_gcp
            ;;
        provision)
            provision_vms
            ;;
        services)
            deploy_services
            ;;
        all)
            deploy_oracle
            deploy_gcp
            provision_vms
            deploy_services
            show_status
            ;;
        status)
            show_status
            ;;
        destroy)
            log_warn "Destroying all resources..."
            cd "${TERRAFORM_DIR}/gcp" && terraform destroy
            cd "${TERRAFORM_DIR}/oracle" && terraform destroy
            ;;
        *)
            echo "Usage: $0 {oracle|gcp|provision|services|all|destroy|status}"
            exit 1
            ;;
    esac
}

main "$@"
