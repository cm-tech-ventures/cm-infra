# Protocolo de deduplicação de achados em rotinas (v1)

Toda rotina de ops/checagem que **detecta uma anomalia e considera abrir
issue** deve seguir este protocolo antes de criar qualquer issue nova.

Motivação: revisão de backlog de 2026-08-04 encontrou 5 issues duplicadas
(CMV-215, CMV-251, CMV-279, CMV-299, CMV-309) para o mesmo achado — template
WhatsApp `orcamento_enviado` com `approval_status=approved` no cm-crm vs
`whatsapp.status=received` na Twilio — uma por execução da rotina de
checagem, porque a anomalia é persistente e cada execução a redetecta sem
checar se já existe issue aberta para ela. Ver CMV-387.

## Protocolo (obrigatório antes de `POST /api/companies/{companyId}/issues`)

1. **Buscar issue existente** com
   `GET /api/companies/{companyId}/issues?q=<identificador-estável-do-achado>`.
   O termo de busca é um **identificador estável do recurso** — SID do
   template, nome do serviço Cloud Run, id do recurso GCP, chave do job —
   **nunca a frase descritiva do achado**, que varia a cada execução (datas,
   contagens, redação).
2. **Se existir issue aberta** (`backlog`/`todo`/`in_progress`/`in_review`/
   `blocked`) para o mesmo achado: **comentar nela** com a nova ocorrência
   (data, contagem, o que mudou desde a última checagem) em vez de abrir
   outra. Não criar issue nova.
3. **Se existir apenas issue fechada** (`done`/`cancelled`) e o achado
   voltou a ocorrer: abrir issue nova referenciando a anterior como
   regressão (`Regressão de CMV-XXX`).
4. **Só criar issue nova** quando a busca não retornar nada relacionado ao
   achado.

## Identificador estável no título

Toda issue aberta a partir de um achado de rotina deve usar, no título, um
**identificador estável** do recurso envolvido (SID do template Twilio, nome
do serviço Cloud Run, id do job/scheduler, etc.) — não só uma descrição em
prosa. Isso é o que permite à busca da próxima execução (passo 1) encontrar
a issue na próxima vez que a mesma anomalia for detectada.

Exemplo: `Template WhatsApp HX64c45b9d6177c90aac17b08939b984e2
(orcamento_enviado) aprovado — reenviar teste`, não apenas `Anomalia:
aprovação de template pendente`.

## Escopo

Aplica-se a toda rotina que abre issue a partir de achado detectado
automaticamente, incluindo (lista não exaustiva, atualizar ao adicionar
novas rotinas):

- Ops semanal — observabilidade (`ops-semanal.md`, CMV-320/CMV-319).
- Checagem de aprovação de templates WhatsApp (Twilio Content API).
- Qualquer rotina futura de checagem/monitoramento que crie issues a partir
  de estado externo (GCP, Twilio, Meta, etc.).

## Escopo ampliado (CMV-387, board 2026-08-04): classificação, não só duplicação

A revisão de backlog de 2026-08-04 mostrou dois outros erros de
classificação na rotina de ops semanal, mais caros que a duplicação
original — não são sobre "abrir issue de novo", são sobre "abrir a issue
errada com a prioridade errada":

- **Falso positivo por não entender workflow reusable** (CMV-322, cancelada):
  a rotina tratou runs diretos de workflows `on: workflow_call`-only
  (`deploy-cloud-run.yml`, `build-and-push.yml` em `cm-infra`) como CI
  quebrado, quando esses workflows não podem rodar sozinhos por construção.
- **Quebra real não priorizada** (CMV-323, aberta como `medium`): o `e2e` do
  cm-crm ficou vermelho em `main` por 4 dias seguidos (01–04/08) e não virou
  anomalia de prioridade correspondente, enquanto um `high` foi gasto no
  falso positivo acima.

Correção versionada em [`ops-semanal.md`](./ops-semanal.md), seção "1.
CI/CD": workflows `workflow_call`-only são excluídos da leitura de saúde de
CI (medida pelos repos consumidores, não pelo repo que hospeda o reusable);
workflow recorrente vermelho por ≥2 execuções consecutivas vira anomalia de
primeira classe com prioridade proporcional ao tempo em vermelho.
  de estado externo (GCP, Twilio, Meta, etc.).
