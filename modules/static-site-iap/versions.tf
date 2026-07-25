terraform {
  required_version = ">= 1.7"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.30, < 7"
    }
    # Usado apenas pelo null_resource que habilita IAP no backend bucket via
    # gcloud (ver README.md — limitação conhecida do provider google).
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2"
    }
  }
}
