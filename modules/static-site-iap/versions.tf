terraform {
  required_version = ">= 1.7"
  required_providers {
    google = {
      source = "hashicorp/google"
      # >= 5.30 cobre o bloco `iap {}` nativo em google_compute_backend_service
      # e o recurso google_cloud_run_v2_service usados por este módulo.
      version = ">= 5.30, < 7"
    }
  }
}
