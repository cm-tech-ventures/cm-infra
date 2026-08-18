variable "project_id" {
  description = "ID do projeto GCP."
  type        = string
}

variable "service_name" {
  description = "Nome do serviço Cloud Run monitorado (resource.labels.service_name)."
  type        = string
}

variable "log_event" {
  description = <<-EOT
    Valor do campo `event` do log estruturado JSON a contar (ex: "http_request",
    "tool_call"). Deve casar com o `event` emitido pelo helper de observabilidade
    do serviço (cm-service-template: service/common/observability).
  EOT
  type        = string
  default     = "http_request"
}

variable "label_field" {
  description = <<-EOT
    Campo do log estruturado usado para rotular a métrica (ex: "path", "tool",
    "operation"). Precisa existir no JSON logado em todo evento.
  EOT
  type        = string
  default     = "path"
}

variable "error_threshold" {
  description = "Contagem de erros na janela `alignment_period` que dispara o alerta."
  type        = number
  default     = 5
}

variable "alignment_period" {
  description = "Janela de agregação da condição (ex: '300s')."
  type        = string
  default     = "300s"
}

variable "notification_channel_id" {
  description = "ID do canal de notificação (google_monitoring_notification_channel). Vazio = política criada sem notificar ninguém."
  type        = string
  default     = ""
}
