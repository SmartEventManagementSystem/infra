terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ============================================
# ENABLE APIS
# ============================================

resource "google_project_service" "apis" {
  for_each = toset([
    "container.googleapis.com",
    "compute.googleapis.com",
    "sqladmin.googleapis.com",
    "redis.googleapis.com",
    "storage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "vpcaccess.googleapis.com",
  ])

  service            = each.key
  disable_on_destroy = false
}

# ============================================
# VPC NETWORK
# ============================================

resource "google_compute_network" "ems_vpc" {
  name                    = "ems-vpc"
  auto_create_subnetworks = false
  mtu                     = 1460
  description             = "EMS Platform VPC"
}

resource "google_compute_subnetwork" "ems_nodes" {
  name             = "ems-nodes"
  network          = google_compute_network.ems_vpc.id
  ip_cidr_range    = var.vpc_cidr
  region           = var.region

  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "ems-pods"
    ip_cidr_range = var.pod_cidr
  }
  secondary_ip_range {
    range_name    = "ems-services"
    ip_cidr_range = var.svc_cidr
  }
}

# ============================================
# CLOUD NAT (for private nodes to reach internet)
# ============================================

resource "google_compute_address" "nat_ip" {
  name         = "ems-nat-ip"
  region       = var.region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
}

resource "google_compute_router" "ems_router" {
  name    = "ems-router"
  network = google_compute_network.ems_vpc.id
  region  = var.region

  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "ems_nat" {
  name                               = "ems-nat"
  router                             = google_compute_router.ems_router.name
  region                             = var.region
  nat_ip_allocate_option              = "MANUAL_ONLY"
  nat_ips                            = [google_compute_address.nat_ip.self_link]
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  min_ports_per_vm = 128

  log_config {
    enable_logging = true
    filter = "ERRORS_ONLY"
  }
}

# ============================================
# PRIVATE SERVICE CONNECT (Cloud SQL)
# ============================================

resource "google_compute_global_address" "ems_sql_private" {
  name          = "ems-sql-private"
  purpose       = "VPC_PEERING"
  address_type = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.ems_vpc.id
  description   = "Private IP range for Cloud SQL"
}

resource "google_service_networking_connection" "ems_sql_vpc" {
  network                 = google_compute_network.ems_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.ems_sql_private.name]

  depends_on = [google_project_service.apis]
}

# ============================================
# GKE SERVICE ACCOUNT + IAM
# ============================================

resource "google_service_account" "gke_nodes" {
  account_id   = "ems-gke-nodes"
  display_name = "EMS GKE Nodes"
}

resource "google_project_iam_member" "gke_nodes_storage" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_secretmanager" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# ============================================
# GKE CLUSTER
# ============================================

resource "google_container_cluster" "ems_cluster" {
  name     = "ems-cluster"
  location = var.region

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  remove_default_node_pool = true
  initial_node_count       = 1

  networking_mode = "VPC_NATIVE"

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "Allow all"
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  vertical_pod_autoscaling {
    enabled = true
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = "04:00"
    }
  }

  cluster_autoscaling {
    autoscaling_profile = "OPTIMIZED_UTILIZATION"

    resource_limits {
      resource_type = "cpu"
      minimum       = 2
      maximum       = 50
    }
    resource_limits {
      resource_type = "memory"
      minimum       = 4
      maximum       = 200
    }
  }

  release_channel {
    channel = "REGULAR"
  }

  depends_on = [
    google_project_service.apis,
    google_service_networking_connection.ems_sql_vpc,
  ]
}

