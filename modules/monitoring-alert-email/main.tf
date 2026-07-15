# Alerta por e-mail quando um Cloud Run Job falha. Genérico: usado por qualquer
# job (hoje o keepalive de bancos Supabase, CMV-53) — nunca conceito de vertical.

resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = var.alert_display_name
  type         = "email"

  labels = {
    email_address = var.notification_email
  }
}

resource "google_monitoring_alert_policy" "job_failed" {
  project      = var.project_id
  display_name = "${var.alert_display_name} — execução falhou"
  combiner     = "OR"
  severity     = "ERROR"

  conditions {
    display_name = "Cloud Run Job ${var.job_name} teve execução com falha"

    condition_threshold {
      filter = join(" AND ", [
        "resource.type = \"cloud_run_job\"",
        "resource.label.job_name = \"${var.job_name}\"",
        "resource.label.location = \"${var.location}\"",
        "metric.type = \"run.googleapis.com/job/completed_execution_count\"",
        "metric.label.result = \"failed\"",
      ])
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      aggregations {
        alignment_period     = var.alignment_period
        per_series_aligner   = "ALIGN_COUNT"
        cross_series_reducer = "REDUCE_SUM"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  alert_strategy {
    auto_close = "86400s"
  }

  documentation {
    content   = "O Cloud Run Job \"${var.job_name}\" teve pelo menos uma execução com falha na última janela. Verifique os logs do job — causa comum: banco Supabase pausado/deletado ou credencial (DSN) inválida. Ver cm-infra/docs/keepalive.md (CMV-53)."
    mime_type = "text/markdown"
  }
}
