terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "project-5ca79767-316d-4e68-a56-ems-terraform-state"
    prefix = "gcp"
    project = "project-5ca79767-316d-4e68-a56"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ============================================
# ENABLE APIS
# ============================================

resource "google_project_service" "sql" {
  service            = "sqladmin.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "redis" {
  service            = "redis.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "storage" {
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudresourcemanager" {
  service            = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
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
      ipv4_enabled    = true
      authorized_networks {
        name  = "all"
        value = "0.0.0.0/0"
      }
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
  name           = "ems-redis"
  memory_size_gb = 1
  redis_version  = "REDIS_7_0"
  region         = var.region
  location_id    = "${var.region}-a"  # deprecated but still required

  tier = "BASIC"

  maintenance_policy {
    description = "Auto-upgrade Redis during maintenance window"
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

output "service_account_email" {
  description = "Deployer Service Account Email"
  value       = google_service_account.ems_deployer.email
}

output "service_account_key" {
  description = "Service Account Key (create separately with gcloud)"
  value       = "gcloud iam service-accounts keys create ems-deployer.json --iam-account=${google_service_account.ems_deployer.email}"
  sensitive   = true
}
