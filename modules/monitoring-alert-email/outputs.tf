output "notification_channel_id" {
  description = "ID do canal de notificação por e-mail."
  value       = google_monitoring_notification_channel.email.id
}

output "alert_policy_id" {
  description = "ID da política de alerta."
  value       = google_monitoring_alert_policy.job_failed.id
}
