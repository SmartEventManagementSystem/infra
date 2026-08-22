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

variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
  default     = ""
}

variable "ssh_private_key" {
  description = "SSH private key path for provisioning"
  type        = string
  default     = ""
}
