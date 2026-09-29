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

variable "pacotes_protegidos" {
  description = <<-EOT
    Pacotes (um por serviço) cujas N últimas versões nunca são apagadas, N = manter_versoes.
    Cada entrada vira uma política KEEP própria com package_name_prefixes, em vez de uma
    política única para o repositório inteiro: num repo compartilhado, "as 10 mais recentes"
    sem prefixo pode proteger só quem fez deploy por último e apagar a imagem viva de quem
    não faz deploy há meses. Lista vazia desliga a retenção.
  EOT
  type        = list(string)
  default     = []
}

variable "manter_versoes" {
  description = "Quantas versões recentes proteger por pacote."
  type        = number
  default     = 10
}

variable "apagar_apos_dias" {
  description = "Idade a partir da qual uma versão não protegida é apagada."
  type        = number
  default     = 30
}

variable "retencao_dry_run" {
  description = <<-EOT
    true = o Artifact Registry avalia as políticas e REGISTRA NO LOG o que apagaria, sem
    apagar nada. Serve para conferir o alcance antes de valer de verdade. Apagar versão de
    imagem é irreversível: comece em true, leia o log, só então vire para false.
  EOT
  type        = bool
  default     = true
}
