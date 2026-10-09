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

variable "metabase_impersonators" {
  description = "Identidades (formato IAM member) com roles/iam.serviceAccountTokenCreator só na SA analytics-bq-metabase, para o Metabase local da plataforma de dados (fase 3)."
  type        = list(string)
  default     = ["user:cm.tech.ventures@gmail.com"]
}

variable "billing_account_id" {
  description = "ID da billing account (formato XXXXXX-XXXXXX-XXXXXX) para conceder roles/billing.viewer à SA cm-ops-observer. Vazio pula o grant (CMV-319)."
  type        = string
  default     = ""
}

variable "mcp_logs_external_sink_writer_identities" {
  description = <<-EOT
    Writer identities (member IAM completo, ex: "serviceAccount:p123-abc@gcp-sa-logging.iam.gserviceaccount.com")
    de sinks de Cloud Logging cross-project que escrevem no dataset raw_mcp_logs — um por projeto GCP onde um
    core/serviço da família MD roda (ex: md-hom para o md-mcp, CMV-599). Cada sink é provisionado no repo do
    serviço (fora deste), que expõe o writer_identity como output depois do primeiro apply; o valor entra aqui
    manualmente porque não há trust de deploy cross-project entre os dois state (mesmo padrão do secret
    IDENTITY_INTROSPECTION_CORE_KEY documentado em md-backend/mcp_server/infra/main.tf).
  EOT
  type        = list(string)
  default     = []
}

variable "retencao_dry_run" {
  description = "Repassado ao módulo artifact-registry: true faz o AR só registrar no log o que apagaria."
  type        = bool
  default     = true
}

variable "secrets_leitores_externos" {
  description = <<-EOT
    Leitura cruzada de secrets do core: nome curto do secret (neste projeto) => members IAM de
    outros projetos com roles/secretmanager.secretAccessor nele (cm-infra#73). Só leitura; admin
    cruzado não entra aqui.
  EOT
  type        = map(list(string))
  default     = {}
}

# --- SA de ensaio (ensaio.tf, cm-infra#74) ---
# As listas não têm default de propósito: um terraform.tfvars antigo, sem elas,
# faz o plan falhar em vez de criar uma SA de ensaio sem actAs nem datasets (que
# reprovaria o ensaio por motivo falso). Valores em terraform.tfvars.example.

variable "ensaio_habilitado" {
  description = "Cria a SA temporária deployer-ensaio e os papéis dela. false no fim da frente: o plan só destrói o que está em ensaio.tf."
  type        = bool
  default     = true
}

variable "ensaio_impersonadores" {
  description = "Members IAM com roles/iam.serviceAccountTokenCreator na SA deployer-ensaio (binding na SA). Só pessoas, nunca SA nem WIF."
  type        = list(string)
}

variable "ensaio_act_as_service_accounts" {
  description = "account_id das SAs do projeto onde o deployer tem roles/iam.serviceAccountUser por recurso. A SA de ensaio recebe o mesmo, SA a SA."
  type        = list(string)
}

variable "ensaio_datasets_dono" {
  description = "Datasets BigQuery onde o deployer é OWNER e segue sendo depois das etapas 11 e 14. A SA de ensaio recebe roles/bigquery.dataOwner."
  type        = list(string)
}

variable "ensaio_datasets_leitura" {
  description = "Datasets BigQuery onde o deploy só lê. A SA de ensaio recebe roles/bigquery.dataViewer."
  type        = list(string)
}
