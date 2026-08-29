output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.ems_cluster.name
}

output "cluster_id" {
  description = "GKE cluster ID"
  value       = google_container_cluster.ems_cluster.id
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.ems_cluster.endpoint
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  sensitive   = true
  value       = google_container_cluster.ems_cluster.master_auth[0].cluster_ca_certificate
}

output "postgres_ip" {
  description = "Cloud SQL PostgreSQL private IP"
  value       = google_sql_database_instance.ems_postgres.private_ip_address
}

output "postgres_connection_name" {
  description = "Cloud SQL connection name"
  value       = google_sql_database_instance.ems_postgres.connection_name
}

output "postgres_instance_name" {
  description = "Cloud SQL instance name"
  value       = google_sql_database_instance.ems_postgres.name
}

output "redis_ip" {
  description = "Cloud Memorystore Redis IP"
  value       = google_redis_instance.ems_redis.host
}

output "redis_port" {
  description = "Cloud Memorystore Redis port"
  value       = google_redis_instance.ems_redis.port
}

output "redis_host" {
  description = "Cloud Memorystore Redis host"
  value       = google_redis_instance.ems_redis.host
}

output "gke_nodes_sa" {
  description = "GKE nodes service account email"
  value       = google_service_account.gke_nodes.email
}

output "backup_bucket" {
  description = "Backup Cloud Storage bucket name"
  value       = google_storage_bucket.ems_backups.name
}

output "datalake_bucket" {
  description = "Datalake Cloud Storage bucket name"
  value       = google_storage_bucket.ems_datalake.name
}

output "vpc_id" {
  description = "VPC network ID"
  value       = google_compute_network.ems_vpc.id
}

output "subnet_id" {
  description = "Subnet ID"
  value       = google_compute_subnetwork.ems_nodes.id
}

output "vpc_connector_id" {
  description = "VPC Access Connector ID"
  value       = google_vpc_access_connector.ems_vpc_connector.id
}

output "nat_ip" {
  description = "Cloud NAT IP address"
  value       = google_compute_address.nat_ip.address
}