# System Node Pool (ArgoCD, ESO, ingress, cert-manager)
resource "google_container_node_pool" "system_pool" {
  name       = "system-pool"
  location   = var.region
  cluster    = google_container_cluster.ems_cluster.id
  node_count = 2

  node_config {
    machine_type    = var.system_node_machine_type
    disk_size_gb    = 50
    disk_type       = "pd-balanced"
    preemptible     = false
    service_account = google_service_account.gke_nodes.email

    labels = {
      "node-pool" = "system"
      "tier"      = "control"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    metadata = {
      "disable-legacy-endpoints" = "true"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  autoscaling {
    min_node_count = 2
    max_node_count = 3
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}

# App Node Pool (web-client, event-service, ai-service)
resource "google_container_node_pool" "app_pool" {
  name       = "app-pool"
  location   = var.region
  cluster    = google_container_cluster.ems_cluster.id
  node_count = 2

  node_config {
    machine_type    = var.app_node_machine_type
    disk_size_gb    = 100
    disk_type       = "pd-ssd"
    preemptible     = false
    service_account = google_service_account.gke_nodes.email

    labels = {
      "node-pool" = "app"
      "tier"      = "application"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    metadata = {
      "disable-legacy-endpoints" = "true"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  autoscaling {
    min_node_count = 2
    max_node_count = 10
  }

  upgrade_settings {
    max_surge       = 2
    max_unavailable = 1
  }
}

# Data Node Pool (Kafka)
resource "google_container_node_pool" "data_pool" {
  name       = "data-pool"
  location   = var.region
  cluster    = google_container_cluster.ems_cluster.id
  node_count = 1

  node_config {
    machine_type    = var.data_node_machine_type
    disk_size_gb    = 200
    disk_type       = "pd-ssd"
    preemptible     = true
    service_account = google_service_account.gke_nodes.email

    labels = {
      "node-pool" = "data"
      "tier"      = "dataplatform"
    }

    taint = [
      {
        key    = "node-pool"
        value  = "data"
        effect = "NoSchedule"
      }
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# ============================================
# POSTGRESQL - Cloud SQL
# ============================================

resource "google_sql_database_instance" "ems_postgres" {
  name                = "ems-postgres"
  database_version    = "POSTGRES_15"
  region              = var.region

  deletion_protection = false  # Allow destroy

  settings {
    tier              = "db-f1-micro"  # Free tier
    availability_type = "ZONAL"
    disk_size         = 10
    disk_type         = "PD_SSD"

    ip_configuration {
      ipv4_enabled    = false
      private_network  = google_compute_network.ems_vpc.id
      require_ssl      = true
    }

    backup_configuration {
      enabled                        = true
      backup_retention_settings {
        retained_backups = 7
        retention_unit  = "COUNT"
      }
      start_time = "03:00"
    }

    maintenance_window {
      day          = 7
      hour         = 4
      update_track = "stable"
    }
  }
}

resource "google_sql_database" "ems_events" {
  name     = "ems_events"
  instance = google_sql_database_instance.ems_postgres.name
}

resource "google_sql_user" "ems_user" {
  name     = "emsuser"
  instance = google_sql_database_instance.ems_postgres.name
  password = var.db_password
}

# ============================================
# REDIS - Memorystore
# ============================================

resource "google_redis_instance" "ems_redis" {
  name              = "ems-redis"
  memory_size_gb    = 1
  redis_version     = "REDIS_7_0"
  region           = var.region
  tier             = "BASIC"
  display_name     = "ems-redis"

  maintenance_policy {
    weekly_maintenance_window {
      day        = "SUNDAY"
      start_time {
        hours   = 17
        minutes = 0
      }
    }
  }

  redis_configs = {
    maxmemory-policy = "allkeys-lru"
  }
}

# ============================================
# CLOUD STORAGE - Buckets
# ============================================

resource "google_storage_bucket" "ems_backups" {
  name          = "${var.project_id}-ems-backups"
  location      = var.region
  storage_class = "STANDARD"
  force_destroy = true

  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  versioning {
    enabled = true
  }
}

resource "google_storage_bucket" "ems_datalake" {
  name          = "${var.project_id}-ems-datalake"
  location      = var.region
  storage_class = "NEARLINE"
  force_destroy = true

  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_storage_bucket_iam_member" "ems_backups_ai" {
  bucket = google_storage_bucket.ems_backups.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${var.gcp_service_account_email}"
}

# ============================================
# SERVICE ACCOUNT
# ============================================

resource "google_service_account" "ems_deployer" {
  account_id   = "ems-deployer"
  display_name = "EMS Deployer Service Account"
}

resource "google_project_iam_member" "ems_deployer_sql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member   = "serviceAccount:${google_service_account.ems_deployer.email}"
}

resource "google_project_iam_member" "ems_deployer_storage" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member   = "serviceAccount:${google_service_account.ems_deployer.email}"
}

resource "google_project_iam_member" "ems_deployer_redis" {
  project = var.project_id
  role    = "roles/redis.viewer"
  member   = "serviceAccount:${google_service_account.ems_deployer.email}"
}

# ============================================
# OUTPUTS
# ============================================

output "postgres_ip" {
  description = "PostgreSQL Private IP"
  value       = google_sql_database_instance.ems_postgres.private_ip_address
}

output "postgres_connection_name" {
  description = "Cloud SQL Connection Name"
  value       = google_sql_database_instance.ems_postgres.connection_name
}

output "redis_ip" {
  description = "Redis Private IP"
  value       = google_redis_instance.ems_redis.host
}

output "redis_port" {
  description = "Redis Port"
  value       = google_redis_instance.ems_redis.port
}

output "backup_bucket" {
  description = "Backup Bucket Name"
  value       = google_storage_bucket.ems_backups.name
}

output "datalake_bucket" {
  description = "Datalake Bucket Name"
  value       = google_storage_bucket.ems_datalake.name
}

output "deployer_service_account_email" {
  description = "Deployer Service Account Email"
  value       = google_service_account.ems_deployer.email
}

output "gke_cluster_name" {
  description = "GKE Cluster Name"
  value       = google_container_cluster.ems_cluster.name
}

output "gke_cluster_region" {
  description = "GKE Cluster Region"
  value       = google_container_cluster.ems_cluster.location
}

output "gke_cluster_endpoint" {
  description = "GKE Cluster Endpoint"
  value       = google_container_cluster.ems_cluster.endpoint
}

output "gke_service_account_email" {
  description = "GKE Nodes Service Account Email"
  value       = google_service_account.gke_nodes.email
}

output "vpc_network" {
  description = "VPC Network Name"
  value       = google_compute_network.ems_vpc.name
}

output "get_credentials" {
  description = "Command to get cluster credentials"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.ems_cluster.name} --region ${var.region}"
}
