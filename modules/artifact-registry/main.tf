# Repositório Docker único por projeto/região para os cores.

resource "google_artifact_registry_repository" "docker" {
  project       = var.project_id
  location      = var.region
  repository_id = var.repository_id
  description   = var.description
  format        = "DOCKER"

  # Retenção. Sem isso o repositório só cresce: em 29/09/2026 os registries da
  # casa somavam 182,8 GB e custavam R$ 103/mês — 56% de toda a conta do GCP.
  #
  # Uma política KEEP por pacote, não uma para o repositório inteiro. O cm-cores
  # é compartilhado (billing, identity, crm, cm-mcp, analytics-pipeline...) e
  # nem todo serviço faz deploy no mesmo ritmo: o keepalive-check tem UMA imagem,
  # de 15/07. "As 10 mais recentes do repositório" apagaria ela. Com prefixo por
  # pacote, cada serviço tem as suas N protegidas, independente do vizinho.
  #
  # KEEP vence DELETE no Artifact Registry, então a regra de idade abaixo nunca
  # alcança o que as políticas de cima protegem.
  cleanup_policy_dry_run = var.retencao_dry_run

  dynamic "cleanup_policies" {
    for_each = toset(var.pacotes_protegidos)
    content {
      id     = "manter-${cleanup_policies.value}"
      action = "KEEP"
      most_recent_versions {
        package_name_prefixes = [cleanup_policies.value]
        keep_count            = var.manter_versoes
      }
    }
  }

  dynamic "cleanup_policies" {
    for_each = length(var.pacotes_protegidos) > 0 ? [1] : []
    content {
      id     = "apagar-antigas"
      action = "DELETE"
      condition {
        older_than = "${var.apagar_apos_dias * 24 * 60 * 60}s"
      }
    }
  }
}

resource "google_artifact_registry_repository_iam_member" "readers" {
  for_each   = toset(var.readers)
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.docker.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${each.value}"
}

resource "google_artifact_registry_repository_iam_member" "writers" {
  for_each   = toset(var.writers)
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.docker.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${each.value}"
}
