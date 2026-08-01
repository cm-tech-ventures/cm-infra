# Módulo genérico de publicação de site estático via Cloud Run + oauth2-proxy
# (sem Load Balancer/domínio próprio — decisão do board de 2026-08-01, CMV-346).
#
# Este módulo é agnóstico de vertical: qualquer core com um dashboard estático
# (ex: Evidence.dev) pode reutilizá-lo.
#
# Histórico:
# - v1 tentava IAP em `google_compute_backend_bucket` (sem suporte no provider).
# - v2 (CMV-259) passou para um Cloud Run "proxy" atrás de LB +
#   `google_compute_backend_service` (que tem `iap {}` nativo) — mas isso exigia
#   um domínio próprio para o certificado gerenciado, e o domínio configurado
#   (`cm-analytics-dashboard.cm-ventures.com`) não pertence à empresa: o
#   certificado nunca saiu de PROVISIONING e o dashboard ficou inacessível.
# - v3 (CMV-346, 1ª revisão) serviu o proxy Cloud Run direto na URL `*.run.app`
#   com IAP NATIVO do Cloud Run (sem LB). Abandonada: bug confirmado da
#   plataforma GCP (audit log mostra `resourceName: projects//locations/...`
#   — projeto vazio no contexto de avaliação do IAP, negando 100% mesmo com
#   IAM policy correta; reproduzido em 13:03 e 13:05 UTC de 2026-08-01, mesmo
#   após toggle oficial `--no-iap`/`--iap` às 12:56 UTC). Ver seção "Por que
#   não IAP nativo" abaixo antes de reverter.
# - v4 (CMV-346, 2ª revisão, atual): autenticação via **oauth2-proxy** como
#   sidecar no mesmo Cloud Run service, na frente do proxy de leitura do
#   bucket. Elimina o LB, a forwarding rule, o IP global e o certificado
#   gerenciado por completo (~US$18/mês), e evita o bug do IAP nativo.
#
# ---------------------------------------------------------------------------
# Por que não IAP nativo (evidência do bug, para avaliar reversão futura)
# ---------------------------------------------------------------------------
# O IAP nativo em Cloud Run negava todos os usuários autorizados mesmo com a
# IAM policy correta (`roles/iap.httpsResourceAccessor` para os e-mails
# esperados, confirmado via `gcloud iap web get-iam-policy` e via REST direto,
# sem cache). Os Data Access audit logs de `iap.googleapis.com` mostraram cada
# avaliação de `iap.webServiceVersions.accessViaIAP` contra
# `resourceName: projects//locations/southamerica-east1/services/...`
# (projeto vazio) — nunca poderia haver match contra a policy real, que vive em
# `projects/857737530765/iap_web/cloud_run-southamerica-east1/...`. O toggle
# oficial (`gcloud run services update --no-iap` seguido de `--iap`) não
# corrigiu o contexto interno (mesmo etag da policy, mesma negação nas
# tentativas subsequentes de 13:03 e 13:05 UTC). Avaliação do board: bug da
# integração nativa IAP↔Cloud Run, provavelmente relacionado a projeto GCP sem
# organização/Workspace. Se o Google corrigir esse bug no futuro, a volta ao
# IAP nativo é barata: reverter este módulo para o commit anterior a esta
# revisão (remove o sidecar oauth2-proxy, os secrets de cookie/allowlist e o
# `allUsers` invoker; re-adiciona `iap_enabled`, o IAM do IAP e o invoker do
# service agent do IAP).
#
# ---------------------------------------------------------------------------
# Bucket único — publicação atômica por objeto-ponteiro
# ---------------------------------------------------------------------------
# O job de publicação (fora deste módulo, em cm-analytics/scripts/publish_atomic.sh)
# escreve cada build em "releases/<versão>/..." e, só depois de dlt+dbt (testes +
# freshness) passarem, sobrescreve o objeto-ponteiro (`var.pointer_object_name`,
# default "current-release") com o texto da versão vigente. Escrita de objeto
# único no GCS é atômica: nunca existe uma janela em que o ponteiro aponta para
# uma versão parcialmente escrita. Se qualquer etapa anterior falhar, o
# ponteiro não é tocado e o site continua servindo a versão anterior.
resource "google_storage_bucket" "site" {
  project                     = var.project_id
  name                        = "${var.name}-site"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = false

  # Sem acesso público: nenhum membro "allUsers"/"allAuthenticatedUsers" é
  # concedido em nenhum lugar deste módulo. O único caminho de leitura é via
  # o serviço proxy (protegido pelo oauth2-proxy).
  public_access_prevention = "enforced"

  versioning {
    enabled = true
  }
}

