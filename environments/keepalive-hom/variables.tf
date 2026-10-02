variable "project_id" {
  description = "ID do projeto GCP. Homologação divide o projeto com produção — não existe projeto de hom para os cores."
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
  default     = "hom"
}

variable "image" {
  description = "URI completa da imagem jobs/keepalive. A mesma de produção: o que muda entre ambientes é a lista de bancos, não o código."
  type        = string
}

variable "schedule" {
  description = <<-EOT
    Cron do keep-alive de homologação. Deslocado em uma hora do de produção
    (07:00 contra 06:00) de propósito: com os dois no mesmo minuto, um teste de
    "disparar agora" pelo Backoffice ficaria indistinguível do disparo
    automático do outro na leitura de execuções.
  EOT
  type        = string
  default     = "0 7 */3 * *"
}

variable "notification_email" {
  description = "E-mail que recebe o alerta de falha. Homologação falhando não é incidente, mas silêncio total ensina a ignorar o painel."
  type        = string
}

variable "keepalive_secret_id" {
  description = <<-EOT
    ID do secret com os DSNs. O default aponta para o MESMO secret de produção,
    que já inclui os dois bancos de homologação (cm-ventures-core-hom e
    bjj-system-hom): assim este ambiente nasce sem precisar de credencial nova.
    A consequência é que os pings ficam redundantes com os de produção — custo
    irrelevante numa rotina a cada 3 dias.
    Para separar de verdade, crie um secret só com os DSNs de hom, aponte esta
    variável para ele e tire os dois de hom do secret de produção. Nessa ordem,
    nunca na inversa.
  EOT
  type        = string
  default     = "keepalive-db-dsns"
}
