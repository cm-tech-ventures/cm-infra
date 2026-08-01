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

variable "iap_authorized_members" {
  description = <<-EOT
    Lista de identidades IAM autorizadas a acessar o site via IAP, cada uma no
    formato aceito por `member` do IAM ('user:pessoa@dominio.com' ou
    'group:nome-do-grupo@googlegroups.com'). Deve conter exatamente quem tem
    direito de visualizar o dashboard (ex: board + dono do MD).

    Contas GCP sem organização/Workspace não têm domínio para um Google Group
    gerenciado — nesse caso, use `user:` diretamente para cada pessoa. Se no
    futuro existir um Workspace, prefira um único `group:...@googlegroups.com`
    ou grupo de domínio para não precisar tocar Terraform a cada troca de membro.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.iap_authorized_members) > 0
    error_message = "iap_authorized_members não pode ser vazio."
  }

  validation {
    condition = alltrue([
      for m in var.iap_authorized_members : can(regex("^(user|group|serviceAccount|domain):.+", m))
    ])
    error_message = "cada membro deve estar no formato 'user:...', 'group:...', 'serviceAccount:...' ou 'domain:...'."
  }
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
