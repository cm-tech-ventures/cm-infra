# --- SA do CI do dbt do cm-analytics (modelagem única M2a, cm-analytics#133) ---
# A conta analytics-ci-dbt é criada pelo Terraform do cm-analytics (aplicar o PR de
# lá ANTES deste: sem a conta, o binding falha). O CI carrega seeds sintéticas em
# datasets ci_<PR>_<camada>, roda dbt build e apaga os datasets no fim; entra pela
# Workload Identity Federation, sem chave.
#
# roles/bigquery.user no projeto: cria dataset e roda job, mas não lê dado de dataset
# nenhum (o mesmo papel do deployer, ver deployer_roles). Quem cria um dataset vira
# OWNER dele, então a conta só manda nos ci_* que ela mesma criar e não enxerga
# bronze, silver, gold, diamond nem billing_export. Condição por nome (ci_*) não
# serve: o IAM nunca satisfaz resource.name em CREATE.
#
# Arquivo próprio, fora das listas de main.tf, para não conflitar com a frente
# Permissões (cm-infra#91).
resource "google_project_iam_member" "analytics_ci_dbt_bigquery_user" {
  project = var.project_id
  role    = "roles/bigquery.user"
  member  = "serviceAccount:analytics-ci-dbt@${var.project_id}.iam.gserviceaccount.com"
}
