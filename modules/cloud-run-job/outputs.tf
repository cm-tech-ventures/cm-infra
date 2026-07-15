output "job_name" {
  description = "Nome do Cloud Run Job."
  value       = google_cloud_run_v2_job.job.name
}

output "job_id" {
  description = "ID completo do job."
  value       = google_cloud_run_v2_job.job.id
}

output "service_account_email" {
  description = "Email da SA de runtime do job."
  value       = google_service_account.job.email
}

output "run_execution_uri" {
  description = "URI da Run Admin API para disparar uma execução do job (usar como target_uri do scheduler-job com oauth)."
  value       = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${google_cloud_run_v2_job.job.name}:run"
}
