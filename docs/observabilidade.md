# Padrão de observabilidade dos serviços (CMV-595)

> **Escopo:** este documento cobre o eixo **erro de aplicação** (5xx, exceção com
> contexto), via log estruturado + `log-error-alert`. O eixo **rotina agendada**
> (o relógio tocou? o trabalho terminou?) está em [alertas.md](alertas.md), que é
> onde fica o padrão em produção desde 24/09/2026. Os dois convivem e não se
> substituem.

**Decisão do board (2026-08-18)**: em vez de adotar uma stack de
observabilidade dedicada (Datadog, Grafana/Loki), generalizamos o padrão
criado no cm-mcp (CMV-498, log estruturado + métrica log-based) como parte do
`cm-service-template` e do `cm-infra`. Racional: os serviços já rodam em Cloud
Run no mesmo projeto GCP — o Cloud Logging já é um repositório centralizado de
fato. O que faltava era padronização (cada serviço loga do seu jeito, ou não
loga nada) e uma camada de consulta consistente.

Fora de escopo, por decisão explícita: qualquer ferramenta paga de
observabilidade (Datadog/Grafana Cloud/etc.), dado o tamanho atual da
operação.

## 1. Log estruturado (aplicação)

`cm-service-template` traz `service/common/observability/middleware.py`
(`RequestLoggingMiddleware`), instalado por padrão em `MIDDLEWARE`. Loga uma
linha JSON por request em stdout — Cloud Run captura e indexa automaticamente
em Cloud Logging, sem client de logging adicional:

```json
{"event": "http_request", "request_id": "...", "org_id": "...", "method": "POST",
 "path": "/api/...", "status_code": 500, "latency_ms": 42.1, "error": "..."}
```

Nunca logar payload de corpo de requisição nem token/Authorization — só
metadados (mesma regra do ADR-003 §3 para mensagens de erro).

Serviços não-Django (ex. cm-mcp, FastMCP) mantêm sua própria implementação do
mesmo formato (`event`, `status`, campo de latência, campo de erro) —
`service/observability.py` do cm-mcp já segue esse contrato; não precisa
migrar para o middleware Django.

## 2. Métrica de erro + alerta (Terraform)

`modules/log-error-alert` (novo, cm-infra) generaliza o log-based metric +
alerting policy que o CMV-498 criou ad-hoc no `infra/main.tf` do cm-mcp.
Conta linhas `jsonPayload.event=<log_event>, jsonPayload.status="error"` por
serviço e dispara um alerta de taxa de erro. Uso opcional no `infra/main.tf`
de cada serviço (thin main.tf continua sendo a regra — isto é ~6 linhas):

```hcl
module "error_alert" {
  source = "git::https://github.com/cm-tech-ventures/cm-infra.git//modules/log-error-alert?ref=main"

  project_id               = var.project_id
  service_name             = var.service_name
  log_event                = "http_request"          # default; "tool_call" no cm-mcp
  label_field               = "path"                  # default; "tool" no cm-mcp
  notification_channel_id  = var.alert_notification_channel_id  # opcional
}
```

Sem `notification_channel_id`, a política é criada mas não notifica ninguém —
não bloqueia o apply enquanto o canal não estiver definido.

**Atualização de 24/09/2026 — a orientação de canal mudou.** O default deixou de
ser "reusar o canal de e-mail do keepalive": a entrega agora é por **Slack**, em
duas caixas (`#dinheiro-cliente` e `#dado-interno`), e **o Terraform nunca cria o
canal** — ele nasce à mão e só o id é consumido. O motivo e os ids estão em
[alertas.md §5](alertas.md). Ao instanciar este módulo, aponte para a caixa certa:
erro de aplicação em serviço sem cliente do outro lado é `#dado-interno`.

**⚠ Cardinalidade.** O `label_field` deste módulo vira rótulo de uma métrica
derivada de log, que é cobrada por quantas combinações gera (150 MiB/mês grátis,
depois US$ 0,258/MiB). O comentário do módulo sugere `request_id/org_id` — **não
use nenhum dos dois**: `org_id` é identificador de cliente e `request_id` é um
valor por requisição, e qualquer um estoura a cota. Prefira rótulo de baixa
cardinalidade (`path`, `tool`, `status`).

