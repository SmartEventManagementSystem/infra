variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "db_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
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

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to access the control plane"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "vpc_cidr" {
  description = "VPC CIDR range"
  type        = string
  default     = "10.10.0.0/20"
}

variable "pod_cidr" {
  description = "Pod IP CIDR range (secondary)"
  type        = string
  default     = "10.20.0.0/16"
}

variable "svc_cidr" {
  description = "Service IP CIDR range (secondary)"
  type        = string
  default     = "10.30.0.0/20"
}

variable "cluster_primary_version" {
  description = "GKE cluster version"
  type        = string
  default     = "1.30"
}

variable "system_node_machine_type" {
  description = "System nodepool machine type"
  type        = string
  default     = "g1-standard-2"
}

variable "app_node_machine_type" {
  description = "App nodepool machine type"
  type        = string
  default     = "n2-standard-4"
}

variable "data_node_machine_type" {
  description = "Data nodepool machine type"
  type        = string
  default     = "n2-standard-8"
}
