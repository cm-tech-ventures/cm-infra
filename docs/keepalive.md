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

1. Obter o DSN Postgres (connection string) do projeto Supabase. Preferir o
   pooler e conferir se o host é `aws-0` ou `aws-1` (ver "Cuidado" abaixo).
2. Atualizar o secret `keepalive-db-dsns` no Secret Manager do projeto
   `cm-ventures-core`, concatenando o novo DSN com `;`:
   ```
   gcloud secrets versions add keepalive-db-dsns --project cm-ventures-core \
     --data-file=- <<< "$DSN_EXISTENTE;$DSN_NOVO"
   ```
3. Nenhuma mudança de Terraform é necessária — o job lê o secret em runtime.
4. Registrar a posse do projeto Supabase em `docs/supabase-projects.md` e
   incluir o banco na tabela "Bancos cobertos hoje" abaixo.

## Bancos cobertos hoje

Lista do secret `keepalive-db-dsns` (cm-ventures-core) a partir da versão 7,
de 06/10/2026: 6 DSNs. Aqui ficam só o ref e o host. Usuário e senha ficam
apenas no secret.

| Project ref | Sistema | Conexão | Desde |
|---|---|---|---|
| `uooowvvrblslwszmcghp` | a identificar | pooler `aws-1` | antes da v7 |
| `aoriyfujsilisrrvadxy` | `sys-bjj-backend` (bjj-system) | direta, `db.<ref>.supabase.co` | 2026-07-29 ([CMV-297](/CMV/issues/CMV-297)) |
| `pmbgbvmwwiezajsveswv` | a identificar | pooler `aws-0` | antes da v7 |
| `iimjsfqodjeybzdwjowz` | a identificar | pooler `aws-0` | antes da v7 |
| `jwyjqiezwjccnxrbmlai` | MD produção: Supabase `md-backend`, servido pelo GCP `md-hom` | pooler `aws-1-sa-east-1`, porta 5432 | 2026-10-06 (v7) |
| `ajjlyugjutltxyepzbhk` | MD homologação: Supabase `md-backend-prod`, ligado ao GCP `md-hlg` | pooler `aws-1-sa-east-1`, porta 5432 | 2026-10-06 (v7) |

O banco dos cores (`cm-ventures-core`) é um projeto Supabase só, usado por
cm-identity, cm-crm e os outros cores: mesmo host, schemas diferentes. Ele
está entre os refs "a identificar" acima. Quem confirmar qual é qual deve
preencher a coluna.

Os dois bancos do MD entraram pela etapa
[cm-infra#59](https://github.com/cm-tech-ventures/cm-infra/issues/59), parte
da virada de ambientes do MD
([md-backend#308](https://github.com/cadusds2/md-backend/issues/308)). O
`md-backend-prod` pausava sozinho justamente por estar fora desta lista. O
nome engana: ele é a homologação nova do MD, não a produção.

### Cuidado: o pooler pode ser `aws-0` ou `aws-1`, conferir por projeto

O host do pooler muda de projeto para projeto, mesmo na mesma região. Os dois
bancos do MD só respondem pelo `aws-1-sa-east-1.pooler.supabase.com`. Pelo
`aws-0`, a resposta é `tenant/user not found`, que parece erro de senha mas é
host errado. Antes de pôr um DSN novo no secret:

1. Pegar o host certo no dashboard do projeto (Connect → Session pooler), sem
   supor pelo host dos outros projetos.
2. Testar com `psql "<dsn>" -c 'select 1'`.
3. O usuário do pooler tem o formato `postgres.<ref>`.

### Cuidado: connection string direta (`db.<ref>.supabase.co`) some do DNS durante a pausa

Ao adicionar o DSN do `sys-bjj-backend` (CMV-297), a execução manual de
verificação falhou com erro de resolução de nome (`Name or service not
known` / `NXDOMAIN`, confirmado até contra `8.8.8.8` diretamente) para o
host `db.aoriyfujsilisrrvadxy.supabase.co` — o formato de conexão direta que
o serviço usa. Isso é esperado enquanto o projeto Supabase segue pausado (no
momento deste commit o board ainda estava restaurando o projeto no
dashboard): o registro DNS do host de conexão direta some por completo
enquanto o projeto está pausado, então o keep-alive não consegue nem
resolver o host até o board concluir a restauração manual — o próprio
keep-alive não tem como "acordar" um projeto nesse estado.

Depois que o board confirmar a restauração, rodar de novo o passo de
"Teste de falha" abaixo (execução manual) para confirmar `succeeded` cobrindo
os 3 bancos.

Recomendação para reduzir a fragilidade desse tipo de incidente: assim que o
projeto do sys-bjj estabilizar, considerar trocar o `DATABASE_URL` do
`sys-bjj-backend` (e o DSN aqui no keep-alive) do formato de conexão direta
para o do connection pooler Supabase (Supavisor, host
`aws-*.pooler.supabase.com`, mesmo padrão já usado pelo banco dos cores) —
não elimina o problema de pausa em si, mas evita depender de um registro DNS
que desaparece por completo enquanto o projeto está pausado.

## Checklist: todo banco novo entra no keep-alive no dia em que nasce

Sempre que um core ou vertical ganhar um banco Supabase novo (novo projeto
Supabase, não só um schema novo em banco já coberto), antes de considerar o
serviço pronto para uso real:

1. Seguir os passos de "Adicionar um novo banco à lista" acima.
2. Confirmar execução verde do job `keepalive-check` cobrindo o novo DSN.
3. Registrar o projeto em `docs/supabase-projects.md` (posse + issue de
   referência).

Isso é responsabilidade do Platform Engineer no momento em que o serviço
nasce — não deixar para o 1º incidente de pausa por free-tier descobrir que
o banco ficou de fora (este é o 3º: [CMV-50](/CMV/issues/CMV-50)/[CMV-55](/CMV/issues/CMV-55),
[CMV-297](/CMV/issues/CMV-297)).

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
