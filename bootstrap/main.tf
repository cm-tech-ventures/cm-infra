# Bootstrap único do projeto GCP: APIs, bucket de state, WIF GitHub → GCP e SA de deploy.
# Regras (contrato de design CMV-4):
#   - Nenhuma chave JSON: só federação OIDC via google-github-actions/auth.
#   - Trust restrito por repository_owner E repository.
#   - Bucket de state versionado; um prefix de state por core.

locals {
  required_apis = [
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudtasks.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "bigquery.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each           = toset(local.required_apis)
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# Condições de IAM em recursos do Secret Manager avaliam resource.name usando o
# NÚMERO do projeto (ex.: "projects/857737530765/secrets/foo"), não o project_id
# textual — apesar da mensagem de erro do Terraform ecoar o project_id. Usar o
# project_id na condição faz o startsWith() nunca casar e o apply falha com 403
# em getIamPolicy/setIamPolicy (CMV-28). Resolvemos o número via data source em
# vez de hardcode para não quebrar se o projeto for recriado.
data "google_project" "current" {
  project_id = var.project_id
}

# --- State bucket (versionado; lock nativo do backend GCS) ---
resource "google_storage_bucket" "tf_state" {
  project                     = var.project_id
  name                        = var.state_bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }
}

# --- Workload Identity Federation GitHub → GCP ---
resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "github-${var.environment}"
  display_name              = "GitHub Actions (${var.environment})"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
  }

  # Trust por owner da org (não por lista manual de repos): repos novos da org
  # cm-tech-ventures não precisam de mudança neste provider para autenticar.
  # A autorização granular por repo continua no binding de IAM da SA abaixo
  # (google_service_account_iam_member.wif_binding), que segue restrito à
  # allowlist var.github_repositories.
  attribute_condition = "assertion.repository_owner == \"${var.github_owner}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# --- SA de deploy federada ---
resource "google_service_account" "deployer" {
  project      = var.project_id
  account_id   = "github-deployer-${var.environment}"
  display_name = "GitHub Actions deployer (${var.environment})"
}

resource "google_service_account_iam_member" "wif_binding" {
  for_each           = toset(var.github_repositories)
  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${each.value}"
}

