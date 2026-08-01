terraform {
  required_version = ">= 1.7"
  required_providers {
    google = {
      source = "hashicorp/google"
      # >= 6.14 cobre `iap_enabled` em google_cloud_run_v2_service e o
      # recurso google_iap_web_cloud_run_service_iam_member (IAP nativo em
      # Cloud Run sem LB — CMV-346). CONFIRMAR contra o CHANGELOG do
      # provider antes do primeiro apply desta revisão.
      version = ">= 6.14, < 7"
    }
  }
}
