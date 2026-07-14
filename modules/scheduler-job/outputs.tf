output "job_name" {
  description = "Nome do job no Cloud Scheduler."
  value       = google_cloud_scheduler_job.job.name
}

output "job_id" {
  description = "ID completo do job."
  value       = google_cloud_scheduler_job.job.id
}
