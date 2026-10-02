output "job_name" {
  value = module.keepalive_hom_job.job_name
}

output "schedule_name" {
  value = module.keepalive_hom_schedule.job_name
}

output "alert_policy_id" {
  value = module.keepalive_hom_alert.alert_policy_id
}
