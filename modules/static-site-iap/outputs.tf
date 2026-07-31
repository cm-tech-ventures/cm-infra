output "bucket_names" {
  description = "Nomes dos dois buckets GCS (blue e green) que guardam os arquivos do site estático."
  value = {
    blue  = google_storage_bucket.site["blue"].name
    green = google_storage_bucket.site["green"].name
  }
}

output "backend_bucket_names" {
  description = "Nomes dos dois google_compute_backend_bucket (blue e green). Um deles é o alvo do set-default-service no publish_atomic.sh."
  value = {
    blue  = google_compute_backend_bucket.site["blue"].name
    green = google_compute_backend_bucket.site["green"].name
  }
}

output "url_map_name" {
  description = "Nome do google_compute_url_map. É o recurso que o job de publicação flipa (gcloud compute url-maps set-default-service) após uma build validada."
  value       = google_compute_url_map.site.name
}

output "load_balancer_ip" {
  description = "Endereço IP externo global do Load Balancer (aponte o DNS do dashboard para este IP)."
  value       = google_compute_global_address.site.address
}
