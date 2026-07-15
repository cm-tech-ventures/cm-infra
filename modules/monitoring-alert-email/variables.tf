variable "project_id" {
  description = "ID do projeto GCP."
  type        = string
}

variable "notification_email" {
  description = "E-mail que recebe o alerta (board)."
  type        = string
}

variable "alert_display_name" {
  description = "Nome do canal de notificação e prefixo da política de alerta."
  type        = string
}

variable "job_name" {
  description = "Nome do Cloud Run Job monitorado (resource.label.job_name)."
  type        = string
}

variable "location" {
  description = "Região do Cloud Run Job (resource.label.location)."
  type        = string
}

variable "alignment_period" {
  description = "Janela de agregação da condição (ex: '3600s'). Deve cobrir pelo menos um ciclo de execução do job."
  type        = string
  default     = "3600s"
}
