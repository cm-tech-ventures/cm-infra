output "service_url" {
  description = "URL do serviço Cloud Run."
  value       = google_cloud_run_v2_service.service.uri
}

output "service_account_email" {
  description = "Email da service account dedicada do serviço."
  value       = google_service_account.service.email
}

output "service_name" {
  description = "Nome do serviço Cloud Run."
  value       = google_cloud_run_v2_service.service.name
}
