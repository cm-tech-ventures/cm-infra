# Alerta genérico de rotina agendada. Um módulo, dois sensores — porque uma
# rotina pode morrer de duas formas diferentes e só um sensor vê cada uma:
#
#   sensor = "scheduler"  o relógio tocou e a chamada não voltou 2xx.
#   sensor = "job"        a execução nasceu e morreu no meio do trabalho.
#
# Os dois são necessários: nas rotinas disparadas como Cloud Run Job via API de
# administração, o Scheduler recebe 200 quando a execução é CRIADA — se o
# trabalho quebrar depois, o Scheduler segue verde. O verde dele é mentira por
# construção nesses casos, e só o sensor "job" enxerga a falha.
#
# O canal de notificação NÃO é criado aqui, de propósito: e-mail verificado por
# clique e Slack autorizado por OAuth são consentimentos humanos que o Terraform
# não enxerga. Se ele gerenciasse o recurso, um apply futuro poderia recriá-lo e
# perder a autorização em silêncio. O canal nasce à mão; aqui só se consome o id.

locals {
  # O Cloud Scheduler não publica métrica no Cloud Monitoring (conferido em
  # 24/09/2026: zero descritores `cloudscheduler.googleapis.com/*` no projeto).
  # Ele publica LOG, então o sensor de relógio é uma métrica derivada de log.
  # O rótulo é só `job_id` — uma dezena de valores. Nunca use identificador de
  # cliente (org_id, user_id, request_id) como rótulo aqui: métrica de log é
  # cobrada por cardinalidade, e um rótulo por cliente estoura a cota gratuita.
  is_scheduler = var.sensor == "scheduler"

  filtro_jobs = length(var.alvo) == 0 ? "" : format(
    " AND (%s)",
    join(" OR ", [for j in var.alvo : "resource.labels.job_id=\"${j}\""])
  )

  metric_name = "alertas/${var.nome}_scheduler_errors"
}

resource "google_logging_metric" "scheduler_errors" {
  count = local.is_scheduler ? 1 : 0

  name    = local.metric_name
  project = var.project_id
  filter  = "resource.type=\"cloud_scheduler_job\" AND severity>=ERROR${local.filtro_jobs}"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"

    labels {
      key         = "job_id"
      value_type  = "STRING"
      description = "Nome do job do Cloud Scheduler."
    }
  }

  label_extractors = {
    job_id = "EXTRACT(resource.labels.job_id)"
  }
}

# O descritor de uma métrica derivada de log leva até ~10 min para ficar
# visível na API do Monitoring, e a política abaixo referencia a métrica pelo
# tipo. Sem esta espera, o primeiro apply cria a métrica e falha na política
# com 404 — corrida real, observada em 24/09/2026 no bjj-system. Nos applies
# seguintes a espera não reexecuta: ela só depende do id da métrica.
resource "time_sleep" "propagacao_da_metrica" {
  count = local.is_scheduler ? 1 : 0

  depends_on      = [google_logging_metric.scheduler_errors]
  create_duration = var.espera_propagacao

  triggers = {
    metric = google_logging_metric.scheduler_errors[0].id
  }
}

resource "google_monitoring_alert_policy" "alerta" {
  depends_on = [time_sleep.propagacao_da_metrica]

  project      = var.project_id
  display_name = var.titulo
  combiner     = "OR"
  severity     = var.severidade

  dynamic "conditions" {
    for_each = local.is_scheduler ? [1] : []
    content {
      display_name = "Tentativa do Cloud Scheduler não voltou 2xx"

      condition_threshold {
        filter = join(" AND ", [
          "resource.type = \"cloud_scheduler_job\"",
          "metric.type = \"logging.googleapis.com/user/${local.metric_name}\"",
        ])
        comparison      = "COMPARISON_GT"
        threshold_value = 0
        duration        = "0s"

        aggregations {
          alignment_period     = var.janela
          per_series_aligner   = "ALIGN_SUM"
          cross_series_reducer = "REDUCE_SUM"
          group_by_fields      = ["metric.label.job_id"]
        }

        trigger {
          count = 1
        }
      }
    }
  }

  dynamic "conditions" {
    for_each = local.is_scheduler ? [] : [1]
    content {
      display_name = "Execução de Cloud Run Job terminou em falha"

      condition_threshold {
        # Métrica nativa do Cloud Run, conferida em 24/09/2026. Sem filtro por
        # job_name quando `alvo` está vazio: uma política cobre os jobs de hoje
        # e os que nascerem amanhã, sem PR novo.
        filter = join(" AND ", concat([
          "resource.type = \"cloud_run_job\"",
          "metric.type = \"run.googleapis.com/job/completed_execution_count\"",
          "metric.label.result = \"failed\"",
          ], length(var.alvo) == 0 ? [] : [
          format("(%s)", join(" OR ", [for j in var.alvo : "resource.label.job_name = \"${j}\""])),
        ]))
        comparison      = "COMPARISON_GT"
        threshold_value = 0
        duration        = "0s"

        aggregations {
          alignment_period     = var.janela
          per_series_aligner   = "ALIGN_COUNT"
          cross_series_reducer = "REDUCE_SUM"
          group_by_fields      = ["resource.label.job_name"]
        }

        trigger {
          count = 1
        }
      }
    }
  }

  notification_channels = [var.canal_id]

  alert_strategy {
    auto_close = "86400s"

    # NÃO use notification_rate_limit aqui: a API só o aceita em política
    # baseada em log (`conditionMatchedLog`), e recusa com 400 nas de limiar,
    # que são as destas. Conferido no apply de 24/09/2026.
    #
    # A digestão sai de outro lugar, e de graça: o Cloud Monitoring notifica
    # uma vez quando o incidente ABRE e não renotifica enquanto ele segue
    # aberto. Com `janela` de 86400s, as falhas do dia caem todas no mesmo
    # incidente e geram uma notificação só. Quem controla o ritmo é a janela,
    # não um limite de frequência.
  }

  documentation {
    content   = var.documentacao
    mime_type = "text/markdown"
  }
}
