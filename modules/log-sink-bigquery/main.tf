# Sink do Cloud Logging que leva os eventos estruturados (envelope do
# cm_sdk.observabilidade) de UM projeto para o dataset bronze_logs do
# cm-ventures-core. Um sink por projeto: sink só enxerga os logs do projeto
# onde vive.
#
# O dataset NÃO é criado aqui: ele é do Terraform do cm-analytics
# (terraform/bigquery.tf). Este módulo só lê o dataset e concede a escrita.

data "google_bigquery_dataset" "destino" {
  project    = var.dataset_project_id
  dataset_id = var.dataset_id
}

locals {
  filtro_padrao = <<-EOT
    resource.type=("cloud_run_revision" OR "cloud_run_job")
    jsonPayload.event:*
    jsonPayload.env="prod"
  EOT
}

resource "google_logging_project_sink" "eventos" {
  project     = var.project_id
  name        = var.nome
  description = var.descricao
  destination = "bigquery.googleapis.com/projects/${data.google_bigquery_dataset.destino.project}/datasets/${data.google_bigquery_dataset.destino.dataset_id}"
  filter      = coalesce(var.filtro, local.filtro_padrao)

  # Uma tabela só, particionada por dia (sem isto, nasce uma tabela por dia
  # com sufixo _AAAAMMDD e o dbt precisa de wildcard).
  bigquery_options {
    use_partitioned_tables = true
  }

  unique_writer_identity = true
}

# Sem esta concessão o sink falha em silêncio. É aditiva (_iam_member): só
# acrescenta a writer identity, não revoga o que já está no dataset. E fica só
# no dataset, nunca no projeto.
resource "google_bigquery_dataset_iam_member" "escrita_do_sink" {
  project    = data.google_bigquery_dataset.destino.project
  dataset_id = data.google_bigquery_dataset.destino.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = google_logging_project_sink.eventos.writer_identity
}
