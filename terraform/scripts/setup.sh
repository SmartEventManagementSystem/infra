#!/bin/bash
# ============================================
# EMS Platform - Setup Development Environment
# Install required tools and setup credentials
# ============================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${BLUE}====== $1 ======${NC}"; }

# ============================================
# INSTALL TERRAFORM
# ============================================

install_terraform() {
    log_step "Installing Terraform"

    if command -v terraform &> /dev/null; then
        TERRAFORM_VERSION=$(terraform version | head -1)
        log_info "Terraform already installed: ${TERRAFORM_VERSION}"
        return
    fi

    log_info "Installing Terraform..."

    case "$(uname -s)" in
        Darwin*)
            # macOS
            if command -v brew &> /dev/null; then
                brew install terraform
            else
                log_error "Homebrew not found. Install from https://brew.sh"
                exit 1
            fi
            ;;
        Linux*)
            # Linux
            sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
            wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
            sudo apt-get update && sudo apt-get install terraform
            ;;
    esac

    log_info "Terraform installed: $(terraform version | head -1)"
}

# ============================================
# INSTALL OCI CLI
# ============================================

install_oci() {
    log_step "Installing Oracle Cloud CLI (OCI)"

    if command -v oci &> /dev/null; then
        log_info "OCI CLI already installed: $(oci --version)"
        return
    fi

    log_info "Installing OCI CLI..."

    case "$(uname -s)" in
        Darwin*)
            brew install oci-cli
            ;;
        Linux*)
            bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
            ;;
    esac

    log_info "OCI CLI installed"
}

# ============================================
# INSTALL GCP CLI
# ============================================

install_gcloud() {
    log_step "Installing GCP CLI"

    if command -v gcloud &> /dev/null; then
        log_info "GCP CLI already installed: $(gcloud --version | head -1)"
        return
    fi

    log_info "Installing GCP CLI..."

    case "$(uname -s)" in
        Darwin*)
            brew install google-cloud-sdk
            ;;
        Linux*)
            echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
            curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
            sudo apt-get update && sudo apt-get install -y google-cloud-sdk
            ;;
    esac

    log_info "GCP CLI installed"
}

# ============================================
# INSTALL kubectl
# ============================================

install_kubectl() {
    log_step "Installing kubectl"

    if command -v kubectl &> /dev/null; then
        log_info "kubectl already installed: $(kubectl version --client | head -1)"
        return
    fi

    log_info "Installing kubectl..."

    case "$(uname -s)" in
        Darwin*)
            brew install kubectl
            ;;
        Linux*)
            curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
            sudo install -o root -m 0755 kubectl /usr/local/bin/kubectl
            ;;
    esac

    log_info "kubectl installed"
}

# ============================================
# SETUP OCI CREDENTIALS
# ============================================

setup_oci_credentials() {
    log_step "Oracle Cloud Credentials Setup"

    echo ""
    echo "Bạn cần lấy credentials từ Oracle Cloud Console:"
    echo ""
    echo "1. Login https://cloud.oracle.com"
    echo "2. Profile → My Profile → API Keys"
    echo "3. Add API Key → Download Private Key"
    echo "4. Copy API Key fingerprint"
    echo ""

    read -p "OCI Config Path (default: ~/.oci/config): " OCI_CONFIG
    OCI_CONFIG="${OCI_CONFIG:-$HOME/.oci/config}"

    if [ -f "$OCI_CONFIG" ]; then
        log_info "OCI config found at: $OCI_CONFIG"
        oci session validate --region ap-singapore-1 2>/dev/null && log_info "OCI session valid!" || log_warn "OCI session invalid"
    else
        log_warn "OCI config not found at: $OCI_CONFIG"
        log_info "Tạo config bằng:"
        echo "  oci session authenticate --region ap-singapore-1"
    fi
}

# ============================================
# SETUP GCP CREDENTIALS
# ============================================

