# Módulo genérico de serviço Cloud Run para os cores da CM Ventures.
# Invariantes (contrato de design CMV-4):
#   - 1 service account dedicada por core, permissões mínimas.
#   - Segredos só como referência a Secret Manager (secret_key_ref) — nunca valor no state.
#   - Nenhum conceito de vertical; especificidade vem de fora via env/secrets.

locals {
  sa_account_id = substr("${var.service_name}-run", 0, 30)
}

resource "google_service_account" "service" {
  project      = var.project_id
  account_id   = local.sa_account_id
  display_name = "Runtime SA — ${var.service_name} (${var.environment})"
}

# A SA do serviço só pode ler os segredos que o próprio serviço usa.
resource "google_secret_manager_secret_iam_member" "reader" {
  for_each  = var.secrets
  project   = var.project_id
  secret_id = each.value.secret
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.service.email}"
}

# A SA de deploy (WIF) precisa de actAs sobre a SA do serviço para fazer deploy.
resource "google_service_account_iam_member" "deployer_act_as" {
  count              = var.deployer_service_account != "" ? 1 : 0
  service_account_id = google_service_account.service.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.deployer_service_account}"
}

resource "google_cloud_run_v2_service" "service" {
  project  = var.project_id
  name     = var.service_name
  location = var.region

  template {
    service_account = google_service_account.service.email

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      image = var.image

      ports {
        container_port = var.container_port
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }

      dynamic "env" {
        for_each = var.env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = var.secrets
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value.secret
              version = env.value.version
            }
          }
        }
      }
    }
  }

  labels = {
    environment = var.environment
    managed-by  = "cm-infra"
  }

  depends_on = [google_secret_manager_secret_iam_member.reader]
}

resource "google_cloud_run_v2_service_iam_member" "public" {
  count    = var.allow_unauthenticated ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_domain_mapping" "domain" {
  count    = var.custom_domain != "" ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = var.custom_domain

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name = google_cloud_run_v2_service.service.name
  }
}
