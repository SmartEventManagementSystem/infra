# Terraform state stored in GCS
# Bucket must be created manually before first apply:
#   gsutil mb -l us-central1 gs://<project-id>-ems-terraform-state

terraform {
  backend "gcs" {
    bucket  = "project-5ca79767-316d-4e68-a56-ems-terraform-state"
    prefix  = "gke"
    project = "project-5ca79767-316d-4e68-a56"
  }
}