# ---------------------------------------------------------------------------
# Service account dedicada do proxy — só leitura do bucket, nada mais. É a SA
# de runtime do Cloud Run service abaixo (via ADC), nunca a SA do job de
# publicação (que tem write).
# ---------------------------------------------------------------------------
resource "google_service_account" "proxy" {
  project = var.project_id
  # account_id do GCP tem limite de 30 chars — var.name já pode ter até 41
  # (ver validation em variables.tf), então trunca antes de anexar o sufixo
  # em vez de simplesmente concatenar (que estourava o limite para nomes
  # como "cm-analytics-dashboard", 22 chars + "-site-proxy" = 33).
  account_id   = substr("${var.name}-proxy", 0, 30)
  display_name = "Proxy read-only do site estático ${var.name} (GCS -> HTTP)"
}

resource "google_storage_bucket_iam_member" "proxy_reader" {
  bucket = google_storage_bucket.site.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.proxy.email}"
}

# A SA de runtime do serviço (usada pelos dois containers, incluindo o
# oauth2-proxy) precisa ler os 4 secrets referenciados via value_source no
# container oauth2-proxy abaixo (client id/secret/cookie/allowlist).
resource "google_secret_manager_secret_iam_member" "proxy_secret_accessor" {
  for_each = toset([
    var.oauth_client_id_secret_id,
    var.oauth_client_secret_secret_id,
    var.cookie_secret_id,
    var.allowed_emails_secret_id,
  ])

  project   = var.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.proxy.email}"
}

