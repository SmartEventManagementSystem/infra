terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oracle = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "oracle" {
  region = var.region
}

# ============================================
# VARIABLES
# ============================================

variable "region" {
  description = "Oracle Cloud region"
  type        = string
  default     = "ap-singapore-1"
}

variable "tenancy_ocid" {
  description = "Oracle Cloud Tenancy OCID"
  type        = string
  sensitive   = true
}

variable "user_ocid" {
  description = "Oracle Cloud User OCID"
  type        = string
  sensitive   = true
}

variable "compartment_ocid" {
  description = "Compartment OCID (usually same as tenancy)"
  type        = string
  default     = ""
}

variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
}

variable "vm_password" {
  description = "Password for VM initial access"
  type        = string
  sensitive   = true
  default     = ""
}

# ============================================
# NETWORK - Virtual Cloud Network
# ============================================

resource "oracle_identityvcn" "ems_vcn" {
  compartment_id = var.tenancy_ocid
  display_name   = "ems-vcn"
  cidr_blocks    = ["10.0.0.0/16"]
  dns_label      = "emsvcn"
}

# Internet Gateway
resource "oracle_networkcore_internet_gateway" "ems_igw" {
  compartment_id = var.tenancy_ocid
  vcn_id        = oracle_identityvcn.ems_vcn.id
  display_name  = "ems-internet-gateway"
  enabled       = true
}

# Route Table
resource "oracle_network routing_table" "ems_route_table" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oracle_identityvcn.ems_vcn.id
  display_name   = "ems-route-table"

  route_rules {
    destination     = "0.0.0.0/0"
    network_entity_id = oracle_networkcore_internet_gateway.ems_igw.id
  }
}

# Public Subnet (for VMs)
resource "oracle_identity_subnet" "ems_public_subnet" {
  compartment_id            = var.tenancy_ocid
  vcn_id                   = oracle_identityvcn.ems_vcn.id
  display_name             = "ems-public-subnet"
  cidr_blocks             = ["10.0.1.0/24"]
  route_table_id           = oracle_network routing_table.ems_route_table.id
  security_list_ids        = [oracle_network_security_list.ems_security_list.id]
  dns_label               = "empspublic"
  prohibit_public_ip_on_vnic = false
}

# Security List
resource "oracle_network_security_list" "ems_security_list" {
  compartment_id = var.tenancy_ocid
  vcn_id        = oracle_identityvcn.ems_vcn.id
  display_name  = "ems-security-list"

  ingress_security_rules {
    stateless = false
    protocol  = "all"
    source    = "0.0.0.0/0"
  }

  egress_security_rules {
    stateless = false
    protocol  = "all"
    destination = "0.0.0.0/0"
  }
}

# ============================================
# COMPUTE - Primary VM (Apps)
# ============================================

resource "oracle_compute_instance" "ems_primary" {
  compartment_id = var.tenancy_ocid
  display_name   = "ems-primary"

  shape = "VM.Standard.A1.Flex"
  shape_config {
    ocpus         = 1
    memory_in_gbs = 6
  }

  source_image_id = data.oracle_compute_image.ubuntu_22_04.id
  subnet_id       = oracle_identity_subnet.ems_public_subnet.id

  assign_public_ip = true
  hostname_label   = "ems-primary"

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data            = base64encode(file("${path.module}/cloud-init.yaml"))
  }

  preserve_boot_volume = false

  timeouts {
    create = "60m"
  }
}

# Boot Volume for Primary VM
resource "oracle_blockstorage_boot_volume" "ems_primary_boot" {
  compartment_id = var.tenancy_ocid
  availability_domain = local.availability_domain
  size_in_gbs         = 50
  display_name        = "ems-primary-boot-volume"

  backup_policy_id = data.oracle_blockstorage_boot_volume_backups.ems_default_backup[0].id
}

resource "oracle_compute_instance" "ems_primary_with_boot" {
  count = 1

  compartment_id = var.tenancy_ocid
  display_name   = "ems-primary"

  shape = "VM.Standard.A1.Flex"
  shape_config {
    ocpus         = 1
    memory_in_gbs = 6
  }

  source_image_id = data.oracle_compute_image.ubuntu_22_04.id
  boot_volume_id  = oracle_blockstorage_boot_volume.ems_primary_boot[0].id
  subnet_id       = oracle_identity_subnet.ems_public_subnet.id

  assign_public_ip = true
  hostname_label   = "ems-primary"

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }
}

