output "politicas" {
  description = "IDs das políticas criadas, por alerta do catálogo."
  value       = { for k, m in module.alerta : k => m.policy_id }
}
