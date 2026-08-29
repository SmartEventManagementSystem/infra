# ============================================================
# EMS Platform — GKE Production Infrastructure
# ============================================================

locals {
  project_number = data.google_project.current.number
  vpc_name       = "ems-vpc"
  cluster_name    = "ems-cluster"
}

data "google_project" "current" {
  project_id = var.project_id
}

# ============================================================
# 1. Enable GCP APIs
# ============================================================
resource "google_project_service" "apis" {
  for_each = toset([
    "container.googleapis.com",
    "compute.googleapis.com",
    "sqladmin.googleapis.com",
    "redis.googleapis.com",
    "storage.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "vpcaccess.googleapis.com",
    "certificatemanager.googleapis.com",
    "dns.googleapis.com",
  ])

  service            = each.key
  disable_on_destroy = false

  depends_on = [google_project_service.apis]
}

# ============================================================
# 2. VPC Network
# ============================================================
resource "google_compute_network" "ems_vpc" {
  name                    = local.vpc_name
  auto_create_subnetworks = false
  mtu                     = 1460
  description             = "EMS Platform VPC"
}

resource "google_compute_subnetwork" "ems_nodes" {
  name          = "ems-nodes"
  network       = google_compute_network.ems_vpc.id
  ip_cidr_range = var.vpc_cidr
  region        = var.region

  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "ems-pods"
    ip_cidr_range = var.pod_cidr
  }
  secondary_ip_range {
    range_name    = "ems-services"
    ip_cidr_range = var.svc_cidr
  }

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling      = 0.5
    metadata           = "INCLUDE_ALL_METADATA"
  }
}

# ============================================================
# 3. Cloud NAT (for private nodes to reach GHCR/GCP APIs)
# ============================================================
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

  enable_logging = true
  log_config {
    filter = "ERRORS_ONLY"
  }
}

# ============================================================
# 4. Private Service Connect (Cloud SQL)
# ============================================================
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

# ============================================================
# 5. VPC Access Connector (for Cloud SQL from pods)
# ============================================================
resource "google_vpc_access_connector" "ems_vpc_connector" {
  name          = "ems-connector"
  region        = var.region
  network       = google_compute_network.ems_vpc.name
  ip_cidr_range = "10.8.0.0/28"
  min_instances  = 2
  max_instances = 10
  machine_type  = "e2-micro"
}

# ============================================================
# 6. Workload Identity Service Account
# ============================================================
resource "google_service_account" "gke_nodes" {
  account_id   = "ems-gke-nodes"
  display_name = "EMS GKE Nodes"
}

resource "google_project_iam_member" "gke_nodes_storage" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member   = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_secretmanager" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member   = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# ============================================================
# 7. GKE Cluster
# ============================================================
resource "google_container_cluster" "ems_cluster" {
  name     = local.cluster_name
  location = var.region

  # Private cluster — control plane is fully private
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block = "172.16.0.0/28"
  }

  # Remove default node pool (managed separately)
  remove_default_node_pool = true
  initial_node_count       = 1

  # VPC-native (alias IP) — requires secondary ranges above
  networking_mode = "VPC_NATIVE"

  # Control plane authorized networks
  master_authorized_networks_config {
    gke_public_endpoint = true
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "Allow all (restrict in production)"
    }
  }

  # Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Vertical Pod Autoscaling
  vertical_pod_autoscaling {
    enabled = true
  }

  # Network Policy (Calico)
  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  # Dataplane v2
  dataplane_v2_enabled = true

  # Maintenance window (4 AM UTC = 11 AM Vietnam)
  maintenance_policy {
    daily_maintenance_window {
      start_time = "04:00"
    }
  }

  # Cluster autoscaling profile
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

  node_pool_auto_repair  = true
  node_pool_auto_upgrade = true

  # Release channel
  release_channel {
    channel = "REGULAR"
  }

  depends_on = [
    google_project_service.apis,
    google_service_networking_connection.ems_sql_vpc,
  ]
}

