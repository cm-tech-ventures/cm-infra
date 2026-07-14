variable "repository_id" {
  description = "ID do repositório Docker no Artifact Registry."
  type        = string
}

variable "project_id" {
  description = "ID do projeto GCP."
  type        = string
}

variable "region" {
  description = "Região do repositório."
  type        = string
}

variable "description" {
  description = "Descrição do repositório."
  type        = string
  default     = "Imagens Docker dos cores CM Ventures"
}

variable "readers" {
  description = "Emails de service accounts com permissão de leitura (pull) — SAs de runtime dos serviços."
  type        = list(string)
  default     = []
}

variable "writers" {
  description = "Emails de service accounts com permissão de push — SA de deploy federada (WIF)."
  type        = list(string)
  default     = []
}
