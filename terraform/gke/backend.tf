# Terraform state stored in GCS
# Bucket must be created manually before first apply:
#   gsutil mb -l us-central1 gs://<project-id>-ems-terraform-state

terraform {
  backend "gcs" {
    bucket = "ems-terraform-state" # Replace with your actual bucket name
    prefix = "gke"
  }
}
