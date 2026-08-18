output "log_metric_name" {
  description = "Nome da log-based metric criada."
  value       = google_logging_metric.errors.name
}

output "alert_policy_id" {
  description = "ID da política de alerta."
  value       = google_monitoring_alert_policy.error_rate.id
}
