variable "project_id" {
  description = "Projeto GCP de onde saem os logs (onde o sink é criado)."
  type        = string
}

variable "nome" {
  # O nome ficou da época do raw_logs (cm-infra#55/#56). Trocar o nome recria o
  # sink e abre uma janela sem gravação; a troca do destino é in-place.
  description = "Nome do sink no projeto de origem."
  type        = string
  default     = "eventos-para-raw-logs"
}

variable "descricao" {
  description = "Descrição do sink, visível no console do Logging."
  type        = string
  default     = "Eventos estruturados (cm_sdk.observabilidade) com env=prod para o bronze_logs do cm-ventures-core. Gerido pelo cm-infra (environments/log-sinks)."
}

variable "dataset_project_id" {
  description = "Projeto do dataset de destino."
  type        = string
  default     = "cm-ventures-core"
}

variable "dataset_id" {
  description = "Id do dataset de destino. Ele precisa existir: é lido por data source, não criado."
  type        = string
  default     = "bronze_logs"
}

variable "filtro" {
  description = "Filtro do sink. Vazio usa o padrão: Cloud Run (serviço ou job), com jsonPayload.event e jsonPayload.env=\"prod\"."
  type        = string
  default     = null
}
