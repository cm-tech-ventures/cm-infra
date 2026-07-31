variable "name" {
  description = "Nome base do site estático (kebab-case). Usado como prefixo dos buckets, backends e recursos de rede."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,40}$", var.name))
    error_message = "name deve ser kebab-case minúsculo (3-41 chars)."
  }
}

variable "project_id" {
  description = "ID do projeto GCP."
  type        = string
}

variable "region" {
  description = "Região usada para o Cloud Storage dos buckets do site. O Load Balancer em si é global."
  type        = string
}

variable "iap_oauth_client_id" {
  description = <<-EOT
    Client ID do OAuth2 usado pelo IAP. Precisa ser criado MANUALMENTE no console GCP
    (tela "OAuth consent screen" / "Credentials" do projeto) antes do apply — não é
    terraformável sem permissão de admin de organização. Ver README.md deste módulo.
  EOT
  type        = string
  sensitive   = true
}

variable "iap_oauth_client_secret" {
  description = "Client Secret correspondente ao iap_oauth_client_id. Também criado manualmente no console GCP."
  type        = string
  sensitive   = true
}

variable "iap_authorized_group" {
  description = <<-EOT
    Identidade do Google Group autorizado a acessar o site via IAP, no formato
    'group:nome-do-grupo@dominio.com'. Deve conter exatamente os membros com direito
    de visualizar o dashboard (ex: board + dono do MD). Nunca hardcodar e-mail
    individual real neste módulo — sempre um grupo gerenciado no Google Workspace.
  EOT
  type        = string
}

variable "runtime_service_account_email" {
  description = <<-EOT
    E-mail da service account de runtime que publica o site (escreve os arquivos
    estáticos nos buckets e flipa o url_map após uma build bem-sucedida). Tipicamente
    o output service_account_email do módulo cloud-run-job do pipeline de publicação.
  EOT
  type        = string
}

variable "active_color" {
  description = <<-EOT
    Cor ativa no momento do apply inicial do Terraform ("blue" ou "green"). Após o
    primeiro apply, o Terraform NUNCA mais altera qual cor está ativa — isso é feito
    pelo próprio job de publicação via chamada à Compute API (urlMaps.patch /
    setDefaultService), de forma atômica, fora do Terraform. Ver README.md.
  EOT
  type        = string
  default     = "blue"

  validation {
    condition     = contains(["blue", "green"], var.active_color)
    error_message = "active_color deve ser 'blue' ou 'green'."
  }
}
