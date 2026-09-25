variable "project_id" {
  description = "ID do projeto GCP."
  type        = string
  default     = "cm-ventures-core"
}

variable "region" {
  description = "Região padrão do provider."
  type        = string
  default     = "southamerica-east1"
}

variable "canais" {
  description = <<-EOT
    IDs dos canais de notificação, por caixa. Os canais são criados À MÃO
    (e-mail exige clique de verificação; Slack exige OAuth) e aqui só se
    consome o id — ver o comentário no modules/alerta-generico/main.tf.

    Listar os ids:
      gcloud beta monitoring channels list --project=cm-ventures-core
  EOT
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["dinheiro", "interno"] : contains(keys(var.canais), k)])
    error_message = "Defina as duas caixas: 'dinheiro' e 'interno'."
  }
}
