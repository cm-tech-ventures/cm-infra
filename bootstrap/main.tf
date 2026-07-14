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
  ]
}

resource "google_project_service" "apis" {
  for_each           = toset(local.required_apis)
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
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

  # Trust restrito: owner correto E repo na allowlist.
  attribute_condition = "assertion.repository_owner == \"${var.github_owner}\" && assertion.repository in ${jsonencode(var.github_repositories)}"

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
resource "google_project_iam_member" "deployer_roles" {
  for_each = toset([
    "roles/run.admin",
    "roles/artifactregistry.writer",
    "roles/cloudscheduler.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/secretmanager.viewer",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_storage_bucket_iam_member" "deployer_state" {
  bucket = google_storage_bucket.tf_state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.deployer.email}"
}

# --- Artifact Registry compartilhado dos cores ---
module "artifact_registry" {
  source        = "../modules/artifact-registry"
  project_id    = var.project_id
  region        = var.region
  repository_id = "cm-cores"
  writers       = [google_service_account.deployer.email]
}
