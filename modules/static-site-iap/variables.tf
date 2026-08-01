variable "name" {
  description = "Nome base do site estático (kebab-case). Usado como prefixo do bucket e do serviço Cloud Run proxy."
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
  description = "Região usada para o bucket e o serviço proxy (Cloud Run)."
  type        = string
}

variable "oauth2_proxy_image" {
  description = <<-EOT
    Imagem de container do oauth2-proxy (sidecar de ingress/autenticação).
    Deve ser fixada por tag de versão específica (idealmente com digest) —
    nunca "latest". Ex: "quay.io/oauth2-proxy/oauth2-proxy:v7.6.0".
  EOT
  type        = string

  validation {
    condition     = !endswith(var.oauth2_proxy_image, ":latest") && can(regex(":", var.oauth2_proxy_image))
    error_message = "oauth2_proxy_image deve ser fixada por tag/digest específico, nunca ':latest' ou sem tag."
  }
}

variable "oauth2_proxy_port" {
  description = "Porta pública (ingress) em que o oauth2-proxy escuta. Deve casar com $PORT injetado pelo Cloud Run."
  type        = number
  default     = 8080
}

variable "proxy_internal_port" {
  description = "Porta interna (localhost) em que o container `proxy` (leitor do bucket) escuta, sem exposição no ingress."
  type        = number
  default     = 8081
}

variable "oauth2_proxy_redirect_url" {
  description = <<-EOT
    URL de callback OAuth do oauth2-proxy (ex: "https://<nome-serviço>-<hash>.<região>.run.app/oauth2/callback").
    Precisa ser configurada como redirect URI autorizada no OAuth client (ação manual no console GCP).
  EOT
  type        = string
}

variable "oauth2_proxy_cookie_expire" {
  description = "Expiração do cookie de sessão do oauth2-proxy. Nunca deve exceder 24h."
  type        = string
  default     = "12h"

  validation {
    condition     = can(regex("^([0-9]+h|[0-9]+m)$", var.oauth2_proxy_cookie_expire))
    error_message = "oauth2_proxy_cookie_expire deve estar em formato de duração Go (ex: '12h', '90m')."
  }
}

variable "oauth_client_id_secret_id" {
  description = "ID do secret (Secret Manager) com o client_id do OAuth client (Google) usado pelo oauth2-proxy."
  type        = string
}

variable "oauth_client_secret_secret_id" {
  description = "ID do secret (Secret Manager) com o client_secret do OAuth client (Google) usado pelo oauth2-proxy."
  type        = string
}

variable "cookie_secret_id" {
  description = "ID do secret (Secret Manager) com o cookie_secret do oauth2-proxy (32 bytes aleatórios, base64)."
  type        = string
}

variable "allowed_emails_secret_id" {
  description = <<-EOT
    ID do secret (Secret Manager) com a allowlist de e-mails autorizados a acessar
    o dashboard (um e-mail por linha) — consumido via --authenticated-emails-file
    do oauth2-proxy. Nunca hardcoded no Terraform.
  EOT
  type        = string
}

variable "runtime_service_account_email" {
  description = <<-EOT
    E-mail da service account de runtime do job de publicação (dlt->dbt->Evidence).
    Escreve as builds versionadas ("releases/<versão>/...") e o objeto-ponteiro no
    bucket. Tipicamente o output service_account_email do módulo cloud-run-job do
    pipeline de publicação. Não precisa de nenhuma permissão de rede/LB — só write
    no bucket.
  EOT
  type        = string
}

variable "proxy_image" {
  description = <<-EOT
    Imagem de container do serviço proxy (Cloud Run) que lê o objeto-ponteiro do
    bucket e serve os arquivos de "releases/<versão>/..." correspondentes.
    Stateless, somente leitura, sem lógica de negócio — publicada pelo workflow
    reusável build-and-push do próprio repositório do core (ex: cm-analytics).
  EOT
  type        = string
}

variable "proxy_max_instances" {
  description = "Máximo de instâncias do Cloud Run service proxy (min_instance_count é sempre 0 — nenhum worker permanente)."
  type        = number
  default     = 3
}

variable "pointer_object_name" {
  description = <<-EOT
    Nome do objeto-ponteiro no bucket cujo conteúdo é a versão ("releases/<versão>/")
    atualmente publicada. O job de publicação só sobrescreve este objeto depois que
    dlt+dbt (testes + freshness) passarem; o proxy lê este objeto a cada request (ou
    com cache curto) para decidir qual versão servir.
  EOT
  type        = string
  default     = "current-release"
}
