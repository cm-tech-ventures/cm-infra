terraform {
  required_version = ">= 1.7"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.30, < 7"
    }
  }

  # Bootstrap começa com state local; após criar o bucket, migre:
  #   terraform init -migrate-state -backend-config="bucket=<state-bucket>" -backend-config="prefix=bootstrap/prod"
  backend "gcs" {}
}
