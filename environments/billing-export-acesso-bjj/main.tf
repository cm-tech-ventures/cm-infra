# Leitura no dataset billing_export do bjj-system (cm-infra#98, épico cm-analytics#144).
#
# O billing_export do bjj-system é o destino do export de faturamento da conta
# do sys-bjj (histórico do sys-bjj até 06/10/2026, antes da troca de conta). Foi criado à mão no console e NÃO se recria: trocar o
# destino do export exige desligá-lo, e o Google avisa que os dados do período
# desligado não se recuperam. Por isso ele fica fora de qualquer Terraform, e
# o cm-analytics só o expõe como view no bronze (custos__gcp_detalhado_bjj).
#
# Este state só acrescenta leitura (dataViewer, aditivo via _iam_member):
#   - analytics-bq-pipeline: lê a tabela pela view do bronze;
#   - github-deployer-prod: o apply do cm-analytics cria a view, e o
#     BigQuery confere a tabela de origem na criação.
# Nada de dataOwner: dataOwner permite apagar o dataset (decisão do Carlos,
# 06/10/2026).
#
# Cópia do environments/billing-export-acesso, mas com state no bucket da
# própria conta dona (terraform-backend-sys-bjj) e aplicado pelo Carlos com a conta
# bjjsystem25 sozinha. Ver README.md.

data "google_bigquery_dataset" "billing_export" {
  project    = "bjj-system"
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
