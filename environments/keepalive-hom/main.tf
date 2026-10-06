# Keep-alive de HOMOLOGAÇÃO (02/10/2026).
#
# Por que existe, já que o keep-alive de produção cobre os bancos de hom:
# o Backoffice precisa de um Cloud Run Job disparado por scheduler em
# homologação para exercitar o caminho de escrita da onda 4 — pausar, retomar,
# mudar horário, disparar agora — sem tocar em rotina de produção.
#
# Das 12 rotinas da empresa, duas já tinham gêmeo de hom (billing-hom-regua-diaria
# e sys-bjj-backend-hom-rotina-diaria), e as duas são `http_oidc`. Esta é a
# primeira `cloud_run_job_oauth` de homologação, que é o tipo de alvo onde o
# "verde" do Cloud Scheduler mente — ou seja, exatamente o caminho que mais
# precisa ser testado antes de subir.
#
# O Cloud Scheduler NÃO aceita vínculo condicional de IAM, então não há como dar
# à conta do Backoffice de hom poder sobre os schedulers `-hom` e não sobre os de
# produção: eles moram no mesmo projeto. A fronteira fica no código do serviço,
# e isso está declarado como limitação, não como garantia.

module "keepalive_hom_job" {
  source = "../../modules/cloud-run-job"

  job_name    = "keepalive-check-hom"
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
  invoker_service_account  = google_service_account.scheduler_hom.email
}

# SA própria, não a de produção: se um dia a de hom precisar de menos poder, não
# há nada para desembaraçar.
resource "google_service_account" "scheduler_hom" {
  project      = var.project_id
  account_id   = "keepalive-hom-scheduler"
  display_name = "Cloud Scheduler — dispara keepalive-check-hom"
}

module "keepalive_hom_schedule" {
  source = "../../modules/scheduler-job"

  name       = "keepalive-check-hom"
  project_id = var.project_id
  region     = var.region
  schedule   = var.schedule

  target_uri           = module.keepalive_hom_job.run_execution_uri
  auth_mode            = "oauth"
  oidc_service_account = google_service_account.scheduler_hom.email
  http_method          = "POST"
  attempt_deadline     = "320s"
  retry_count          = 1
}

module "keepalive_hom_alert" {
  source = "../../modules/monitoring-alert-email"

  project_id         = var.project_id
  notification_email = var.notification_email
  alert_display_name = "Keep-alive Supabase — HOMOLOGAÇÃO"
  job_name           = module.keepalive_hom_job.job_name
  location           = var.region
  alignment_period   = "86400s"
}