setup_gcp_credentials() {
    log_step "GCP Credentials Setup"

    echo ""
    echo "Bạn cần tạo Service Account cho Terraform:"
    echo ""
    echo "1. GCP Console → IAM → Service Accounts"
    echo "2. Create Service Account: terraform-deployer"
    echo "3. Grant roles: Project Editor"
    echo "4. Create Key → Download JSON"
    echo ""

    read -p "GCP Credentials JSON path: " GCP_CREDS

    if [ -n "$GCP_CREDS" ] && [ -f "$GCP_CREDS" ]; then
        log_info "GCP credentials found: $GCP_CREDS"
        export GOOGLE_APPLICATION_CREDENTIALS="$GCP_CREDS"
        gcloud auth activate-service-account --credentials="$GCP_CREDS" 2>/dev/null && \
            log_info "GCP credentials activated!" || \
            log_warn "GCP credentials activation failed"
    else
        log_warn "GCP credentials not provided"
        log_info "Set biến môi trường:"
        echo "  export GOOGLE_APPLICATION_CREDENTIALS=/path/to/credentials.json"
    fi
}

# ============================================
# CREATE TERRAFORM VARIABLES
# ============================================

create_terraform_config() {
    log_step "Creating Terraform Configuration"

    # Oracle Cloud
    ORACLE_TFVARS="${PROJECT_ROOT}/terraform/oracle/terraform.tfvars"
    if [ ! -f "$ORACLE_TFVARS" ]; then
        log_info "Creating Oracle Cloud config..."
        cat > "$ORACLE_TFVARS" << 'EOF'
# Oracle Cloud Configuration
region = "ap-singapore-1"

# Lấy từ Oracle Cloud Console
# Profile → My Profile → API Keys
tenancy_ocid = "ocid1.tenancy.oc1.xxx"
user_ocid = "ocid1.user.oc1.xxx"

# SSH Public Key (tạo với: ssh-keygen -t rsa -b 4096)
ssh_public_key = "ssh-rsa AAAA..."
EOF
        log_info "Created: $ORACLE_TFVARS"
    fi

    # GCP
    GCP_TFVARS="${PROJECT_ROOT}/terraform/gcp/terraform.tfvars"
    if [ ! -f "$GCP_TFVARS" ]; then
        log_info "Creating GCP config..."
        cat > "$GCP_TFVARS" << 'EOF'
# GCP Configuration
project_id = "your-gcp-project-id"
region = "asia-southeast1"

# Database password
db_password = "your-secure-password"

# Oracle VM IP (sau khi deploy Oracle)
oracle_vm_ip = ""
EOF
        log_info "Created: $GCP_TFVARS"
    fi

    # Environment file
    ENV_FILE="${PROJECT_ROOT}/terraform/oracle/.env"
    if [ ! -f "$ENV_FILE" ]; then
        log_info "Creating environment file..."
        cp "${PROJECT_ROOT}/terraform/oracle/.env.example" "$ENV_FILE"
        log_info "Created: $ENV_FILE (edit this file)"
    fi
}

# ============================================
# SHOW NEXT STEPS
# ============================================

show_next_steps() {
    log_step "Setup Complete!"

    echo ""
    echo "=========================================="
    echo "   NEXT STEPS TO DEPLOY EMS PLATFORM     "
    echo "=========================================="
    echo ""
    echo "1. Oracle Cloud Setup:"
    echo "   - Lấy tenancy_ocid, user_ocid từ Oracle Console"
    echo "   - Tạo API Key và upload lên Oracle Cloud"
    echo "   - Edit terraform/oracle/terraform.tfvars"
    echo ""
    echo "2. GCP Setup:"
    echo "   - Tạo Project và enable billing"
    echo "   - Tạo Service Account và download credentials"
    echo "   - Edit terraform/gcp/terraform.tfvars"
    echo ""
    echo "3. Deploy:"
    echo "   cd terraform"
    echo "   ./scripts/deploy.sh all"
    echo ""
    echo "Hoặc deploy từng bước:"
    echo "   ./scripts/deploy.sh oracle    # Deploy Oracle Cloud"
    echo "   ./scripts/deploy.sh gcp      # Deploy GCP"
    echo "   ./scripts/deploy.sh provision # Setup VMs"
    echo "   ./scripts/deploy.sh services  # Deploy Docker services"
    echo ""
    echo "=========================================="
    echo ""
}

# ============================================
# MAIN
# ============================================

main() {
    echo "=========================================="
    echo "   EMS Platform - Infrastructure Setup   "
    echo "=========================================="
    echo ""

    install_terraform
    install_oci
    install_gcloud
    install_kubectl

    create_terraform_config

    # Optional: Setup credentials
    if [ "${1}" == "--setup-credentials" ]; then
        setup_oci_credentials
        setup_gcp_credentials
    fi

    show_next_steps
}

main "$@"
