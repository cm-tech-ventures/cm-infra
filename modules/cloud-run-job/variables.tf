variable "job_name" {
  description = "Nome do Cloud Run Job (ex: keepalive-check). Genérico: nunca nome de vertical."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,48}$", var.job_name))
    error_message = "job_name deve ser kebab-case minúsculo (3-49 chars)."
  }
}

variable "project_id" {
  description = "ID do projeto GCP."
  type        = string
}

variable "region" {
  description = "Região do Cloud Run Job."
  type        = string
}

variable "environment" {
  description = "Ambiente (prod, staging). Nunca hardcodar prod em recursos."
  type        = string
  default     = "prod"
}

variable "image" {
  description = "URI completa da imagem no Artifact Registry, preferencialmente com digest."
  type        = string
}

variable "command" {
  description = "Override do entrypoint da imagem. Vazio = usa o ENTRYPOINT/CMD da imagem."
  type        = list(string)
  default     = []
}

variable "env" {
  description = "Variáveis de ambiente NÃO sensíveis. Nunca colocar segredo aqui."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = <<-EOT
    Map nome-da-env => referência ao Secret Manager. Injetado via secret_key_ref;
    nenhum valor literal entra no TF state. Secret precisa já existir (provisionado
    out-of-band) — este módulo só concede leitura à SA de runtime do job.
    Ex: { KEEPALIVE_DB_DSNS = { secret = "keepalive-db-dsns", version = "latest" } }
  EOT
  type = map(object({
    secret  = string
    version = optional(string, "latest")
  }))
  default = {}
}

variable "cpu" {
  description = "CPU por execução."
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memória por execução. Mínimo 512Mi (execução gen2 com CPU sempre alocada)."
  type        = string
  default     = "512Mi"
}

variable "timeout" {
  description = "Timeout de cada tentativa (ex: '300s')."
  type        = string
  default     = "300s"
}

variable "max_retries" {
  description = "Retries por execução falha antes de marcar a execution como failed."
  type        = number
  default     = 0
}

variable "deployer_service_account" {
  description = "Email da SA de deploy (WIF) que pode atuar como a SA do job. Vazio = não concede."
  type        = string
  default     = ""
}

variable "invoker_service_account" {
  description = "Email da SA autorizada a disparar a execução do job (ex: SA do Cloud Scheduler). Vazio = não concede."
  type        = string
  default     = ""
}
