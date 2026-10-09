# Alerta da conferência diária do salão (cm-analytics, passo final do
# analytics-diario). Não usa o módulo alerta-generico: aquele vigia rotina
# (relógio/execução); este vigia o RESULTADO — o evento `conferencia.diferenca`
# que a conferência escreve quando o salão e os eventos não batem.
#
# Contrato do evento (cm-analytics#118): jsonPayload.event = "conferencia.diferenca",
# severidade ERROR para dados.categoria = "dinheiro" e WARNING para "dado".
# `dados` é TEXTO JSON no envelope, então o rótulo sai por REGEXP_EXTRACT.
# O JSON sai de json.dumps (": " com espaço), como o `"tool": "..."` do md-mcp;
# o `\s*` tolera as duas grafias.
#
# Rótulo `categoria`: dois valores. Nunca id de cliente (docs/alertas.md §6).

locals {
  conferencia_metric = "alertas/conferencia_diferenca"
  conferencia_filtro = "jsonPayload.event=\"conferencia.diferenca\" AND resource.type=\"cloud_run_job\" AND jsonPayload.env=\"prod\""
}

resource "google_logging_metric" "conferencia_diferenca" {
  name    = local.conferencia_metric
  project = var.project_id
  filter  = local.conferencia_filtro

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"

    labels {
      key         = "categoria"
      value_type  = "STRING"
      description = "dinheiro (custa ao cliente) ou dado (só interno)."
    }
  }

  label_extractors = {
    categoria = "REGEXP_EXTRACT(jsonPayload.dados, \"\\\"categoria\\\":\\\\s*\\\"([^\\\"]+)\\\"\")"
  }
}

# Mesma corrida do módulo alerta-generico: o descritor demora a aparecer na API.
resource "time_sleep" "conferencia_propagacao" {
  depends_on      = [google_logging_metric.conferencia_diferenca]
  create_duration = "360s"

  triggers = {
    metric = google_logging_metric.conferencia_diferenca.id
  }
}

locals {
  conferencia_politicas = {
    dinheiro = {
      titulo     = "Conferência do salão — diferença em DINHEIRO"
      categoria  = "dinheiro"
      caixa      = "dinheiro"
      severidade = "ERROR"
      janela     = "60s" # a cada vez: sem digestão
      doc        = <<-EOT
        A conferência diária (passo 5/5 do analytics-diario) achou diferença
        entre o salão e os eventos que mexe com dinheiro: pagamento sem evento,
        evento sem pagamento ou valor divergente.

        Onde olhar: Cloud Logging, projeto cm-ventures-core,
        `jsonPayload.event="conferencia.diferenca" AND jsonPayload.dados=~"dinheiro"`.
        `dados` traz dia, linhas_sem_evento, eventos_sem_linha,
        pagamentos_valor_divergente e diferenca_centavos.
      EOT
    }
    dado = {
      titulo     = "Conferência do salão — diferença de dado (digest)"
      categoria  = "dado"
      caixa      = "interno"
      severidade = "WARNING"
      janela     = "86400s" # digest: um incidente por dia
      doc        = <<-EOT
        A conferência diária achou diferença de dado sem efeito direto em
        dinheiro. Não é urgente; entra uma vez por dia.

        Onde olhar: Cloud Logging, projeto cm-ventures-core,
        `jsonPayload.event="conferencia.diferenca" AND jsonPayload.dados=~"dado"`.
      EOT
    }
  }
}

resource "google_monitoring_alert_policy" "conferencia" {
  for_each   = local.conferencia_politicas
  depends_on = [time_sleep.conferencia_propagacao]

  project      = var.project_id
  display_name = each.value.titulo
  combiner     = "OR"
  severity     = each.value.severidade

  conditions {
    display_name = "Conferência registrou diferença (${each.value.categoria})"

    condition_threshold {
      filter = join(" AND ", [
        "resource.type = \"cloud_run_job\"",
        "metric.type = \"logging.googleapis.com/user/${local.conferencia_metric}\"",
        "metric.label.categoria = \"${each.value.categoria}\"",
      ])
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      aggregations {
        alignment_period     = each.value.janela
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["metric.label.categoria"]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [var.canais[each.value.caixa]]

  alert_strategy {
    auto_close = "86400s"
  }

  documentation {
    content   = each.value.doc
    mime_type = "text/markdown"
  }
}
