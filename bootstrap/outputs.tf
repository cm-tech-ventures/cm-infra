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

output "mcp_logs_dataset" {
  description = "Dataset BigQuery de destino dos logs de tool call do cm-mcp/md-mcp (CMV-594)."
  value       = google_bigquery_dataset.mcp_logs.dataset_id
}

output "mcp_logs_sink_writer_identity" {
  description = "Writer identity do sink do Cloud Logging — referência para debug de permissão (CMV-594)."
  value       = google_logging_project_sink.mcp_tool_calls.writer_identity
}