# ============================================
# COMPUTE - Kafka VM
# ============================================

resource "oracle_compute_instance" "ems_kafka" {
  compartment_id = var.tenancy_ocid
  display_name   = "ems-kafka"

  shape = "VM.Standard.E2.1.Micro"  # Always Free
  source_image_id = data.oracle_compute_image.ubuntu_22_04.id
  subnet_id       = oracle_identity_subnet.ems_public_subnet.id

  assign_public_ip = true
  hostname_label   = "ems-kafka"

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(file("${path.module}/cloud-init.yaml"))
  }
}

# ============================================
# OBJECT STORAGE
# ============================================

resource "oracle_objectstorage_bucket" "ems_backups" {
  compartment_id = var.tenancy_ocid
  namespace      = data.oracle_objectstorage_namespace.ems_ns.namespace
  bucket         = "ems-backups"
  storage_tier   = "Standard"

  access_type = "NoPublicAccess"

  lifecycle_policy {
    rules {
      action     = "DELETE"
      time_type  = "DAYS_AFTER_MODIFIED"
      days       = 30
    }
  }
}

# ============================================
# LOAD BALANCER
# ============================================

resource "oracle_loadbalancer_loadbalancer" "ems_lb" {
  compartment_id = var.tenancy_ocid
  display_name   = "ems-load-balancer"
  shape           = "100Mbps"
  subnet_ids      = [oracle_identity_subnet.ems_public_subnet.id]

  ip_mode = "IPV4"

  frontends {
    name       = "ems-http"
    port       = 80
    protocol   = "HTTP"
  }

  frontends {
    name       = "ems-https"
    port       = 443
    protocol   = "TCP"
  }

  backendsets {
    name            = "ems-backend"
    protocol        = "HTTP"
    load_balancing_policy = "ROUND_ROBIN"

    health_checker {
      protocol    = "HTTP"
      port        = 80
      url_path    = "/health"
      interval_ms = 10000
      timeout_ms  = 5000
      retries     = 3
    }
  }

  rules {
    name = "ems-listener-rule"
    condition = "TRUE"
    actions {
      type = "ADD_HTTP_REQUEST_HEADER"
      name = "X-Forwarded-Proto"
      value = "https"
    }
  }
}

# ============================================
# OUTPUTS
# ============================================

output "primary_vm_ip" {
  description = "Primary VM Public IP"
  value       = oracle_compute_instance.ems_primary_with_boot[0].public_ip
}

output "kafka_vm_ip" {
  description = "Kafka VM Public IP"
  value       = oracle_compute_instance.ems_kafka.public_ip
}

output "vcn_id" {
  description = "VCN ID"
  value       = oracle_identityvcn.ems_vcn.id
}

output "subnet_id" {
  description = "Public Subnet ID"
  value       = oracle_identity_subnet.ems_public_subnet.id
}

output "backup_bucket" {
  description = "Backup Bucket Name"
  value       = oracle_objectstorage_bucket.ems_backups.name
}

output "load_balancer_ip" {
  description = "Load Balancer IP"
  value       = oracle_loadbalancer_loadbalancer.ems_lb.ip_addresses[0]
}

# ============================================
# DATA SOURCES
# ============================================

data "oracle_compute_image" "ubuntu_22_04" {
  compartment_id = var.tenancy_ocid
  shape         = "VM.Standard.A1.Flex"

  operating_system      = "Canonical Ubuntu"
  operating_system_version = "22.04"
}

data "oracle_objectstorage_namespace" "ems_ns" {
  tenancy_id = var.tenancy_ocid
}

data "oracle_blockstorage_boot_volume_backups" "ems_default_backup" {
  count = 0
  compartment_id = var.tenancy_ocid
  boot_volume_id = oracle_blockstorage_boot_volume.ems_primary_boot.id
}

locals {
  availability_domain = "FHCD:AP-SINGAPORE-1-AD-1"
}
