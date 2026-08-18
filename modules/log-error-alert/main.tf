# Log-based metric + alerting policy genérico para o padrão de log estruturado
# JSON dos serviços Cloud Run (CMV-595, generaliza o que CMV-498 fez ad-hoc no
# cm-mcp). Não é conceito de vertical: conta linhas `jsonPayload.event=<var>,
# jsonPayload.status="error"` por serviço e opera o alerta em cima disso — o
# nome do evento e o campo de rótulo são parametrizados para servir qualquer
# core (request_id/org_id/operação/latência/status, sem payload sensível).

resource "google_logging_metric" "errors" {
  name    = "${var.service_name}/${var.log_event}_errors"
  project = var.project_id
  filter  = <<-EOT
    resource.type="cloud_run_revision"
    resource.labels.service_name="${var.service_name}"
    jsonPayload.event="${var.log_event}"
    jsonPayload.status="error"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
    labels {
      key        = var.label_field
      value_type = "STRING"
    }
  }

  label_extractors = {
    (var.label_field) = "EXTRACT(jsonPayload.${var.label_field})"
  }
}

# Canal de notificação é opcional: com `notification_channel_id` vazio, a
# policy fica visível no console do Cloud Monitoring mas não notifica ninguém
# — não bloqueia o apply enquanto o canal não estiver definido (mesmo
# comportamento adotado no CMV-498 do cm-mcp).
resource "google_monitoring_alert_policy" "error_rate" {
  project      = var.project_id
  display_name = "${var.service_name}: taxa de erro de ${var.log_event} acima do limiar"
  combiner     = "OR"

  notification_channels = var.notification_channel_id != "" ? [var.notification_channel_id] : []

  conditions {
    display_name = "${var.service_name}/${var.log_event}_errors acima de ${var.error_threshold} em ${var.alignment_period}"
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${var.service_name}\" AND metric.type=\"logging.googleapis.com/user/${google_logging_metric.errors.name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.error_threshold
      duration        = "0s"
      aggregations {
        alignment_period   = var.alignment_period
        per_series_aligner = "ALIGN_COUNT"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }
}
