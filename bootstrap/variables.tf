variable "project_id" {
  description = "ID do projeto GCP."
  type        = string
}

variable "region" {
  description = "Região default (bucket de state, Artifact Registry)."
  type        = string
  default     = "southamerica-east1"
}

variable "environment" {
  description = "Ambiente. Único prod hoje, preparado para staging."
  type        = string
  default     = "prod"
}

variable "github_owner" {
  description = "Owner/org do GitHub autorizado no WIF (ex: cm-ventures)."
  type        = string
}

variable "github_repositories" {
  description = "Repos (owner/name) autorizados a assumir a SA de deploy. Trust restrito por repo, não só por owner."
  type        = list(string)
}

variable "state_bucket_name" {
  description = "Nome do bucket GCS de state do Terraform."
  type        = string
}

variable "ops_observer_impersonators" {
  description = "Identidades (formato IAM member, ex: user:foo@bar.com) autorizadas a assumir a SA cm-ops-observer via impersonation (CMV-319)."
  type        = list(string)
  default     = []
}

variable "billing_account_id" {
  description = "ID da billing account (formato XXXXXX-XXXXXX-XXXXXX) para conceder roles/billing.viewer à SA cm-ops-observer. Vazio pula o grant (CMV-319)."
  type        = string
  default     = ""
}

variable "dbt_pipeline_service_account" {
  description = "E-mail da SA do Cloud Run Job do pipeline dbt do cm-analytics, autorizada como dataViewer no dataset raw_mcp_logs (CMV-594)."
  type        = string
}
