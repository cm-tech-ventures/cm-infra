terraform {
  required_version = ">= 1.7"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.30, < 7"
    }
  }

  backend "gcs" {
    bucket = "cm-ventures-core-tfstate"
    prefix = "environments/log-sinks"
  }
}

provider "google" {
  project = "cm-ventures-core"
  region  = "southamerica-east1"
}
