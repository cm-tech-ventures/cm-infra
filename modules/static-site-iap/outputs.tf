output "bucket_name" {
  description = "Nome do bucket GCS único que guarda as builds versionadas (releases/<versão>/...) e o objeto-ponteiro."
  value       = google_storage_bucket.site.name
}

output "pointer_object_name" {
  description = "Nome do objeto-ponteiro no bucket. O job de publicação (publish_atomic.sh) escreve neste objeto, por último, o prefixo da versão vigente."
  value       = var.pointer_object_name
}

output "backend_service_name" {
  description = "Nome do google_compute_backend_service (com IAP nativo habilitado) que expõe o proxy Cloud Run."
  value       = google_compute_backend_service.site.name
}

output "proxy_service_name" {
  description = "Nome do Cloud Run service proxy (somente leitura do bucket, ingress restrito ao LB)."
  value       = google_cloud_run_v2_service.proxy.name
}

output "proxy_service_account_email" {
  description = "E-mail da service account de runtime do proxy (roles/storage.objectViewer no bucket, nada além disso)."
  value       = google_service_account.proxy.email
}

output "url_map_name" {
  description = "Nome do google_compute_url_map. Gerenciado inteiramente pelo Terraform — não há mais flip fora de banda (a publicação atômica agora vive no objeto-ponteiro do bucket)."
  value       = google_compute_url_map.site.name
}

output "load_balancer_ip" {
  description = "Endereço IP externo global do Load Balancer (aponte o DNS do dashboard para este IP)."
  value       = google_compute_global_address.site.address
}
