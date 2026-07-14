output "repository_url" {
  description = "URL base do repositório (para tag de imagens): REGION-docker.pkg.dev/PROJECT/REPO."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker.repository_id}"
}

output "repository_id" {
  description = "ID do repositório."
  value       = google_artifact_registry_repository.docker.repository_id
}
