# Módulo genérico de publicação de site estático atrás de um Load Balancer HTTPS
# com IAP, usando publicação atômica a NÍVEL DE OBJETO NO BUCKET (não mais
# blue/green a nível de Load Balancer — ver ADR-003, adendo de 2026-08-01).
#
# Este módulo é agnóstico de vertical: qualquer core com um dashboard estático
# (ex: Evidence.dev) pode reutilizá-lo.
#
# Histórico: a primeira versão deste módulo tentava IAP nativo em
# `google_compute_backend_bucket`, que não existe no provider Terraform (só
# existe o campo REST, não coberto). A segunda tentativa (blue/green de
# backend buckets) contornava isso só para o IAP via null_resource/local-exec.
# O CTO decidiu (adendo ADR-003) trocar a arquitetura: em vez de servir o
# bucket diretamente via backend bucket, um serviço Cloud Run "proxy" mínimo,
# sem estado e com `min_instance_count = 0`, lê o bucket e serve o conteúdo.
# Esse proxy senta atrás de um Serverless NEG + `google_compute_backend_service`,
# que SUPORTA o bloco `iap {}` nativo — elimina o `null_resource`/local-exec.
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
  # o serviço proxy (que só é alcançável através do LB + IAP).
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
  project      = var.project_id
  account_id   = "${var.name}-site-proxy"
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
# permanente. Ingress restrito a "internal-and-cloud-load-balancing": a URL
# "*.run.app" não serve o dashboard — só é alcançável via o LB (e, portanto,
# via IAP). Nenhum binding de invoker é concedido a "allUsers": a única forma
# de invocar é o próprio LB, permitido implicitamente pelo Serverless NEG.
# ---------------------------------------------------------------------------
resource "google_cloud_run_v2_service" "proxy" {
  project  = var.project_id
  name     = "${var.name}-site-proxy"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

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

# ---------------------------------------------------------------------------
# Serverless NEG — aponta o backend do LB para o Cloud Run service proxy.
# ---------------------------------------------------------------------------
resource "google_compute_region_network_endpoint_group" "proxy" {
  project               = var.project_id
  name                  = "${var.name}-site-proxy-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"

  cloud_run {
    service = google_cloud_run_v2_service.proxy.name
  }
}

# ---------------------------------------------------------------------------
# Backend service — ao contrário de google_compute_backend_bucket, este
# recurso SUPORTA o bloco `iap {}` nativo do provider Terraform. Elimina o
# null_resource/local-exec da versão anterior deste módulo.
# ---------------------------------------------------------------------------
resource "google_compute_backend_service" "site" {
  project               = var.project_id
  name                  = "${var.name}-site-backend"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  protocol              = "HTTPS"

  backend {
    group = google_compute_region_network_endpoint_group.proxy.id
  }

  iap {
    enabled              = true
    oauth2_client_id     = var.iap_oauth_client_id
    oauth2_client_secret = var.iap_oauth_client_secret
  }
}

# IAM do IAP: concede a cada membro autorizado o papel para passar pelo IAP e
# chegar ao backend service. A lista deve conter só quem tem direito de ver o
# dashboard (ex: board + dono do MD) — nunca conceder no nível do projeto inteiro.
resource "google_iap_web_backend_service_iam_member" "authorized_members" {
  for_each = toset(var.iap_authorized_members)

  project             = var.project_id
  web_backend_service = google_compute_backend_service.site.name
  role                = "roles/iap.httpsResourceAccessor"
  member              = each.value
}

# ---------------------------------------------------------------------------
# url_map — aponta direto para o backend service único. Sem blue/green a
# nível de LB: a publicação atômica agora vive inteiramente no objeto-ponteiro
# do bucket (ver comentário no topo do arquivo), então não há mais necessidade
# de o job flipar nada no Compute API — o Terraform gerencia o url_map por
# inteiro, normalmente.
# ---------------------------------------------------------------------------
resource "google_compute_url_map" "site" {
  project         = var.project_id
  name            = "${var.name}-url-map"
  default_service = google_compute_backend_service.site.id
}

# ---------------------------------------------------------------------------
# Load Balancer HTTPS externo padrão: IP global + cert gerenciado + proxy + regra.
# ---------------------------------------------------------------------------
resource "google_compute_global_address" "site" {
  project      = var.project_id
  name         = "${var.name}-lb-ip"
  address_type = "EXTERNAL"
}

resource "google_compute_managed_ssl_certificate" "site" {
  project = var.project_id
  name    = "${var.name}-ssl-cert"

  managed {
    domains = ["${var.name}.cm-ventures.com"]
  }
}

resource "google_compute_target_https_proxy" "site" {
  project          = var.project_id
  name             = "${var.name}-https-proxy"
  url_map          = google_compute_url_map.site.id
  ssl_certificates = [google_compute_managed_ssl_certificate.site.id]
}

resource "google_compute_global_forwarding_rule" "site" {
  project               = var.project_id
  name                  = "${var.name}-fwd-rule"
  target                = google_compute_target_https_proxy.site.id
  port_range            = "443"
  ip_address            = google_compute_global_address.site.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# ---------------------------------------------------------------------------
# A SA de runtime do job de publicação (dlt->dbt->Evidence) escreve as builds
# versionadas e o objeto-ponteiro. Só write no bucket — ela nunca precisa
# tocar em recursos de rede/LB (ao contrário da versão blue/green anterior,
# que exigia um custom role para flipar o url_map).
# ---------------------------------------------------------------------------
resource "google_storage_bucket_iam_member" "publisher_writer" {
  bucket = google_storage_bucket.site.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.runtime_service_account_email}"
}
