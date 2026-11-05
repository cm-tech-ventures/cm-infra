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
    bucket = "md-hom-paperclip-tfstate"
    prefix = "cm-infra/billing-export-acesso-md"
  }
}

provider "google" {
  project = "md-hom"
  region  = "southamerica-east1"
}
