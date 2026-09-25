variable "nome" {
  description = "Identificador curto do alerta, em kebab-case. Vira parte do nome da métrica derivada de log."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.nome))
    error_message = "Use só minúsculas, números e hífen."
  }
}

variable "titulo" {
  description = "Nome da política como aparece no console e no assunto da notificação."
  type        = string
}

variable "project_id" {
  description = "ID do projeto GCP onde a política é criada. Canal e política precisam viver no mesmo projeto."
  type        = string
}

variable "sensor" {
  description = "Que tipo de morte este alerta enxerga: 'scheduler' (o relógio tocou e a chamada falhou) ou 'job' (a execução nasceu e morreu no meio)."
  type        = string

  validation {
    condition     = contains(["scheduler", "job"], var.sensor)
    error_message = "sensor deve ser 'scheduler' ou 'job'."
  }
}

variable "alvo" {
  description = "Nomes dos jobs vigiados. Lista VAZIA significa todos do projeto, inclusive os que ainda não existem — é o padrão para a caixa de digestão."
  type        = list(string)
  default     = []
}

variable "canal_id" {
  description = "ID do canal de notificação já existente (criado à mão, ver comentário no main.tf). Formato: projects/<p>/notificationChannels/<n>."
  type        = string
}

variable "severidade" {
  description = "ERROR na caixa que interrompe, WARNING na de digestão."
  type        = string
  default     = "ERROR"

  validation {
    condition     = contains(["CRITICAL", "ERROR", "WARNING"], var.severidade)
    error_message = "severidade deve ser CRITICAL, ERROR ou WARNING."
  }
}

variable "janela" {
  description = "Janela de agregação. Deve cobrir pelo menos um ciclo da rotina vigiada, senão o alerta fecha antes de você ver."
  type        = string
  default     = "3600s"
}

variable "limite_frequencia" {
  description = "Intervalo mínimo entre notificações. Vazio = sem limite, e é o certo para a caixa que interrompe. Use '86400s' na de digestão."
  type        = string
  default     = ""
}

variable "documentacao" {
  description = "O que o seu eu futuro precisa saber às 23h. Vai no corpo da notificação — escreva onde olhar, não o que aconteceu."
  type        = string
}

variable "espera_propagacao" {
  description = "Tempo entre criar a métrica derivada de log e criar a política que a referencia. O descritor leva alguns minutos para aparecer na API do Monitoring; sem isto o primeiro apply falha com 404."
  type        = string
  default     = "360s"
}