# Permissões mínimas de deploy (push de imagem, deploy Cloud Run, state, scheduler).
# monitoring.alertPolicyEditor + monitoring.notificationChannelEditor: cores passaram a
# instanciar o módulo monitoring-alert-email via Terraform (CMV-513) — sem essas duas roles
# o `terraform apply` do deploy falha com 403 ao criar google_monitoring_alert_policy /
# google_monitoring_notification_channel.
resource "google_project_iam_member" "deployer_roles" {
  for_each = toset([
    "roles/run.admin",
    "roles/artifactregistry.writer",
    "roles/cloudscheduler.admin",
    "roles/monitoring.alertPolicyEditor",
    "roles/monitoring.notificationChannelEditor",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

# secretmanager.viewer não é suficiente: o módulo cloud-run-service cria bindings IAM
# (google_secret_manager_secret_iam_member), o que exige setIamPolicy — só secretmanager.admin
# concede isso. Escopado por condição ao padrão real de nome usado pelo cm-service-template
# (<service_name>-database-url, <service_name>-django-secret-key — ver infra/main.tf dos
# cores) para não abrir admin sobre segredos de outros sistemas do projeto. O prefixo "cm-"
# usado antes nunca correspondia a nenhum secret real (CMV-28) — se um core novo precisar
# de outro tipo de segredo, estenda este regex.
#
# Extensão CMV-61: cm-crm passou a usar <service>-twilio-auth-token (CMV-58) e o secret
# compartilhado identity-introspection-core-key (CMV-59, sem prefixo de service_name — é
# a mesma chave usada por todo core que introspecciona via cm-identity), e o `terraform
# apply` do deploy passou a falhar com 403 em getIamPolicy nesses dois porque a condição
# não cobria os sufixos novos.
resource "google_project_iam_member" "deployer_secretmanager_admin" {
  project = var.project_id
  role    = "roles/secretmanager.admin"
  member  = "serviceAccount:${google_service_account.deployer.email}"

  condition {
    title       = "core-secrets-only"
    description = "Admin restrito aos secrets padrão dos cores (database-url, django-secret-key, twilio-auth-token, identity-introspection-core-key)."
    expression  = "resource.name.startsWith(\"projects/${data.google_project.current.number}/secrets/\") && (resource.name.endsWith(\"-database-url\") || resource.name.endsWith(\"-django-secret-key\") || resource.name.endsWith(\"-twilio-auth-token\") || resource.name.endsWith(\"/identity-introspection-core-key\"))"
  }
}

# Tentativa anterior escopava iam.serviceAccountAdmin por condição no sufixo de nome
# da SA (endsWith "-run@..."). Isso nunca funciona: o motor de condições do IAM avalia
# resource.name de Service Account usando o unique_id NUMÉRICO
# ("//iam.googleapis.com/projects/-/serviceAccounts/<unique_id>"), não o email/account_id
# — confirmado pelo erro 403 em getIamPolicy mesmo com o nome batendo no padrão (CMV-28).
# Não há atributo de condição alternativo para escopar por nome uma SA que ainda não
# existe no momento do apply.
#
# Em vez de roles/iam.serviceAccountAdmin (que também inclui disable/delete/update-key,
# ampliando a superfície de escalação), usamos uma role customizada restrita só às duas
# permissões que o módulo cloud-run-service realmente precisa: ler e escrever a política
# IAM da SA de runtime que ele acabou de criar, para conceder actAs ao deployer
# (google_service_account_iam_member.deployer_act_as). Ainda é um grant projeto-wide (sem
# condição possível), mas a superfície é bem menor que serviceAccountAdmin completo.
resource "google_project_iam_custom_role" "deployer_sa_iam_policy_admin" {
  project     = var.project_id
  role_id     = "deployerServiceAccountIamPolicyAdmin"
  title       = "Deployer — leitura/escrita de política IAM de Service Accounts"
  description = "Permite ao deployer conceder roles/iam.serviceAccountUser sobre as SAs de runtime que ele cria (deploy Cloud Run). Não inclui create/delete/update de SAs."
  permissions = [
    "iam.serviceAccounts.getIamPolicy",
    "iam.serviceAccounts.setIamPolicy",
  ]
}

resource "google_project_iam_member" "deployer_serviceaccount_iam_policy_admin" {
  project = var.project_id
  role    = google_project_iam_custom_role.deployer_sa_iam_policy_admin.id
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

# Condições baseadas em resource.name nunca são satisfeitas em chamadas CREATE (o
# recurso ainda não existe para o avaliador comparar) — por isso o binding acima,
# sozinho, nunca permite ao deployer criar a SA de runtime de um core novo (CMV-28).
# serviceAccountCreator só concede create/get/list, sem delete/update/setIamPolicy,
# então não reabre o caminho de escalação de privilégio que a condição acima evita.
resource "google_project_iam_member" "deployer_serviceaccount_creator" {
  project = var.project_id
  role    = "roles/iam.serviceAccountCreator"
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_storage_bucket_iam_member" "deployer_state" {
  bucket = google_storage_bucket.tf_state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.deployer.email}"
}

# --- SA read-only de observabilidade (rotina Ops semanal — CMV-319) ---
# Sem chave JSON: a rotina assume esta SA via impersonation
# (gcloud --impersonate-service-account) a partir da identidade local listada em
# var.ops_observer_impersonators. Somente roles de leitura — a rotina só lê
# (list/describe/logs read), nunca age no GCP.
resource "google_service_account" "ops_observer" {
  project      = var.project_id
  account_id   = "cm-ops-observer"
  display_name = "Ops semanal — leitura read-only (CMV-319)"
}

resource "google_project_iam_member" "ops_observer_roles" {
  for_each = toset([
    "roles/run.viewer",
    "roles/monitoring.viewer",
    "roles/logging.viewer",
    "roles/cloudscheduler.viewer",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.ops_observer.email}"
}

resource "google_billing_account_iam_member" "ops_observer_billing_viewer" {
  count              = var.billing_account_id != "" ? 1 : 0
  billing_account_id = var.billing_account_id
  role               = "roles/billing.viewer"
  member             = "serviceAccount:${google_service_account.ops_observer.email}"
}

resource "google_service_account_iam_member" "ops_observer_token_creator" {
  for_each           = toset(var.ops_observer_impersonators)
  service_account_id = google_service_account.ops_observer.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = each.value
}

# --- BigQuery: logs de tool call do cm-mcp/md-mcp (CMV-594, filha de CMV-593) ---
# Dataset único para as duas fontes de tool call (cm-mcp aqui neste projeto; md-mcp
# roda em projeto próprio da família MD — infra dele fora deste repo, ver comentário
# de fechamento da issue). Tabela particionada nativa via bigquery_options no sink
# (não o default `_YYYYMMDD` por wildcard) para o dbt do cm-analytics declarar a
# source sem glob de tabelas.
resource "google_bigquery_dataset" "mcp_logs" {
  project     = var.project_id
  dataset_id  = "raw_mcp_logs"
  location    = var.region
  description = "Logs estruturados de tool call do cm-mcp/md-mcp (evento tool_call), via Cloud Logging sink (CMV-594)."
}

resource "google_logging_project_sink" "mcp_tool_calls" {
  project     = var.project_id
  name        = "cm-mcp-tool-calls-to-bq"
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.mcp_logs.dataset_id}"

  # jsonPayload.event="tool_call": formato emitido por service/observability.py
  # do cm-mcp (CMV-498) e equivalente do md-mcp (CMV-591/592). resource.labels.service_name
  # diferencia a origem (cm-mcp vs md-mcp) já que os dois podem cair no mesmo projeto/dataset.
  filter = <<-EOT
    resource.type="cloud_run_revision"
    jsonPayload.event="tool_call"
    resource.labels.service_name=("cm-mcp" OR "md-mcp")
  EOT

  bigquery_options {
    use_partitioned_tables = true
  }

  unique_writer_identity = true
}

# Sem essa concessão o sink falha silenciosamente ao gravar (grava para o _Default
# sink coletor de erros, não para o dataset) — a writer_identity do sink precisa de
# dataEditor no dataset, nunca no projeto inteiro.
resource "google_bigquery_dataset_iam_member" "mcp_logs_sink_writer" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.mcp_logs.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = google_logging_project_sink.mcp_tool_calls.writer_identity
}

# SA do pipeline dbt do cm-analytics (analytics-pipeline-job@...) — leitura para
# declarar a source no staging, sem poder de escrita sobre o dataset de logs.
resource "google_bigquery_dataset_iam_member" "mcp_logs_dbt_reader" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.mcp_logs.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${var.dbt_pipeline_service_account}"
}

# --- Artifact Registry compartilhado dos cores ---
module "artifact_registry" {
  source        = "../modules/artifact-registry"
  project_id    = var.project_id
  region        = var.region
  repository_id = "cm-cores"
  writers       = [google_service_account.deployer.email]
}
