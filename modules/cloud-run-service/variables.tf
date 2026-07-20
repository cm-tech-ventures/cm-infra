variable "service_name" {
  description = "Nome do serviço Cloud Run (ex: cm-identity). Genérico: nunca nome de vertical."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,48}$", var.service_name))
    error_message = "service_name deve ser kebab-case minúsculo (3-49 chars)."
  }
}

variable "project_id" {
  description = "ID do projeto GCP."
  type        = string
}

variable "region" {
  description = "Região do Cloud Run."
  type        = string
}

variable "environment" {
  description = "Ambiente (prod, staging). Nunca hardcodar prod em recursos."
  type        = string
  default     = "prod"
}

variable "image" {
  description = "URI completa da imagem no Artifact Registry, preferencialmente com digest (…@sha256:…)."
  type        = string
}

variable "env" {
  description = "Variáveis de ambiente NÃO sensíveis (ex: DJANGO_DB_SCHEMA). Nunca colocar segredo aqui."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = <<-EOT
    Map nome-da-env => referência ao Secret Manager. Injetado via secret_key_ref;
    nenhum valor literal entra no TF state.
    Ex: { DATABASE_URL = { secret = "cm-identity-database-url", version = "latest" } }
  EOT
  type = map(object({
    secret  = string
    version = optional(string, "latest")
  }))
  default = {}
}

variable "custom_domain" {
  description = "Domínio custom opcional (ex: api.exemplo.com). Vazio = sem domain mapping."
  type        = string
  default     = ""
}

variable "min_instances" {
  description = "Instâncias mínimas. Default 0 (scale-to-zero)."
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "Instâncias máximas."
  type        = number
  default     = 3
}

variable "cpu" {
  description = "CPU por instância."
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memória por instância."
  type        = string
  default     = "512Mi"
}

variable "container_port" {
  description = "Porta exposta pelo container."
  type        = number
  default     = 8080
}

variable "allow_unauthenticated" {
  description = "Permite invocação pública sem IAM. Default false."
  type        = bool
  default     = false
}

variable "release_command" {
  description = <<-EOT
    Comando do Cloud Run Job de release (schema + migrate), executado pelo
    deploy-cloud-run.yml antes de servir tráfego na nova revisão. Default
    assume o management command `release` do cm-service-template (CMV-39).
    Use [] para serviços sem etapa de release (ex. frontend Node/Next.js —
    CMV-136): o Job nem é criado, e deploy-cloud-run.yml pula a execução.
  EOT
  type        = list(string)
  default     = ["python", "manage.py", "release"]
}

variable "deployer_service_account" {
  description = "Email da SA de deploy (WIF) que pode atuar como a SA do serviço. Vazio = não concede."
  type        = string
  default     = ""
}