# ============================================================
# 8. System Node Pool (ArgoCD, ESO, ingress, cert-manager)
# ============================================================
resource "google_container_node_pool" "system_pool" {
  name       = "system-pool"
  location   = var.region
  cluster    = google_container_cluster.ems_cluster.id
  node_count = 2

  node_config {
    machine_type         = var.system_node_machine_type
    disk_size_gb        = 50
    disk_type           = "pd-balanced"
    preemptible          = false
    service_account     = google_service_account.gke_nodes.email

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

# ============================================================
# 9. App Node Pool (web-client, event-service, ai-service)
# ============================================================
resource "google_container_node_pool" "app_pool" {
  name       = "app-pool"
  location   = var.region
  cluster    = google_container_cluster.ems_cluster.id
  node_count = 2

  node_config {
    machine_type     = var.app_node_machine_type
    disk_size_gb     = 100
    disk_type        = "pd-ssd"
    preemptible      = false
    service_account  = google_service_account.gke_nodes.email

    labels = {
      "node-pool" = "app"
      "tier"      = "application"
    }

    taint = []

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

# ============================================================
# 10. Data Node Pool (Kafka)
# ============================================================
resource "google_container_node_pool" "data_pool" {
  name       = "data-pool"
  location   = var.region
  cluster    = google_container_cluster.ems_cluster.id
  node_count = 1

  node_config {
    machine_type     = var.data_node_machine_type
    disk_size_gb     = 200
    disk_type        = "pd-ssd"
    preemptible      = true
    service_account  = google_service_account.gke_nodes.email

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

# ============================================================
# 11. Cloud SQL PostgreSQL 15
# ============================================================
resource "google_sql_database_instance" "ems_postgres" {
  name                = "ems-postgres"
  database_version    = "POSTGRES_15"
  region             = var.region
  deletion_protection = false

  settings {
    tier              = "db-n1-standard-2"
    availability_type = "REGIONAL"
    disk_size         = 50
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.ems_vpc.id
      require_ssl     = true

      authorized_networks {
        name  = "gke-nodes"
        value = var.vpc_cidr
      }
    }

    backup_configuration {
      enabled                        = true
      start_time                    = "03:00"
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
      point_in_time_recovery_enabled = true
    }

    maintenance_window {
      day          = 0
      hour         = 4
      update_track = "stable"
    }

    insights_config {
      query_insights_enabled = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = false
    }

    database_flags {
      name  = "log_connections"
      value = "on"
    }
    database_flags {
      name  = "log_disconnections"
      value = "on"
    }
  }
}

resource "google_sql_database" "ems_events" {
  name     = var.db_name
  instance = google_sql_database_instance.ems_postgres.name
}

resource "google_sql_user" "ems_user" {
  name     = var.db_user
  instance = google_sql_database_instance.ems_postgres.name
  password = var.db_password
}

# ============================================================
# 12. Cloud Memorystore Redis 7
# ============================================================
resource "google_redis_instance" "ems_redis" {
  name              = "ems-redis"
  memory_size_gb    = 2  # Redis instance size
  redis_version     = "REDIS_7_0"
  region           = var.region
  tier             = "STANDARD_HA"
  display_name     = "EMS Redis"

  connectivity_mode = "PRIVATE_SERVICE_ACCESS"

  maintenance_policy {
    weekly_maintenance_window {
      day        = "SUNDAY"
      start_time {
        hours = 17
        minutes = 0
      }
    }
  }

  auth_enabled = length(var.redis_password) > 0 ? true : false
}

# ============================================================
# 13. Cloud Storage Buckets
# ============================================================
resource "google_storage_bucket" "ems_backups" {
  name                        = "${var.project_id}-ems-backups"
  location                    = var.region
  storage_class              = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "inherited"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_storage_bucket" "ems_datalake" {
  name                        = "${var.project_id}-ems-datalake"
  location                    = var.region
  storage_class              = "NEARLINE"
  uniform_bucket_level_access = true
  public_access_prevention    = "inherited"

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
}

# Terraform state bucket (separate from backups)
resource "google_storage_bucket" "ems_terraform_state" {
  name                        = "${var.project_id}-ems-terraform-state"
  location                    = var.region
  storage_class              = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "inherited"

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
}

# ============================================================
# 14. GCP Secret Manager (seed secrets)
# ============================================================
resource "google_secret_manager_secret" "db_password" {
  secret_id = "ems-db-password"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password_v1" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = var.db_password
}

resource "google_secret_manager_secret" "db_user" {
  secret_id = "ems-db-user"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_user_v1" {
  secret      = google_secret_manager_secret.db_user.id
  secret_data = var.db_user
}

resource "google_secret_manager_secret" "db_name" {
  secret_id = "ems-db-name"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_name_v1" {
  secret      = google_secret_manager_secret.db_name.id
  secret_data = var.db_name
}

resource "google_secret_manager_secret" "jwt_secret" {
  secret_id = "ems-jwt-secret"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "jwt_secret_v1" {
  secret      = google_secret_manager_secret.jwt_secret.id
  secret_data = "your_jwt_secret_change_in_production_${random_id.jwt_suffix.hex}"
}

resource "google_secret_manager_secret" "redis_password" {
  secret_id = "ems-redis-password"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "redis_password_v1" {
  secret      = google_secret_manager_secret.redis_password.id
  secret_data = var.redis_password
}

resource "random_id" "jwt_suffix" {
  byte_length = 8
}
