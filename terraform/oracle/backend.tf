# ============================================
# Terraform Backend Configuration
# Use OCI Object Storage for state management
# ============================================

terraform {
  # Local backend (default for development)
  # Uncomment remote backend for production

  backend "local" {
    path = "terraform.tfstate"
  }

  # Remote backend using OCI Object Storage (for team collaboration)
  # Uncomment and configure for production use:
  #
  # backend "s3" {
  #   endpoint        = "https://objectstorage.ap-singapore-1.oraclecloud.com"
  #   region          = "ap-singapore-1"
  #   bucket          = "ems-terraform-state"
  #   key             = "oracle/terraform.tfstate"
  #   encrypt         = true
  #   access_key      = var.access_key
  #   secret_key      = var.secret_key
  # }
}

# ============================================
# Variables for Remote Backend
# ============================================

variable "access_key" {
  description = "OCI Access Key for Object Storage"
  type        = string
  sensitive   = true
  default     = ""
}

variable "secret_key" {
  description = "OCI Secret Key for Object Storage"
  type        = string
  sensitive   = true
  default     = ""
}

# ============================================
# Terraform Cloud (Alternative)
# Free for small teams
# ============================================

# Add to main.tf:
#
# terraform {
#   cloud {
#     organization = "your-org"
#     workspaces {
#       name = "ems-oracle-cloud"
#     }
#   }
# }
