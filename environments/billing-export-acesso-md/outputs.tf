output "leitores_billing_export" {
  description = "Quem tem dataViewer no billing_export por este state."
  value       = { for k, m in google_bigquery_dataset_iam_member.leitura : k => m.member }
}
