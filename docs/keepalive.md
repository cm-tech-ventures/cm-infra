# Keep-alive dos bancos Supabase free-tier (CMV-53)

## Contexto

O free-tier do Supabase pausa projetos por inatividade (~7 dias sem
atividade). Isso já causou dois incidentes — o banco antigo do Paperclip e o
outage do `backend-md` em md-hom ([CMV-50](/CMV/issues/CMV-50)/[CMV-52](/CMV/issues/CMV-52)).
Enquanto as verticais não têm uso real contínuo, este job evita a pausa.

**Isto é um paliativo de fase pré-produção, não solução permanente.** Quando
uma vertical entrar em produção com uso real e contínuo, avaliar upgrade do
projeto Supabase correspondente para tier pago em vez de depender do
keep-alive — o keep-alive não resolve latência de cold start nem os outros
limites do free-tier (storage, banda, etc).

## Como funciona

- `jobs/keepalive/`: script Python que roda `SELECT 1` em cada DSN da lista
  (env `KEEPALIVE_DB_DSNS`, separados por `;`). Falha (`exit 1`) se qualquer
  DSN estiver inacessível — nunca engole erro silenciosamente.
- `modules/cloud-run-job`: módulo genérico de Cloud Run Job (SA dedicada,
  segredos via Secret Manager, sem worker permanente).
- `modules/scheduler-job`: Cloud Scheduler dispara a execução via Run Admin
  API (`auth_mode = "oauth"`, escopo `cloud-platform`) a cada 3 dias.
- `modules/monitoring-alert-email`: canal de e-mail + alerta de Cloud
  Monitoring quando o job falha (`run.googleapis.com/job/completed_execution_count`
  com `result = "failed"`).
- `environments/keepalive/`: instancia os três módulos acima no projeto
  `cm-ventures-core`.

## Adicionar um novo banco à lista

1. Obter o DSN Postgres (connection string) do projeto Supabase.
2. Atualizar o secret `keepalive-db-dsns` no Secret Manager do projeto
   `cm-ventures-core`, concatenando o novo DSN com `;`:
   ```
   gcloud secrets versions add keepalive-db-dsns --project cm-ventures-core \
     --data-file=- <<< "$DSN_EXISTENTE;$DSN_NOVO"
   ```
3. Nenhuma mudança de Terraform é necessária — o job lê o secret em runtime.
4. Registrar a posse do projeto Supabase em `docs/supabase-projects.md`.

Hoje a lista cobre apenas o banco dos cores (`cm-ventures-core`, projeto
Supabase único para cm-identity/cm-crm/etc — mesmo host, schemas
diferentes). O banco do `backend-md` (md-hom) entra assim que a transferência
de organização em [CMV-54](/CMV/issues/CMV-54) for concluída.

## Publicar uma nova imagem do job

```
gcloud builds submit --project cm-ventures-core \
  --tag southamerica-east1-docker.pkg.dev/cm-ventures-core/cm-cores/keepalive-check:vN \
  jobs/keepalive
```

Depois atualizar `image` em `environments/keepalive/terraform.tfvars` e
aplicar.

## Teste de falha (runbook de verificação do alerta)

1. Apontar temporariamente o secret `keepalive-db-dsns` para um host
   inválido.
2. Disparar uma execução manual:
   `gcloud run jobs execute keepalive-check --project cm-ventures-core --region southamerica-east1 --wait`
   — a execução deve terminar como `failed`.
3. Conferir nos logs do Cloud Run Job que a causa foi reportada sem vazar
   credencial (o script só loga o host, nunca usuário/senha).
4. Conferir em Cloud Monitoring que a métrica
   `run.googleapis.com/job/completed_execution_count{result="failed"}`
   subiu — isso é exatamente o filtro da política de alerta
   `Keep-alive Supabase (CMV-53) — execução falhou`, que notifica por e-mail
   o canal configurado em `notification_email`.
5. Restaurar o secret para o(s) DSN(s) válido(s) e rodar a execução manual
   de novo para confirmar recuperação (`succeeded`).

Verificado em 2026-07-15: passos 1-5 executados manualmente contra o projeto
`cm-ventures-core` — execução falhou como esperado, métrica de falha
apareceu corretamente filtrada pela política de alerta, e a execução
seguinte com DSN válido voltou a `succeeded`.
