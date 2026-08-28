# Padrão de observabilidade dos serviços (CMV-595, CMV-602)

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
linha JSON por request:

```json
{"event": "http_request", "request_id": "...", "org_id": "...", "method": "POST",
 "path": "/api/...", "status_code": 500, "latency_ms": 42.1, "error": "..."}
```

Nunca logar payload de corpo de requisição nem token/Authorization — só
metadados (mesma regra do ADR-003 §3 para mensagens de erro).

Serviços não-Django (ex. cm-mcp, FastMCP) mantêm sua própria implementação do
mesmo formato (`event`, `status`, campo de latência, campo de erro) —
`service/observability.py` do cm-mcp/md-mcp segue o mesmo contrato e adota a
convenção de `logName` abaixo (CMV-602).

### Convenção de `logName` (CMV-602)

Em Cloud Run, escrever com `print()`/stdout faz o Cloud Run capturar o log e
indexá-lo automaticamente no Cloud Logging **sob o logName padrão
`run.googleapis.com/stdout`** — junto com qualquer outro print/traceback não
estruturado do processo. Isso tem duas consequências ruins, descobertas na
prática nas CMV-593/594/597/598/599/601:

1. Um sink Cloud Logging → BigQuery apontado para esses logs gera uma tabela
   com nome ilegível (`run_googleapis_com_stdout` ou `_YYYYMMDD`), nunca um
   nome intencional como `tool_calls`.
2. Mistura o log de aplicação com qualquer outra coisa que caia no stdout do
   processo — dificulta filtrar/tipar por sink.

Por isso, `RequestLoggingMiddleware` escreve **direto no Cloud Logging** via
client oficial (`google-cloud-logging`), sob um **`logName` customizado e
explícito** (`settings.OBSERVABILITY_LOG_NAME`, env `LOG_NAME`, default
`app-events`) — nunca via stdout. Fora do Cloud Run (dev local, testes,
detectado por ausência da env `K_SERVICE`), continua caindo no logger stdlib
de stdout, sem custo de autenticação contra o Cloud Logging real.

Convenção de nome: um `logName` por domínio de evento, não por serviço —
`app-events` é o default genérico do template; serviços com um domínio de
evento próprio e volume relevante (ex. `tool-calls` no cm-mcp/md-mcp) devem
sobrescrever via `var.log_name` no `infra/main.tf`. Isso faz qualquer sink
futuro derivar um nome de tabela BigQuery legível automaticamente
(`google_logging_project_sink` particiona por logName), sem reverse-engineering
como nas issues citadas acima.

A SA dedicada do serviço (módulo `cloud-run-service`) recebe
`roles/logging.logWriter` no projeto para essas chamadas funcionarem — não é
mais implícito via SA de compute default.

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
não bloqueia o apply enquanto o canal não estiver definido. Reusar o canal de
e-mail já existente em `cm-ventures-core` (mesmo do keepalive Supabase,
CMV-53) é a opção default; só criar canal novo se o board pedir notificação
segregada por serviço.

## 3. Sink Cloud Logging → BigQuery (opcional, por serviço)

Para consulta/dashboard consistente sobre o histórico de logs estruturados
(não só o log-based metric acima, que é só contagem), o padrão é um
`google_logging_project_sink` filtrado por `logName="projects/<project>/logs/<log_name>"`
(ver convenção de `logName` na seção 1) apontando para um dataset BigQuery —
**o mesmo mecanismo usado no mart de observabilidade do cm-mcp no cm-analytics
(CMV-593)**, que serve de modelo replicável.

**Migração pendente (CMV-602, sem urgência)**: o sink `cm-mcp-tool-calls-to-bq`
(md-hom) e a extração do cm-analytics (CMV-601) ainda apontam para o logName
antigo (`run.googleapis.com/stdout`, tabela `run_googleapis_com_stdout`) — o
pipeline atual continua funcionando com esse nome até a migração para o
logName customizado (`tool-calls`) acontecer; não é bloqueante.

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
  filter      = "logName=\"projects/${var.project_id}/logs/${var.log_name}\" AND resource.labels.service_name=\"${var.service_name}\""

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
2. **cm-crm, cm-scheduling** — cores mais recentes, menor superfície de
   request, bom lugar para validar o middleware em produção sem risco alto.
3. **cm-identity** — crítico (introspecção usada por todos os outros cores);
   adotar só depois do padrão validado nos passos 1-2, e sem o sink BigQuery
   inicialmente (só log + alerta).
4. **cm-erp, cm-billing** — mesma prioridade, paralelizáveis entre si.
5. **md-backend, sys-bjj-backend** — donos são VerticalMD/VerticalBJJ, fora
   do território do PlatformEngineer; a adoção nesses dois é responsabilidade
   do dono de cada serviço, este documento só define o padrão a seguir.

Cada adoção é: (a) copiar/atualizar `service/common/observability/` a partir
do template (ou depender de `cm-sdk` se/quando esse código for promovido lá),
(b) instalar `RequestLoggingMiddleware` em `MIDDLEWARE`, (c) opcionalmente
instanciar `modules/log-error-alert` no `infra/main.tf` do serviço. Não expande
o escopo desta issue — cada adoção é uma issue própria do dono do serviço.
