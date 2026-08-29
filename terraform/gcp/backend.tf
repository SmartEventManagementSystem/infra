terraform {
  backend "gcs" {
    bucket = "project-5ca79767-316d-4e68-a56-ems-terraform-state"
    prefix = "gcp"
  }
}
