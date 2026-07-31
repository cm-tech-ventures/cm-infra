output "workload_identity_provider" {
  description = "Resource name do WIF provider — usar em workload-identity-provider dos workflows."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "deploy_service_account" {
  description = "Email da SA de deploy — usar em deploy-service-account dos workflows."
  value       = google_service_account.deployer.email
}

output "state_bucket" {
  description = "Bucket GCS de state do Terraform."
  value       = google_storage_bucket.tf_state.name
}

output "artifact_repository_url" {
  description = "URL base do Artifact Registry dos cores."
  value       = module.artifact_registry.repository_url
}

output "ops_observer_service_account" {
  description = "Email da SA read-only de observabilidade — usar em --impersonate-service-account na rotina Ops semanal (CMV-319)."
  value       = google_service_account.ops_observer.email
}
