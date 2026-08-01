output "bucket_name" {
  description = "Nome do bucket GCS único que guarda as builds versionadas (releases/<versão>/...) e o objeto-ponteiro."
  value       = google_storage_bucket.site.name
}

output "pointer_object_name" {
  description = "Nome do objeto-ponteiro no bucket. O job de publicação (publish_atomic.sh) escreve neste objeto, por último, o prefixo da versão vigente."
  value       = var.pointer_object_name
}

output "proxy_service_name" {
  description = "Nome do Cloud Run service (sidecar oauth2-proxy + proxy leitor do bucket), único ponto de acesso ao dashboard."
  value       = google_cloud_run_v2_service.proxy.name
}

output "proxy_service_account_email" {
  description = "E-mail da service account de runtime do proxy (roles/storage.objectViewer no bucket, nada além disso)."
  value       = google_service_account.proxy.email
}

output "dashboard_url" {
  description = "URL pública (*.run.app) do dashboard, atrás do oauth2-proxy (login Google + allowlist de e-mails). Sem domínio próprio — HTTPS automático do próprio Cloud Run."
  value       = google_cloud_run_v2_service.proxy.uri
}