# ---------------------------------------------------------------------------
# Cloud Run service: dois containers no mesmo serviço (sidecar).
#
# - `oauth2-proxy` é o *ingress container* (recebe o tráfego público, porta
#   exposta) — faz login Google, valida contra a allowlist de e-mails e só
#   então repassa a requisição para o upstream local.
# - `proxy` (leitor do bucket) não tem porta exposta no ingress: só recebe
#   tráfego do oauth2-proxy via `localhost`, nunca diretamente da internet.
#
# `min_instance_count = 0` preserva o princípio de nenhum worker permanente.
# Ingress "all" é necessário porque não há mais LB na frente — a autenticação
# passa a ser 100% na camada de aplicação (oauth2-proxy), não mais na borda do
# GCP. Por isso o invoker do serviço é `allUsers` (ver bloco de IAM abaixo):
# toda requisição chega ao oauth2-proxy, mas nenhuma chega ao conteúdo estático
# sem sessão Google válida + e-mail na allowlist.
# ---------------------------------------------------------------------------
resource "google_cloud_run_v2_service" "proxy" {
  project  = var.project_id
  name     = "${var.name}-site-proxy"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.proxy.email

    # Sidecars (multi-container) exigem o ambiente de execução gen2 — no gen1
    # (default), o container secundário falha ao iniciar com "no such file or
    # directory" mesmo quando o binário existe na imagem (confirmado em apply
    # real, CMV-346).
    execution_environment = "EXECUTION_ENVIRONMENT_GEN2"

    scaling {
      min_instance_count = 0
      max_instance_count = var.proxy_max_instances
    }

    # Container de ingress: oauth2-proxy. Recebe o tráfego público na porta
    # $PORT injetada pelo Cloud Run e faz proxy reverso para o upstream local
    # (container `proxy`, porta interna fixa `var.proxy_internal_port`).
    containers {
      name  = "oauth2-proxy"
      image = var.oauth2_proxy_image

      ports {
        container_port = var.oauth2_proxy_port
      }

      # `command` explícito: sem ele, o Cloud Run (multi-container/sidecar)
      # não resolve o ENTRYPOINT da imagem e tenta executar o primeiro item
      # de `args` como binário (falha: "error finding executable
      # '--provider=google' in PATH"). Confirmado em apply real (CMV-346).
      command = ["/bin/oauth2-proxy"]
      args = [
        "--provider=google",
        "--http-address=0.0.0.0:${var.oauth2_proxy_port}",
        "--upstream=http://localhost:${var.proxy_internal_port}",
        "--redirect-url=${var.oauth2_proxy_redirect_url}",
        "--email-domain=*",
        "--cookie-secure=true",
        "--cookie-expire=${var.oauth2_proxy_cookie_expire}",
      ]

      env {
        name = "OAUTH2_PROXY_CLIENT_ID"
        value_source {
          secret_key_ref {
            secret  = var.oauth_client_id_secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "OAUTH2_PROXY_CLIENT_SECRET"
        value_source {
          secret_key_ref {
            secret  = var.oauth_client_secret_secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "OAUTH2_PROXY_COOKIE_SECRET"
        value_source {
          secret_key_ref {
            secret  = var.cookie_secret_id
            version = "latest"
          }
        }
      }

      # Allowlist de e-mails montada via volume de secret — nunca hardcoded
      # no Terraform. O oauth2-proxy lê o arquivo referenciado por
      # --authenticated-emails-file.
      volume_mounts {
        name       = "allowed-emails"
        mount_path = "/etc/oauth2-proxy"
      }

      env {
        name  = "OAUTH2_PROXY_AUTHENTICATED_EMAILS_FILE"
        value = "/etc/oauth2-proxy/allowed-emails"
      }
    }

    volumes {
      name = "allowed-emails"
      secret {
        secret = var.allowed_emails_secret_id
        items {
          version = "latest"
          path    = "allowed-emails"
        }
      }
    }

    # Container upstream: lê o objeto-ponteiro do bucket e serve os arquivos
    # de "releases/<versão>/..." correspondentes. SEM porta pública — só o
    # oauth2-proxy acima fala com ele, via localhost.
    containers {
      name  = "proxy"
      image = var.proxy_image

      env {
        name  = "BUCKET_NAME"
        value = google_storage_bucket.site.name
      }

      env {
        name  = "POINTER_OBJECT_NAME"
        value = var.pointer_object_name
      }

      env {
        name  = "PORT"
        value = tostring(var.proxy_internal_port)
      }
    }
  }

  lifecycle {
    # As imagens são publicadas pelo pipeline de build/push da própria infra
    # (workflow reusável build-and-push), não pelo apply de Terraform de
    # rotina — evita que um apply sem nova imagem reverta o rollout.
    ignore_changes = [
      template[0].containers[0].image,
      template[0].containers[1].image,
    ]
  }
}

# ---------------------------------------------------------------------------
# Sem IAP: a autenticação é 100% do oauth2-proxy. Por isso o invoker do
# serviço precisa ser `allUsers` — é o oauth2-proxy quem decide quem passa,
# não o IAM do Cloud Run. Mudança de postura de segurança consciente,
# aprovada pelo CTO na CMV-346 (2ª revisão): a superfície exposta é o próprio
# oauth2-proxy (tela de login), sem caminho para o conteúdo estático sem
# sessão válida + e-mail na allowlist.
# ---------------------------------------------------------------------------
resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  project  = var.project_id
  location = google_cloud_run_v2_service.proxy.location
  name     = google_cloud_run_v2_service.proxy.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ---------------------------------------------------------------------------
# A SA de runtime do job de publicação (dlt->dbt->Evidence) escreve as builds
# versionadas e o objeto-ponteiro. Só write no bucket — ela nunca precisa
# tocar em recursos de rede/LB (que não existem mais nesta arquitetura).
# ---------------------------------------------------------------------------
resource "google_storage_bucket_iam_member" "publisher_writer" {
  bucket = google_storage_bucket.site.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.runtime_service_account_email}"
}
