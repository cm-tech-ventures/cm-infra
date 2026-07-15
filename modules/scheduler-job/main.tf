# Cloud Scheduler → Cloud Run (Job ou endpoint HTTP) com OIDC.
# Substitui worker permanente (Celery): async nos cores é Jobs + Scheduler + Tasks.

resource "google_cloud_scheduler_job" "job" {
  project          = var.project_id
  region           = var.region
  name             = var.name
  schedule         = var.schedule
  time_zone        = var.time_zone
  attempt_deadline = var.attempt_deadline

  retry_config {
    retry_count = var.retry_count
  }

  http_target {
    uri         = var.target_uri
    http_method = var.http_method
    body        = var.body != "" ? base64encode(var.body) : null
    headers     = var.body != "" ? { "Content-Type" = "application/json" } : null

    dynamic "oidc_token" {
      for_each = var.auth_mode == "oidc" ? [1] : []
      content {
        service_account_email = var.oidc_service_account
        audience              = var.oidc_audience != "" ? var.oidc_audience : var.target_uri
      }
    }

    # Run Admin API (ex: disparar execução de Cloud Run Job) exige OAuth, não OIDC.
    dynamic "oauth_token" {
      for_each = var.auth_mode == "oauth" ? [1] : []
      content {
        service_account_email = var.oidc_service_account
        scope                 = var.oauth_scope
      }
    }
  }
}
