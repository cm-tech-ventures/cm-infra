output "job_name" {
  value = module.keepalive_job.job_name
}

output "schedule_name" {
  value = module.keepalive_schedule.job_name
}

output "alert_policy_id" {
  value = module.keepalive_alert.alert_policy_id
}
