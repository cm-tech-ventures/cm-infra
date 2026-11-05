terraform {
  required_version = ">= 1.7"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.30, < 7"
    }
  }

  # State no bucket da conta dona do dataset, não no cm-ventures-core-tfstate.
  # Ver README.md.
  backend "gcs" {
    bucket = "terraform-backend-sys-bjj"
    prefix = "cm-infra/billing-export-acesso-bjj"
  }
}

provider "google" {
  project = "bjj-system"
  region  = "southamerica-east1"
}
