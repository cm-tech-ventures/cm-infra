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
        # CPU extra durante o boot do container (sem custo de instância parada
        # a mais — só acelera o cold start). Mitigação para min_instances=0
        # (CMV-395: 500 recorrente no cm-crm correlacionado 100% com cold
        # start; boost reduz a janela de risco, não elimina).
        startup_cpu_boost = true
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

# Cloud Run Job executado pelo deploy (deploy-cloud-run.yml) antes de servir
# tráfego na nova revisão: cria o schema Postgres do serviço (se necessário)
# e roda as migrations. Mesma imagem do serviço web, comando sobrescrito.
# Idempotente por construção (CREATE SCHEMA IF NOT EXISTS + migrate) — CMV-39.
# Opcional: release_command = [] pula a criação do Job (serviços sem etapa de
# release, ex. frontends estáticos/Next.js — CMV-136). deploy-cloud-run.yml já
# trata release_job_name ausente como "sem release job" (best-effort).
resource "google_cloud_run_v2_job" "release" {
  count    = length(var.release_command) > 0 ? 1 : 0
  project  = var.project_id
  name     = "${var.service_name}-release"
  location = var.region

  template {
    template {
      service_account = google_service_account.service.email
      max_retries     = 1

      containers {
        image   = var.image
        command = var.release_command

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
