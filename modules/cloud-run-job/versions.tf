terraform {
  required_version = ">= 1.7"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 7" # deletion_protection no google_cloud_run_v2_job nasceu na 6.0
    }
  }
}
