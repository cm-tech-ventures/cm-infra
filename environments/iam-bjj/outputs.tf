output "contas_deploy" {
  description = "E-mail de cada conta de deploy, por nome curto."
  value       = { for k, sa in google_service_account.deploy : k => sa.email }
}

output "wif_provider" {
  description = "Nome completo do provider do WIF (o GCP_WORKLOAD_ID_PROVIDER dos repos)."
  value       = google_iam_workload_identity_pool_provider.github.name
}
