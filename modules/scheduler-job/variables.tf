variable "name" {
  description = "Nome do job no Cloud Scheduler."
  type        = string
}

variable "project_id" {
  description = "ID do projeto GCP."
  type        = string
}

variable "region" {
  description = "Região do Cloud Scheduler."
  type        = string
}

variable "schedule" {
  description = "Expressão cron (ex: '*/15 * * * *')."
  type        = string
}

variable "time_zone" {
  description = "Timezone do agendamento."
  type        = string
  default     = "America/Sao_Paulo"
}

variable "target_uri" {
  description = "URI alvo: endpoint HTTP do serviço Cloud Run ou URI de execução de Cloud Run Job."
  type        = string
}

variable "oidc_service_account" {
  description = "Email da SA usada para autenticar a chamada via OIDC (SA do próprio core)."
  type        = string
}

variable "oidc_audience" {
  description = "Audience do token OIDC. Vazio = usa o target_uri."
  type        = string
  default     = ""
}

variable "http_method" {
  description = "Método HTTP da chamada."
  type        = string
  default     = "POST"

  validation {
    condition     = contains(["GET", "POST", "PUT", "PATCH", "DELETE"], var.http_method)
    error_message = "http_method deve ser GET, POST, PUT, PATCH ou DELETE."
  }
}

variable "body" {
  description = "Corpo JSON da requisição (string). Vazio = sem body."
  type        = string
  default     = ""
}

variable "attempt_deadline" {
  description = "Deadline da tentativa."
  type        = string
  default     = "320s"
}

variable "retry_count" {
  description = "Número de retries em falha."
  type        = number
  default     = 1
}
