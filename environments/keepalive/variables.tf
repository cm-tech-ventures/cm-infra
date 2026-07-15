variable "project_id" {
  description = "ID do projeto GCP."
  type        = string
  default     = "cm-ventures-core"
}

variable "region" {
  description = "Região dos recursos."
  type        = string
  default     = "southamerica-east1"
}

variable "environment" {
  description = "Ambiente."
  type        = string
  default     = "prod"
}

variable "image" {
  description = "URI completa (com tag ou digest) da imagem jobs/keepalive publicada no Artifact Registry."
  type        = string
}

variable "schedule" {
  description = "Cron do keep-alive. Padrão: a cada 3 dias às 06:00 (folga sobre a janela de inatividade do free-tier Supabase, tipicamente 7 dias)."
  type        = string
  default     = "0 6 */3 * *"
}

variable "notification_email" {
  description = "E-mail do board que recebe o alerta de falha do keep-alive."
  type        = string
}

variable "keepalive_secret_id" {
  description = "ID do secret no Secret Manager com os DSNs (';'-separado), provisionado out-of-band."
  type        = string
  default     = "keepalive-db-dsns"
}
