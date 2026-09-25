output "policy_id" {
  description = "ID da política de alerta criada."
  value       = google_monitoring_alert_policy.alerta.id
}

output "metric_name" {
  description = "Nome da métrica derivada de log, quando o sensor é 'scheduler'. Vazio para o sensor 'job', que usa métrica nativa."
  value       = local.is_scheduler ? local.metric_name : ""
}