## 3. Sink Cloud Logging → BigQuery (opcional, por serviço)

Para consulta/dashboard consistente sobre o histórico de logs estruturados
(não só o log-based metric acima, que é só contagem), o padrão é um
`google_logging_project_sink` filtrado por `jsonPayload.event=<...>` apontando
para um dataset BigQuery — **o mesmo mecanismo usado no mart de observabilidade
do cm-mcp no cm-analytics (CMV-593)**, que serve de modelo replicável.

Isto **não é padrão de saída obrigatório do template** — é opt-in por
serviço, habilitado quando o serviço tiver necessidade real de
dashboard/consulta histórica (ex. incidentes recorrentes, SLA a acompanhar).
Serviços que só precisam do alerta em tempo real (seção 2) não precisam do
sink.

Esqueleto de referência (a instanciar manualmente no `infra/main.tf` do
serviço que optar por habilitar, seguindo o padrão do CMV-593 em
`cm-analytics/terraform`):

```hcl
resource "google_bigquery_dataset" "observability" {
  project    = var.project_id
  dataset_id = "${replace(var.service_name, "-", "_")}_observability"
  location   = var.region
}

resource "google_logging_project_sink" "observability" {
  name        = "${var.service_name}-observability-sink"
  project     = var.project_id
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.observability.dataset_id}"
  filter      = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${var.service_name}\" AND jsonPayload.event=\"http_request\""

  bigquery_options {
    use_partitioned_tables = true
  }
}

resource "google_project_iam_member" "sink_writer" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = google_logging_project_sink.observability.writer_identity
}
```

Não extraímos isso como módulo `cm-infra` nesta issue porque só há um caso de
uso concreto até agora (cm-mcp/CMV-593); se um segundo serviço adotar o sink,
extrair para `modules/log-bigquery-sink` nesse momento (regra geral do
template: extrair reutilização quando ela aparece, não antecipar).

## 4. Plano de adoção incremental

Não é para migrar tudo de uma vez. Ordem sugerida, do menor para o maior
risco de ruído (serviços mais novos/menos observados primeiro, para validar o
padrão antes de tocar nos que já têm tráfego real):

1. **cm-service-template** (feito nesta issue) — todo core novo já nasce com
   o middleware + módulo disponível.
2. **cm-crm** — core mais recente, menor superfície de request, bom lugar para
   validar o middleware em produção sem risco alto. (O `cm-scheduling` citado na
   versão original deste plano **nunca foi criado**.)
3. **cm-identity** — crítico (introspecção usada por todos os outros cores);
   adotar só depois do padrão validado nos passos 1-2, e sem o sink BigQuery
   inicialmente (só log + alerta).
4. **cm-billing** — já instancia o módulo, atrás da flag `enable_error_alert`,
   que nasce desligada. (O `cm-erp` citado na versão original **nunca foi
   criado**.) Em 30/09/2026 o log estruturado `service/common/observability`
   existe em **dois repos apenas**: `cm-service-template` e `cm-billing` — ou
   seja, ligar este eixo nos demais exige adotar o log antes, e não é "só ligar a
   flag".
5. **md-backend, sys-bjj-backend** — donos são VerticalMD/VerticalBJJ, fora
   do território do PlatformEngineer; a adoção nesses dois é responsabilidade
   do dono de cada serviço, este documento só define o padrão a seguir.

Cada adoção é: (a) copiar/atualizar `service/common/observability/` a partir
do template (ou depender de `cm-sdk` se/quando esse código for promovido lá),
(b) instalar `RequestLoggingMiddleware` em `MIDDLEWARE`, (c) opcionalmente
instanciar `modules/log-error-alert` no `infra/main.tf` do serviço. Não expande
o escopo desta issue — cada adoção é uma issue própria do dono do serviço.
