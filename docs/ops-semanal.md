# Ops semanal — rotina de observabilidade (v0)

Rotina automatizada (Paperclip routine, trigger `schedule`, semanal — segunda de
manhã) que executa 4 checks read-only sobre a infraestrutura da CM Ventures e
publica um relatório em comentário na issue fixa **CMV-320 — "Ops semanal —
relatórios de observabilidade"**.

Design aprovado pelo CTO em CMV-318. Implementação: CMV-319.

## Regra de ouro

A rotina **só lê** (list/describe/logs read). Nunca executa ação de escrita no
GCP, GitHub ou Paperclip. Qualquer anomalia que exija ação vira uma **issue
própria**, linkada ao comentário-relatório — nunca uma correção direta a
partir da rotina.

## Autenticação: SA `cm-ops-observer` via impersonation

Sem chave JSON. A SA é criada no `bootstrap/main.tf` (projeto
`cm-ventures-core`) com:
- `roles/run.viewer`
- `roles/monitoring.viewer`
- `roles/logging.viewer`
- `roles/billing.viewer` na billing account `013EE2-6E67DB-A423CD`

`roles/iam.serviceAccountTokenCreator` sobre a SA é concedido à identidade
local que roda a rotina (`var.ops_observer_impersonators` em
`bootstrap/terraform.tfvars`, hoje `user:cm.tech.ventures@gmail.com` — a
conta ADC usada pelo agente PlatformEngineer).

Todo comando `gcloud` da rotina usa:

```
--impersonate-service-account=cm-ops-observer@cm-ventures-core.iam.gserviceaccount.com
```

Fallback documentado (só como transição, não estado final): se a
impersonation causar atrito no primeiro run, usar ADC diretamente com a regra
estrita de "somente list/describe/read" até a impersonation ser corrigida.

## Os 4 checks

### 1. CI/CD

Para cada repo — `cm-analytics`, `cm-crm`, `cm-identity`, `cm-infra`:

```
gh run list --repo cm-tech-ventures/<repo> --limit 1 --json status,conclusion,createdAt,workflowName
```

Anomalia se: último run `conclusion != success` (quebrado), OU está
`in_progress`/vermelho há mais de 24h.

### 2. BI/pipeline (cm-analytics)

**Enquanto F1.3 (CMV-259) não estiver implantado**: reportar
`pipeline não implantado — n/a`. Não tentar os comandos abaixo.

Quando implantado:

```
gcloud run jobs executions list --job=<job-do-cm-analytics> \
  --project=cm-ventures-core --region=southamerica-east1 \
  --impersonate-service-account=cm-ops-observer@cm-ventures-core.iam.gserviceaccount.com \
  --limit=1 --format=json

gcloud scheduler jobs describe <scheduler-job-do-cm-analytics> \
  --project=cm-ventures-core --location=southamerica-east1 \
  --impersonate-service-account=cm-ops-observer@cm-ventures-core.iam.gserviceaccount.com \
  --format="value(schedule)"
```

A fonte da verdade do intervalo é o **Scheduler implantado**
(`gcloud scheduler jobs describe`), nunca o `.tfvars` — drift entre os dois
não deve virar falso negativo.

Anomalia se: última execução falhou, OU idade da última execução
bem-sucedida > 2× o intervalo do cron lido do Scheduler.

Frescor de dados (dbt source freshness) fica para v1 — fora do escopo desta
rotina.

### 3. GCP

**Alertas disparados:**
```
gcloud monitoring policies list --project=cm-ventures-core \
  --impersonate-service-account=cm-ops-observer@cm-ventures-core.iam.gserviceaccount.com \
  --format=json
gcloud alpha monitoring channels list --project=cm-ventures-core \
  --impersonate-service-account=cm-ops-observer@cm-ventures-core.iam.gserviceaccount.com
```
(ou consultar incidentes recentes via Cloud Monitoring API/console, se o CLI
não expor incidentes diretamente — o objetivo é saber se algum alert policy
dos módulos `monitoring-alert-email` disparou na semana.)

**5xx nos serviços Cloud Run** (logging, últimos 7 dias):
```
gcloud logging read \
  'resource.type="cloud_run_revision" AND httpRequest.status>=500' \
  --project=cm-ventures-core --freshness=7d --limit=50 \
  --impersonate-service-account=cm-ops-observer@cm-ventures-core.iam.gserviceaccount.com
```
Anomalia se: houver 5xx recorrente (não isolado) em algum serviço.

**Custo:**
Se não houver BigQuery billing export configurado, reportar apenas o estado
dos budget alerts (`gcloud billing budgets list`, se acessível via
`roles/billing.viewer`) e anotar a limitação no relatório — não tentar
comparar custo do mês vs. média histórica sem export. Criar o export é
candidato a v1, não pré-requisito da v0.

### 4. Paperclip

Via API Paperclip (`GET /api/companies/{companyId}/issues`):
- Issues `blocked` sem dono nomeado no comentário de bloqueio, ou paradas
  (sem atividade) há mais de 7 dias.
- Runs com erro recentes (se a API expuser).
- Andamento da Fase 3.5 (issues do board sob o parentId correspondente) e do
  goal G2.

## Deduplicação de achados (obrigatório antes de abrir issue)

Antes de criar qualquer issue a partir de uma anomalia, seguir o protocolo
em [`dedup-achados-rotinas.md`](./dedup-achados-rotinas.md): buscar issue
existente por um identificador estável do achado (nome do serviço, id do
recurso — nunca a frase descritiva), comentar na issue aberta se já existir,
e só abrir issue nova se a busca não retornar nada relacionado. Toda issue
nova deve usar um identificador estável no título.

## Formato do relatório (obrigatório)

Comentário em pt-BR na issue **CMV-320**:
- **Só anomalias**, cada uma com uma ação sugerida (ex.: "abrir issue X",
  "investigar Y").
- **1 linha "ok"** por área quando não há anomalia — nunca uma parede de
  status verde detalhado.
- Anomalias que exigem ação viram **issues próprias** (após checar
  deduplicação, ver seção acima), linkadas no comentário (ex.:
  `Anomalia → CMV-XXX`). A rotina nunca corrige nada diretamente no GCP,
  GitHub ou Paperclip.

Exemplo de estrutura:

```
## Ops semanal — 2026-08-03

- CI/CD: ok (4/4 repos verdes)
- BI/pipeline: não implantado — n/a (aguarda CMV-259)
- GCP: anomalia — 12 5xx em `crm` nas últimas 24h (ver logs). Ação sugerida:
  investigar em CMV-XXX (criada).
- Paperclip: ok (nenhum bloqueio >7 dias sem dono; Fase 3.5 em andamento
  conforme esperado)
```

## Executor

Routine Paperclip: trigger `schedule` (semanal, segunda de manhã), agente
PlatformEngineer, `claude-sonnet-5`, effort `low`, 1 run por disparo.
