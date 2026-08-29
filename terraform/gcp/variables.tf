variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "asia-southeast1"
}

variable "db_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
}

variable "oracle_vm_ip" {
  description = "Oracle VM IP to whitelist for Cloud SQL"
  type        = string
  default     = ""
}

variable "gcp_service_account_email" {
  description = "Service account email for IAM"
  type        = string
  default     = "ems-terraform@project-5ca79767-316d-4e68-a56.iam.gserviceaccount.com"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "db_user" {
  description = "PostgreSQL username"
  type        = string
  default     = "emsuser"
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "ems_events"
}

variable "redis_password" {
  description = "Redis password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vpc_cidr" {
  description = "VPC CIDR range"
  type        = string
  default     = "10.10.0.0/20"
}

variable "pod_cidr" {
  description = "Pod IP CIDR range"
  type        = string
  default     = "10.20.0.0/16"
}

variable "svc_cidr" {
  description = "Service IP CIDR range"
  type        = string
  default     = "10.30.0.0/20"
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "system_node_machine_type" {
  description = "System nodepool machine type"
  type        = string
  default     = "e2-micro"
}

variable "app_node_machine_type" {
  description = "App nodepool machine type"
  type        = string
  default     = "e2-micro"
}

variable "data_node_machine_type" {
  description = "Data nodepool machine type"
  type        = string
  default     = "e2-micro"
}
