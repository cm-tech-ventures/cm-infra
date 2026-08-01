# Módulo genérico de publicação de site estático via Cloud Run + IAP DIRETO
# (sem Load Balancer/domínio próprio — decisão do board de 2026-08-01, CMV-346).
#
# Este módulo é agnóstico de vertical: qualquer core com um dashboard estático
# (ex: Evidence.dev) pode reutilizá-lo.
#
# Histórico: a v1 tentava IAP em `google_compute_backend_bucket` (sem suporte
# no provider). A v2 (CMV-259) passou para um Cloud Run "proxy" atrás de LB +
# `google_compute_backend_service` (que tem `iap {}` nativo) — mas isso exigia
# um domínio próprio para o certificado gerenciado, e o domínio configurado
# (`cm-analytics-dashboard.cm-ventures.com`) não pertence à empresa: o
# certificado nunca saiu de PROVISIONING e o dashboard ficou inacessível
# (bug CMV-346). O board decidiu não usar domínio próprio por ora: esta v3
# serve o proxy Cloud Run diretamente na URL `*.run.app` (HTTPS automático do
# próprio Cloud Run) com IAP habilitado nativamente no serviço — GCP suporta
# IAP em Cloud Run sem LB. Elimina o LB, a forwarding rule, o IP global e o
# certificado gerenciado por completo (~US$18/mês).
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
  # o serviço proxy (protegido por IAP).
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

# ---------------------------------------------------------------------------
# Cloud Run service proxy: stateless, somente leitura do bucket, sem lógica de
# negócio. `min_instance_count = 0` preserva o princípio de nenhum worker
# permanente. Ingress "all" é necessário para o IAP nativo do Cloud Run
# interceptar as requisições antes do container (não há mais LB na frente);
# o IAP é quem garante que só usuários autenticados/autorizados chegam ao
# proxy — a URL pública `*.run.app` nunca fica de fato aberta.
# ---------------------------------------------------------------------------
resource "google_cloud_run_v2_service" "proxy" {
  project  = var.project_id
  name     = "${var.name}-site-proxy"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  # IAP nativo do Cloud Run (sem LB), disponível no provider google >= 6.14
  # como campo `iap_enabled` do serviço (ver
  # https://cloud.google.com/iap/docs/enabling-cloud-run). PENDENTE DE
  # VALIDAÇÃO contra a versão do provider fixada em versions.tf antes do
  # primeiro apply desta revisão — se a versão travada não expuser o campo,
  # atualizar o `required_providers` (não há workaround de outro recurso
  # Terraform conhecido; documentar no README caso um `terraform plan` real
  # rejeite o atributo).
  iap_enabled = true

  template {
    service_account = google_service_account.proxy.email

    scaling {
      min_instance_count = 0
      max_instance_count = var.proxy_max_instances
    }

    containers {
      image = var.proxy_image

      env {
        name  = "BUCKET_NAME"
        value = google_storage_bucket.site.name
      }

      env {
        name  = "POINTER_OBJECT_NAME"
        value = var.pointer_object_name
      }
    }
  }

  lifecycle {
    # A imagem do proxy é publicada pelo pipeline de build/push da própria
    # infra (workflow reusável build-and-push), não pelo apply de Terraform
    # de rotina — evita que um apply sem nova imagem reverta o rollout.
    ignore_changes = [template[0].containers[0].image]
  }
}

# IAM do IAP nativo do Cloud Run: concede a cada membro autorizado o papel
# para passar pelo IAP e chegar ao serviço. A lista deve conter só quem tem
# direito de ver o dashboard (ex: board + dono do MD) — nunca "allUsers".
resource "google_iap_web_cloud_run_service_iam_member" "authorized_members" {
  for_each = toset(var.iap_authorized_members)

  project           = var.project_id
  location          = google_cloud_run_v2_service.proxy.location
  cloud_run_service = google_cloud_run_v2_service.proxy.name
  role              = "roles/iap.httpsResourceAccessor"
  member            = each.value
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
