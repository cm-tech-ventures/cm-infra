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
# logging.configWriter: mesma história, um ciclo depois. As políticas de alerta que
# entraram em 24/09 contam linhas de log, e para isso o deploy cria
# google_logging_metric (modules/alerta-generico, modules/log-error-alert) — sem esta
# role o apply falha com 403. O papel foi concedido à mão na ocasião e não foi escrito
# aqui; esta linha só registra no código o que já vale em produção desde então.
# bigquery.user: o cm-analytics passou a criar os datasets do armazém no Terraform
# (Plataforma de dados, fase 1 / E1, cm-analytics#71). Sem ela o apply falha com 403
# em bigquery.datasets.create. É o papel mínimo: cria dataset e roda job, mas não lê
# dado de dataset nenhum. Quem cria o dataset vira OWNER dele, e isso basta para o
# deploy dar as permissões por dataset (google_bigquery_dataset_iam_member) — sem
# abrir billing_export nem raw_mcp_logs.
resource "google_project_iam_member" "deployer_roles" {
  for_each = toset([
    "roles/run.admin",
    "roles/artifactregistry.writer",
    "roles/bigquery.user",
    "roles/cloudscheduler.admin",
    "roles/logging.configWriter",
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

# Extensão da core-secrets-only (cm-infra#73, plano #70). A varredura de 06/10 achou
# secrets que os deploys tocam e que a condição acima não cobre: hoje só funcionam por
# causa do secretmanager.admin SEM condição que o deployer ganhou à mão, e que a E5 vai
# tirar. Sem esta extensão, o primeiro deploy depois da E5 falha com 403.
#
# É um SEGUNDO binding, e não uma edição da condição acima, porque `condition` força
# REPLACE no google_project_iam_member (destroy + create do binding). Somar um binding
# condicional novo, com outro título, é "1 to add" e não encosta no que funciona.
#
# Prefixo do nome completo, não sufixo genérico: um "-asaas-api-key" solto também
# casaria uma futura chave de subconta (billing-subconta-*), que é credencial de
# cliente e não é assunto do deploy. Cada alternativa abaixo cobre só os secrets
# listados. Limite do IAM: 12 operadores lógicos por condição; esta usa 9.
#   billing[-hom]-asaas-api-key, billing[-hom]-asaas-webhook-token
#   identity[-hom]-google-oauth-client-id, identity[-hom]-google-oauth-client-secret
#   identity[-hom]-resend-api-key, identity-hom-introspection-core-key
#   cm-analytics-iap-oauth-client-{id,secret}, cm-analytics-oauth2-proxy-{cookie-secret,allowed-emails}
#   analytics-md-db-url: a plataforma de dados (#89) dá secretAccessor nele à
#   analytics-bq-pipeline pelo Terraform do cm-analytics, aplicado pelo deployer.
locals {
  secrets_prefixo = "projects/${data.google_project.current.number}/secrets/"
  deployer_secrets_extra = [
    "billing-asaas-",
    "billing-hom-asaas-",
    "identity-google-oauth-client-",
    "identity-hom-google-oauth-client-",
    "identity-resend-api-key",
    "identity-hom-resend-api-key",
    "identity-hom-introspection-core-key",
    "cm-analytics-iap-oauth-client-",
    "cm-analytics-oauth2-proxy-",
    "analytics-md-db-url",
  ]
}

resource "google_project_iam_member" "deployer_secretmanager_admin_extra" {
  project = var.project_id
  role    = "roles/secretmanager.admin"
  member  = "serviceAccount:${google_service_account.deployer.email}"

  condition {
    title       = "core-secrets-extra"
    description = "Admin nos secrets de deploy fora da core-secrets-only: Asaas do billing, OAuth/Resend do identity, chave de introspecção de hom, OAuth do IAP e analytics-md-db-url (cm-infra#73)."
    expression  = join(" || ", [for p in local.deployer_secrets_extra : "resource.name.startsWith(\"${local.secrets_prefixo}${p}\")"])
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

# storage.admin só nos buckets que os deploys mantêm (cm-infra#73). Hoje o deployer
# tem storage.admin no PROJETO, dado à mão, e é isso que deixa o Terraform do
# cm-docs e do cm-analytics mexer na política IAM destes buckets. A E5 tira o papel
# do projeto; este binding por bucket é o que fica.
resource "google_storage_bucket_iam_member" "deployer_buckets_admin" {
  for_each = toset([
    "cm-docs-site",
    "cm-analytics-dbt-docs-site",
    "cm-ventures-core-analytics-staging",
  ])
  bucket = each.value
  role   = "roles/storage.admin"
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

# --- Leitura do Backoffice no core (cm-infra#73) ---
# Os papéis abaixo foram dados à mão quando o Backoffice nasceu e entram aqui por
# import (bootstrap/imports.tf), COMO ESTÃO: o cloudscheduler.admin de prod não é
# rebaixado agora (pergunta aberta no #70: só vira viewer se a frente do Backoffice
# confirmar que nenhuma onda dispara rotina). As SAs são criadas pelo Terraform do
# cm-backoffice; aqui mora só o que elas podem no projeto.
#
# iam.securityReviewer (prod) é novo: a tela "Permissões" do Backoffice (E10) lê as
# políticas de IAM. logging.viewer já existia e só é importado.
locals {
  backoffice_papeis = {
    "cm-backoffice-run" = [
      "roles/cloudscheduler.admin",
      "roles/iam.securityReviewer",
      "roles/logging.viewer",
      "roles/run.viewer",
    ]
    "cm-backoffice-hom-run" = [
      "roles/cloudscheduler.viewer",
      "roles/logging.viewer",
      "roles/run.viewer",
    ]
  }
}

resource "google_project_iam_member" "backoffice_leitura" {
  for_each = merge([
    for sa, papeis in local.backoffice_papeis : {
      for papel in papeis : "${sa} ${papel}" => { sa = sa, papel = papel }
    }
  ]...)
  project = var.project_id
  role    = each.value.papel
  member  = "serviceAccount:${each.value.sa}@${var.project_id}.iam.gserviceaccount.com"
}

# --- bigquery.jobUser das SAs do armazém (cm-infra#73) ---
# Hoje declarados no cm-analytics (terraform/bigquery.tf, warehouse_pipeline_job_user
# e warehouse_metabase_job_user), o único motivo para o deployer ainda precisar de
# projectIamAdmin. Entram aqui por import; o cm-analytics solta os dois do state dele
# com `removed { lifecycle { destroy = false } }` (etapa seguinte do #70). Até lá os
# dois states declaram o mesmo membro — inofensivo, porque _iam_member é aditivo.
resource "google_project_iam_member" "armazem_job_user" {
  for_each = toset([
    "analytics-bq-pipeline",
    "analytics-bq-metabase",
  ])
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${each.value}@${var.project_id}.iam.gserviceaccount.com"
}

# --- Metabase local impersona a analytics-bq-metabase (plataforma de dados, fase 3) ---
# A org bloqueia chave de SA, então o Metabase local usa impersonation. Binding NA SA,
# nunca no projeto: a pessoa só lê o que a SA lê.
resource "google_service_account_iam_member" "metabase_token_creator" {
  for_each           = toset(var.metabase_impersonators)
  service_account_id = "projects/${var.project_id}/serviceAccounts/analytics-bq-metabase@${var.project_id}.iam.gserviceaccount.com"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = each.value
}

# --- Leitura cruzada de secrets do core (cm-infra#73) ---
# SAs de outros projetos (MD e bjj) que leem secrets do core: a chave de
# introspecção e a chave da org MD no identity. Concedidas à mão; entram aqui por
# import. Só secretAccessor: o secretmanager.admin cruzado que algumas SAs de deploy
# de fora têm nesses secrets NÃO é declarado aqui (sai na E5 do #70).
resource "google_secret_manager_secret_iam_member" "leitura_cruzada" {
  for_each = merge([
    for secret, membros in var.secrets_leitores_externos : {
      for membro in membros : "${secret} ${membro}" => { secret = secret, membro = membro }
    }
  ]...)
  project   = var.project_id
  secret_id = each.value.secret
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value.membro
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

# REMOVIDO em 06/10/2026: havia aqui um `mcp_logs_dbt_reader` dando
# bigquery.dataViewer no raw_mcp_logs à SA do pipeline dbt do cm-analytics
# (analytics-pipeline-job@). Essa SA **não existe mais** — foi embora com o
# analytics antigo, removido pela Plataforma de dados no mesmo dia.
#
# O bloco nunca chegou a ser aplicado, e era a razão de todo `plan` do bootstrap
# nascer com "1 to add" pendente para quem quer que fosse aplicar. Provado por
# apply real: o Google recusou com
#   "Service account analytics-pipeline-job@... does not exist"
#
# A variável `dbt_pipeline_service_account` também saiu (cm-infra#65). Se o
# raw_mcp_logs voltar a precisar de leitor dbt, a SA é analytics-bq-pipeline@.

# Writer identities de sinks cross-project (ex: md-hom/md-mcp, CMV-599) que também
# gravam em raw_mcp_logs. Cloud Logging sinks são escopados ao projeto onde vivem
# (não veem logs de outros projetos), então cada projeto da família MD provisiona
# seu próprio sink apontando pra este dataset; a IAM correspondente entra aqui porque
# só este state tem permissão sobre o dataset.
resource "google_bigquery_dataset_iam_member" "mcp_logs_external_sink_writer" {
  for_each   = toset(var.mcp_logs_external_sink_writer_identities)
  project    = var.project_id
  dataset_id = google_bigquery_dataset.mcp_logs.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = each.value
}

# --- Artifact Registry compartilhado dos cores ---
module "artifact_registry" {
  source        = "../modules/artifact-registry"
  project_id    = var.project_id
  region        = var.region
  repository_id = "cm-cores"
  writers       = [google_service_account.deployer.email]

  # Um pacote por serviço que publica aqui. Conferir com:
  #   gcloud artifacts packages list --repository=cm-cores \
  #     --location=southamerica-east1 --project=cm-ventures-core
  # Pacote novo que não entrar nesta lista NÃO fica protegido: cai na regra de
  # idade e perde tudo com mais de 30 dias. Ao criar um core novo, adicione aqui.
  pacotes_protegidos = [
    "analytics-dashboard-proxy",
    "analytics-pipeline",
    "billing",
    "cm-backoffice",
    "cm-backoffice-frontend",
    "cm-mcp",
    "crm",
    "identity",
    "keepalive-check",
    "service",
  ]

  retencao_dry_run = var.retencao_dry_run
}
