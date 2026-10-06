# Leitura no dataset billing_export do cm-ventures-core (cm-infra#63).
#
# O billing_export é o destino do export de faturamento do GCP da conta do
# core. Foi criado à mão no console em 24/09/2026 e NÃO se recria: trocar o
# destino do export exige desligá-lo, e o Google avisa que os dados do período
# desligado não se recuperam. Por isso ele fica fora de qualquer Terraform, e
# o cm-analytics só o expõe como views no bronze_custos (cm-analytics#82).
#
# Este state só acrescenta leitura (dataViewer, aditivo via _iam_member):
#   - analytics-bq-pipeline: lê as tabelas pelas views do bronze_custos;
#   - github-deployer-prod: o apply do cm-analytics cria as views, e o
#     BigQuery confere a tabela de origem na criação.
# Nada de dataOwner: dataOwner permite apagar o dataset (decisão do Carlos,
# 06/10/2026).
#
# Estado próprio, fora do bootstrap (que tem drift e não se aplica), aplicado
# pela conta cm.tech.ventures, dona do dataset, com plan literal no PR.

data "google_bigquery_dataset" "billing_export" {
  project    = "cm-ventures-core"
  dataset_id = "billing_export"
}

locals {
  leitores_billing_export = {
    pipeline = "serviceAccount:analytics-bq-pipeline@cm-ventures-core.iam.gserviceaccount.com"
    deploy   = "serviceAccount:github-deployer-prod@cm-ventures-core.iam.gserviceaccount.com"
  }
}

resource "google_bigquery_dataset_iam_member" "leitura" {
  for_each = local.leitores_billing_export

  project    = data.google_bigquery_dataset.billing_export.project
  dataset_id = data.google_bigquery_dataset.billing_export.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = each.value
}
