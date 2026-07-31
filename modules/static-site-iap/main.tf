# Módulo genérico de publicação de site estático atrás de um Load Balancer HTTPS
# com IAP, usando o padrão blue/green a NÍVEL DE LOAD BALANCER para permitir
# publicação atômica (a troca de versão é uma única chamada de API que aponta o
# url_map para outro backend — nunca uma sobrescrita de arquivos "no ar").
#
# Este módulo é agnóstico de vertical: qualquer core com um dashboard estático
# (ex: Evidence.dev) pode reutilizá-lo.

locals {
  colors = ["blue", "green"]
}

# ---------------------------------------------------------------------------
# Buckets GCS — um por cor. Privados: todo acesso passa pelo LB + IAP.
# ---------------------------------------------------------------------------
resource "google_storage_bucket" "site" {
  for_each = toset(local.colors)

  project                     = var.project_id
  name                        = "${var.name}-${each.key}"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = false

  # Sem acesso público: nenhum membro "allUsers"/"allAuthenticatedUsers" é concedido
  # em nenhum lugar deste módulo. O único caminho de leitura é via backend bucket + IAP.
  public_access_prevention = "enforced"

  website {
    main_page_suffix = "index.html"
    not_found_page   = "index.html"
  }

  versioning {
    enabled = true
  }
}

# ---------------------------------------------------------------------------
# Backend buckets — um por cor, cada um protegido por IAP.
# ---------------------------------------------------------------------------
resource "google_compute_backend_bucket" "site" {
  for_each = toset(local.colors)

  project     = var.project_id
  name        = "${var.name}-${each.key}-backend"
  bucket_name = google_storage_bucket.site[each.key].name
  enable_cdn  = false
}

# LIMITAÇÃO CONHECIDA DO PROVIDER: verificado nesta implementação (provider
# hashicorp/google e hashicorp/google-beta, ambos v6.50.0, via
# `terraform providers schema -json`) que o recurso `google_compute_backend_bucket`
# NÃO expõe o bloco `iap {}` (esse bloco só existe em `google_compute_backend_service`,
# usado para backends de instância/NEG — não para backend de bucket GCS). A API REST
# do Compute Engine aceita IAP em backend buckets (`compute.backendBuckets.iap`), mas
# o provider Terraform não cobre esse campo até a versão testada aqui.
#
# Solução adotada: configurar o IAP do backend bucket via `gcloud` num
# `null_resource` com `local-exec`, disparado sempre que as credenciais OAuth
# mudarem. Isso sai do "caminho 100% declarativo" do Terraform para esse campo
# específico — reavalie/substitua por um bloco nativo assim que o provider
# passar a suportar `iap` em `google_compute_backend_bucket`
# (acompanhar https://github.com/hashicorp/terraform-provider-google/issues).
resource "null_resource" "backend_bucket_iap" {
  for_each = toset(local.colors)

  triggers = {
    backend_bucket   = google_compute_backend_bucket.site[each.key].name
    oauth2_client_id = var.iap_oauth_client_id
    # sha1 do secret em vez do valor puro, para não deixar o segredo em texto
    # claro nos triggers (que ficam no state).
    oauth2_secret_sha = sha1(var.iap_oauth_client_secret)
  }

  provisioner "local-exec" {
    command = <<-EOT
      gcloud compute backend-buckets update ${google_compute_backend_bucket.site[each.key].name} \
        --project=${var.project_id} \
        --iap=enabled,oauth2-client-id=${var.iap_oauth_client_id},oauth2-client-secret=${var.iap_oauth_client_secret}
    EOT
  }

  depends_on = [google_compute_backend_bucket.site]
}

# IAM do IAP: concede a cada membro autorizado o papel para passar pelo IAP e
# chegar ao backend bucket. A lista deve conter só quem tem direito de ver o
# dashboard (ex: board + dono do MD) — nunca conceder no nível do projeto inteiro.
#
# Nome do resource verificado nesta implementação via `terraform providers
# schema -json` contra o provider hashicorp/google v6.50.0 (sem necessidade de
# google-beta): o resource google_iap_web_backend_service_iam_member existe no
# provider google padrão e aceita o argumento web_backend_service = nome do
# backend bucket/service. Ainda assim, re-confirme contra a versão do provider
# realmente pinada no lockfile do ambiente antes do primeiro apply em produção.
resource "google_iap_web_backend_service_iam_member" "authorized_members" {
  for_each = {
    for pair in setproduct(local.colors, var.iap_authorized_members) :
    "${pair[0]}|${pair[1]}" => { color = pair[0], member = pair[1] }
  }

  project             = var.project_id
  web_backend_service = google_compute_backend_bucket.site[each.value.color].name
  role                = "roles/iap.httpsResourceAccessor"
  member              = each.value.member
}

# ---------------------------------------------------------------------------
# url_map — o coração do mecanismo de publicação atômica.
#
# O default_service aponta para o backend da cor ATIVA. A troca de cor (deploy
# de uma nova build bem-sucedida) NÃO é feita via `terraform apply`: é feita pelo
# job de publicação (script publish_atomic.sh em cm-analytics), que chama a
# Compute API (gcloud compute url-maps set-default-service / urlMaps.patch) DEPOIS
# de já ter escrito os arquivos novos no bucket standby. Isso garante que o site
# só "vai ao ar" com a build completa e validada (dlt + dbt build/testes/freshness
# passaram) — se qualquer etapa falhar antes disso, o url_map continua apontando
# pro backend antigo, sem downtime e sem rollback manual.
#
# O `lifecycle.ignore_changes` abaixo é o que impede o Terraform de "brigar" com o
# job toda vez que ele flipa o default_service fora de banda.
resource "google_compute_url_map" "site" {
  project         = var.project_id
  name            = "${var.name}-url-map"
  default_service = google_compute_backend_bucket.site[var.active_color].id

  lifecycle {
    ignore_changes = [default_service]
  }
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
# IAM granular para a SA de runtime flipar o url_map, sem conceder o papel amplo
# roles/compute.loadBalancerAdmin (que permite administrar qualquer recurso de LB
# no projeto). Criamos um role custom só com as duas permissions necessárias.
# ---------------------------------------------------------------------------
resource "google_project_iam_custom_role" "url_map_flipper" {
  project     = var.project_id
  role_id     = replace("${var.name}_url_map_flipper", "-", "_")
  title       = "Flip url_map de ${var.name} (blue/green)"
  description = "Permissão mínima para ler e atualizar o url_map do site estático ${var.name}, usada pelo job de publicação atômica."
  permissions = [
    "compute.urlMaps.get",
    "compute.urlMaps.update",
  ]
}

resource "google_project_iam_member" "url_map_flipper" {
  project = var.project_id
  role    = google_project_iam_custom_role.url_map_flipper.id
  member  = "serviceAccount:${var.runtime_service_account_email}"
}

# A SA de runtime também precisa escrever os arquivos do site nos dois buckets
# (ela não sabe de antemão qual é o standby até consultar o url_map em runtime).
resource "google_storage_bucket_iam_member" "runtime_writer" {
  for_each = toset(local.colors)

  bucket = google_storage_bucket.site[each.key].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.runtime_service_account_email}"
}
