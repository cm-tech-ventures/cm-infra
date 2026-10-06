terraform {
  required_version = ">= 1.7"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.30, < 7"
    }
  }

  # State próprio: uma mudança em homologação nunca toca o state de produção.
  backend "gcs" {
    bucket = "cm-ventures-core-tfstate"
    prefix = "environments/keepalive-hom"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
