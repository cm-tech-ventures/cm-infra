# Módulo genérico de Cloud Run Job para os cores da CM Ventures.
# Async nos cores é Jobs + Scheduler + Tasks — sem worker permanente (contrato CMV-4).
# Nenhum conceito de vertical: especificidade vem de fora via env/secrets.

locals {
  sa_account_id = substr("${var.job_name}-job", 0, 30)
}

resource "google_service_account" "job" {
  project      = var.project_id
  account_id   = local.sa_account_id
  display_name = "Runtime SA — job ${var.job_name} (${var.environment})"
}

# A SA do job só pode ler os segredos que o próprio job usa.
resource "google_secret_manager_secret_iam_member" "reader" {
  for_each  = var.secrets
  project   = var.project_id
  secret_id = each.value.secret
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.job.email}"
}

# A SA de deploy (WIF) precisa de actAs sobre a SA do job para fazer deploy.
resource "google_service_account_iam_member" "deployer_act_as" {
  count              = var.deployer_service_account != "" ? 1 : 0
  service_account_id = google_service_account.job.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.deployer_service_account}"
}

resource "google_cloud_run_v2_job" "job" {
  project  = var.project_id
  name     = var.job_name
  location = var.region

  template {
    template {
      service_account = google_service_account.job.email
      max_retries     = var.max_retries
      timeout         = var.timeout

      containers {
        image   = var.image
        command = length(var.command) > 0 ? var.command : null

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
  }

  lifecycle {
    ignore_changes = [
      launch_stage,
    ]
  }
}

# Permite que a SA usada pelo Cloud Scheduler (OAuth) dispare a execução do job.
resource "google_cloud_run_v2_job_iam_member" "invoker" {
  count    = var.invoker_service_account != "" ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.job.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.invoker_service_account}"
}
