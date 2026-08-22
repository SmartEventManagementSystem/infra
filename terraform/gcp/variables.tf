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
  default     = ""
}
