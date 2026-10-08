# --- SA de ensaio (cm-infra#74, etapa 9 do plano #70; decisão D4) ---
#
# Conta TEMPORÁRIA com exatamente o poder que o github-deployer-prod terá depois
# da etapa 11 (cm-infra#76), quando perde:
#   projectIamAdmin, roleAdmin, serviceAccountAdmin, serviceAccountUser no projeto,
#   storage.admin no projeto, secretmanager.admin sem condição,
#   iap.admin e compute.loadBalancerAdmin (nenhum Terraform do core usa
#   google_iap_* nem google_compute_*; o static-site-iap usa oauth2-proxy no Run).
# Com ela, impersonada à mão, rodamos plan de todos os states do core e apply dos
# de hom ANTES de tirar os papéis do deployer real. Roteiro em docs/permissoes.md,
# seção "SA de ensaio".
#
# Sem WIF: só as pessoas de var.ensaio_impersonadores assumem a conta.
# Tudo aqui depende de var.ensaio_habilitado. No fim da frente:
# ensaio_habilitado = false e o plan mostra só destroys deste arquivo; depois o
# arquivo e as variáveis ensaio_* podem sair.
#
# Todo binding é _iam_member (aditivo): nada aqui encosta no que o deployer tem.

locals {
  ensaio_ativo  = var.ensaio_habilitado ? 1 : 0
  ensaio_member = var.ensaio_habilitado ? "serviceAccount:${google_service_account.deployer_ensaio[0].email}" : ""

  # Papéis de projeto que sobram ao deployer depois da etapa 11: os mesmos do
  # bootstrap (main.tf), mais o papel custom de IAM de SA e o serviceAccountCreator.
  ensaio_papeis_projeto = concat(
    local.deployer_papeis_projeto,
    [
      google_project_iam_custom_role.deployer_sa_iam_policy_admin.id,
      "roles/iam.serviceAccountCreator",
    ],
  )
}

resource "google_service_account" "deployer_ensaio" {
  count        = local.ensaio_ativo
  project      = var.project_id
  account_id   = "deployer-ensaio"
  display_name = "Ensaio do deployer pós-E5 (temporária, cm-infra#74)"
  description  = "Mesmos papéis do github-deployer-prod depois da etapa 11 do #70. Sem WIF. Apagar no fim da frente (ensaio_habilitado = false)."
}

resource "google_service_account_iam_member" "ensaio_token_creator" {
  for_each           = var.ensaio_habilitado ? toset(var.ensaio_impersonadores) : toset([])
  service_account_id = google_service_account.deployer_ensaio[0].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = each.value
}

resource "google_project_iam_member" "ensaio_roles" {
  for_each = var.ensaio_habilitado ? toset(local.ensaio_papeis_projeto) : toset([])
  project  = var.project_id
  role     = each.value
  member   = local.ensaio_member
}

# As duas condições do deployer, com o mesmo texto (local.deployer_secrets_condicoes).
resource "google_project_iam_member" "ensaio_secretmanager_admin" {
  for_each = var.ensaio_habilitado ? local.deployer_secrets_condicoes : {}
  project  = var.project_id
  role     = "roles/secretmanager.admin"
  member   = local.ensaio_member

  condition {
    title       = each.value.title
    description = each.value.description
    expression  = each.value.expression
  }
}

resource "google_storage_bucket_iam_member" "ensaio_state" {
  count  = local.ensaio_ativo
  bucket = google_storage_bucket.tf_state.name
  role   = "roles/storage.objectAdmin"
  member = local.ensaio_member
}

resource "google_storage_bucket_iam_member" "ensaio_buckets_admin" {
  for_each = var.ensaio_habilitado ? toset(local.deployer_buckets_admin) : toset([])
  bucket   = each.value
  role     = "roles/storage.admin"
  member   = local.ensaio_member
}

# actAs por recurso: o deployer tem serviceAccountUser em cada SA de runtime/proxy
# (deployer_act_as dos módulos e do cm-analytics). Na SA de ensaio quem dá é o
# bootstrap, porque os repos só conhecem o deployer real.
resource "google_service_account_iam_member" "ensaio_act_as" {
  for_each           = var.ensaio_habilitado ? toset(var.ensaio_act_as_service_accounts) : toset([])
  service_account_id = "projects/${var.project_id}/serviceAccounts/${each.value}@${var.project_id}.iam.gserviceaccount.com"
  role               = "roles/iam.serviceAccountUser"
  member             = local.ensaio_member
}

# Datasets onde o deployer é OWNER e continua sendo depois das etapas 11 e 14
# (os do armazém, criados pelo cm-analytics). Fora: bronze_logs e raw_mcp_logs,
# que pela etapa 14 passam a ter dono só humano e o deploy não usa.
resource "google_bigquery_dataset_iam_member" "ensaio_datasets_dono" {
  for_each   = var.ensaio_habilitado ? toset(var.ensaio_datasets_dono) : toset([])
  project    = var.project_id
  dataset_id = each.value
  role       = "roles/bigquery.dataOwner"
  member     = local.ensaio_member
}

# Leitura onde o deploy só lê: billing_export (o apply do cm-analytics cria as
# views do bronze_custos e o BigQuery confere a origem). Espelha o dataViewer que
# o deployer tem por environments/billing-export-acesso.
resource "google_bigquery_dataset_iam_member" "ensaio_datasets_leitura" {
  for_each   = var.ensaio_habilitado ? toset(var.ensaio_datasets_leitura) : toset([])
  project    = var.project_id
  dataset_id = each.value
  role       = "roles/bigquery.dataViewer"
  member     = local.ensaio_member
}
