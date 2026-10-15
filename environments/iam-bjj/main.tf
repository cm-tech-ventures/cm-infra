# IAM do bjj-system no código (cm-infra#79, plano #70).
#
# Fundação do projeto bjj-system: contas de deploy, WIF do GitHub, papéis de
# projeto das contas de deploy, IAM do bucket de state e o que contas de fora
# (cm.tech.ventures, Backoffice) têm aqui. Ver docs/permissoes.md.
#
# Nesta etapa tudo é retrato do que está vivo em 06/10/2026, inclusive os papéis
# que a regra 1 proíbe (projectIamAdmin, serviceAccountAdmin, secretmanager.admin
# sem condição...). Eles saem na etapa 18, um a um, por PR.
#
# Só `google_*_iam_member` (aditivo). Nunca `_iam_binding` nem `_iam_policy`:
# eles apagariam o que não está declarado aqui (service agents, owner etc.).
#
# Aplicado à mão pela bjjsystem25, nunca pelo CI.

data "google_project" "atual" {
  project_id = var.project_id
}

locals {
  numero_projeto = data.google_project.atual.number
  pool_id        = "github-pool"

  # Conta de deploy => repositório do GitHub que a usa pelo WIF.
  # Hoje cada conta de deploy também é a conta de runtime do próprio serviço
  # (usar_conta_deploy_para_runtime = true no backend e no face).
  contas_deploy = {
    "sys-bjj-backend-deploy"     = "cadusds2/sys-bjj-backend"
    "sys-bjj-backend-hom-deploy" = "cadusds2/sys-bjj-backend"
    "sys-bjj-face-deploy"        = "cadusds2/sys-bjj-face"
    "sys-bjj-face-hom-deploy"    = "cadusds2/sys-bjj-face"
    "sys-bjj-frontend-deploy"    = "matheusnaziel/sys-bjj-frontend"
    "sys-bjj-mcp-deploy"         = "cm-tech-ventures/sys-bjj-mcp"
  }

  # Papéis de projeto de cada conta de deploy, como estão.
  papeis_deploy = {
    "sys-bjj-backend-deploy" = [
      "roles/artifactregistry.admin",
      "roles/artifactregistry.reader",
      "roles/cloudscheduler.admin",
      "roles/iam.serviceAccountAdmin",
      "roles/iam.serviceAccountUser",
      "roles/logging.logWriter",
      "roles/resourcemanager.projectIamAdmin",
      "roles/run.admin",
      "roles/secretmanager.admin",
      "roles/secretmanager.secretAccessor",
      "roles/serviceusage.serviceUsageAdmin",
      "roles/storage.objectAdmin",
      "roles/storage.objectViewer",
    ]
    "sys-bjj-backend-hom-deploy" = [
      "roles/artifactregistry.admin",
      "roles/artifactregistry.reader",
      "roles/cloudscheduler.admin",
      "roles/iam.serviceAccountAdmin",
      "roles/iam.serviceAccountUser",
      "roles/logging.logWriter",
      "roles/run.admin",
      "roles/secretmanager.admin",
      "roles/secretmanager.secretAccessor",
    ]
    "sys-bjj-face-deploy" = [
      "roles/artifactregistry.admin",
      "roles/artifactregistry.reader",
      "roles/iam.serviceAccountAdmin",
      "roles/iam.serviceAccountUser",
      "roles/logging.logWriter",
      "roles/resourcemanager.projectIamAdmin",
      "roles/run.admin",
      "roles/secretmanager.admin",
      "roles/serviceusage.serviceUsageAdmin",
    ]
    "sys-bjj-face-hom-deploy" = [
      "roles/artifactregistry.admin",
      "roles/artifactregistry.reader",
      "roles/iam.serviceAccountAdmin",
      "roles/iam.serviceAccountUser",
      "roles/logging.logWriter",
      "roles/run.admin",
    ]
    "sys-bjj-frontend-deploy" = [
      "roles/artifactregistry.admin",
      "roles/artifactregistry.reader",
      "roles/iam.serviceAccountAdmin",
      "roles/iam.serviceAccountUser",
      "roles/logging.logWriter",
      "roles/resourcemanager.projectIamAdmin",
      "roles/run.admin",
      "roles/secretmanager.admin",
      "roles/secretmanager.secretAccessor",
      "roles/serviceusage.serviceUsageAdmin",
      "roles/storage.objectAdmin",
      "roles/storage.objectViewer",
    ]
    "sys-bjj-mcp-deploy" = [
      "roles/artifactregistry.writer",
      "roles/iam.serviceAccountAdmin",
      "roles/run.admin",
    ]
  }

  # Papéis no bucket de state, por conta de deploy. Os bindings legados de
  # conveniência (projectOwner/projectEditor/projectViewer) ficam fora.
  papeis_bucket_state = {
    "sys-bjj-backend-deploy"     = ["roles/storage.admin", "roles/storage.objectAdmin"]
    "sys-bjj-backend-hom-deploy" = ["roles/storage.objectAdmin"]
    "sys-bjj-face-deploy"        = ["roles/storage.admin", "roles/storage.objectAdmin"]
    "sys-bjj-face-hom-deploy"    = ["roles/storage.objectAdmin"]
    "sys-bjj-frontend-deploy"    = ["roles/storage.objectAdmin"]
    "sys-bjj-mcp-deploy"         = ["roles/storage.objectAdmin"]
  }

  # Contas de fora do projeto, com o que têm aqui.
  papeis_externos = {
    # Sink de log para o bronze_logs (environments/log-sinks). Os outros 7
    # papéis dela no bjj-system ficam fora de propósito: saem na etapa 18.
    "user:cm.tech.ventures@gmail.com" = ["roles/logging.configWriter"]
    # Backoffice só lê (o cloudscheduler.admin de prod é para pausar/disparar job).
    "serviceAccount:cm-backoffice-run@cm-ventures-core.iam.gserviceaccount.com" = [
      "roles/cloudscheduler.admin",
      "roles/logging.viewer",
      "roles/run.viewer",
    ]
    "serviceAccount:cm-backoffice-hom-run@cm-ventures-core.iam.gserviceaccount.com" = [
      "roles/cloudscheduler.viewer",
      "roles/logging.viewer",
      "roles/run.viewer",
    ]
  }

  # Chaves "<conta> <papel>", legíveis no plan.
  deploy_projeto = merge([
    for sa, papeis in local.papeis_deploy : {
      for p in papeis : "${sa} ${p}" => { sa = sa, papel = p }
    }
  ]...)
  deploy_bucket_state = merge([
    for sa, papeis in local.papeis_bucket_state : {
      for p in papeis : "${sa} ${p}" => { sa = sa, papel = p }
    }
  ]...)
  externos_projeto = merge([
    for membro, papeis in local.papeis_externos : {
      for p in papeis : "${membro} ${p}" => { membro = membro, papel = p }
    }
  ]...)

  # WIF: cada conta de deploy aceita o repositório dela, com os dois papéis.
  wif = merge([
    for sa, repo in local.contas_deploy : {
      for p in ["roles/iam.workloadIdentityUser", "roles/iam.serviceAccountTokenCreator"] :
      "${sa} ${p}" => {
        sa     = sa
        papel  = p
        membro = "principalSet://iam.googleapis.com/projects/${local.numero_projeto}/locations/global/workloadIdentityPools/${local.pool_id}/attribute.repository/${repo}"
      }
    }
  ]...)
}

