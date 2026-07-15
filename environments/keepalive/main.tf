# Keep-alive periódico dos bancos Supabase free-tier da empresa (CMV-53).
# Paliativo de fase pré-produção: quando uma vertical tiver uso real contínuo,
# avaliar upgrade do projeto Supabase para tier pago em vez de depender disto
# (ver cm-infra/docs/keepalive.md).

module "keepalive_job" {
  source = "../../modules/cloud-run-job"

  job_name    = "keepalive-check"
  project_id  = var.project_id
  region      = var.region
  environment = var.environment
  image       = var.image

  secrets = {
    KEEPALIVE_DB_DSNS = { secret = var.keepalive_secret_id }
  }

  cpu         = "1"
  memory      = "512Mi"
  timeout     = "300s"
  max_retries = 0

  deployer_service_account = "github-deployer-prod@${var.project_id}.iam.gserviceaccount.com"
  invoker_service_account  = google_service_account.scheduler.email
}

# SA dedicada ao Cloud Scheduler para disparar a execução via Run Admin API (OAuth).
resource "google_service_account" "scheduler" {
  project      = var.project_id
  account_id   = "keepalive-scheduler"
  display_name = "Cloud Scheduler — dispara keepalive-check (CMV-53)"
}

module "keepalive_schedule" {
  source = "../../modules/scheduler-job"

  name       = "keepalive-check"
  project_id = var.project_id
  region     = var.region
  schedule   = var.schedule

  target_uri           = module.keepalive_job.run_execution_uri
  auth_mode            = "oauth"
  oidc_service_account = google_service_account.scheduler.email
  http_method          = "POST"
  attempt_deadline     = "320s"
  retry_count          = 1
}

module "keepalive_alert" {
  source = "../../modules/monitoring-alert-email"

  project_id         = var.project_id
  notification_email = var.notification_email
  alert_display_name = "Keep-alive Supabase (CMV-53)"
  job_name           = module.keepalive_job.job_name
  location           = var.region
  alignment_period   = "86400s"
}
