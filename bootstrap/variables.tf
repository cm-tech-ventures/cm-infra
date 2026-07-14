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