# --- Contas de deploy ---

resource "google_service_account" "deploy" {
  for_each = local.contas_deploy

  project      = var.project_id
  account_id   = each.key
  display_name = "Conta de serviço de deploy para ${trimsuffix(each.key, "-deploy")}"
}

# --- WIF do GitHub ---

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = local.pool_id
  display_name              = "GitHub Pool"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub Provider"

  # Só estes 4 repositórios entram. Hoje sem filtro de branch: a etapa 18 faz
  # a conta de prod aceitar só main (regra 3).
  attribute_condition = join(" || ", [
    for repo in distinct(values(local.contas_deploy)) : "assertion.repository == \"${repo}\""
  ])

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "wif" {
  for_each = local.wif

  service_account_id = google_service_account.deploy[each.value.sa].name
  role               = each.value.papel
  member             = each.value.membro
}

# O backend assina URL do Cloud Storage delegando para si mesmo (signBlob na
# IAM Credentials API). Ver core/settings.py do sys-bjj-backend (CMV-630).
resource "google_service_account_iam_member" "backend_assina_urls" {
  service_account_id = google_service_account.deploy["sys-bjj-backend-deploy"].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.deploy["sys-bjj-backend-deploy"].email}"
}

# --- Papéis de projeto ---

resource "google_project_iam_member" "deploy" {
  for_each = local.deploy_projeto

  project = var.project_id
  role    = each.value.papel
  member  = "serviceAccount:${google_service_account.deploy[each.value.sa].email}"
}

resource "google_project_iam_member" "externos" {
  for_each = local.externos_projeto

  project = var.project_id
  role    = each.value.papel
  member  = each.value.membro
}

# --- Bucket de state do Terraform ---

resource "google_storage_bucket_iam_member" "state" {
  for_each = local.deploy_bucket_state

  bucket = "terraform-backend-sys-bjj"
  role   = each.value.papel
  member = "serviceAccount:${google_service_account.deploy[each.value.sa].email}"
}
