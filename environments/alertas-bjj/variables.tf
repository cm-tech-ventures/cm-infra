variable "project_id" {
  description = "ID do projeto GCP."
  type        = string
  default     = "bjj-system"
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
      gcloud beta monitoring channels list --project=bjj-system
  EOT
  type        = map(string)

  validation {
    condition     = contains(keys(var.canais), "dinheiro")
    error_message = "Defina a caixa 'dinheiro'. O bjj-system não tem caixa de digestão."
  }
}
