# Padrão de alertas de rotina agendada

**Como criar um alerta novo:** acrescente um item em `environments/alertas-core/alertas.yaml`
(ou `alertas-bjj`), abra PR, leia o `plan`, aplique. Não escreva HCL.

Este documento cobre o eixo **rotina agendada** (o relógio tocou? o trabalho
terminou?). O eixo **erro de aplicação** (5xx, exceção com contexto) é outro, e
está em [observabilidade.md](observabilidade.md) — os dois convivem e não se
substituem.

## 1. O que existe hoje

| Projeto | Política | Severidade | Caixa |
|---|---|---|---|
| `cm-ventures-core` | Régua de cobrança do cm-billing não rodou | ERROR | `#dinheiro-cliente` |
| `cm-ventures-core` | Cloud Scheduler (core) — alguma tentativa falhou | WARNING | `#dado-interno` |
| `cm-ventures-core` | Cloud Run Jobs (core) — alguma execução falhou | WARNING | `#dado-interno` |
| `bjj-system` | sys-bjj — rotina agendada não rodou | ERROR | `#dinheiro-cliente` |

Em produção desde 24/09/2026 (PRs #43 e #44). Custo recorrente: **R$ 0,00** —
políticas e canais do Cloud Monitoring são grátis, e as métricas usadas ou são
nativas do GCP ou são derivadas de log dentro da cota gratuita.

Código: `modules/alerta-generico`, instanciado por `environments/alertas-core`
(state no bucket `cm-ventures-core-tfstate`) e `environments/alertas-bjj`
(bucket `terraform-backend-sys-bjj`).

## 2. Como adicionar um alerta

Um item de lista no YAML do ambiente. Nada mais:

```yaml
- nome: regua-cobranca            # kebab-case, único no arquivo
  titulo: "Régua de cobrança do cm-billing não rodou"
  sensor: scheduler               # scheduler | job
  alvo: [billing-regua-diaria]    # [] = todos do projeto, hoje e no futuro
  caixa: dinheiro                 # dinheiro | interno
  janela: 86400s                  # opcional; default 3600s
  doc: |
    O que o seu eu futuro precisa saber às 23h.
```

O `main.tf` do ambiente lê o arquivo e cria uma política por item. Ele não muda.

Para aplicar: `terraform plan` no diretório do ambiente, **mostrar o plan literal
ao Carlos** (o `cm-infra` não tem CI), e só então `apply`.

## 3. Os dois sensores — e por que são dois

Uma rotina morre de duas formas, e cada sensor só vê uma:

| `sensor` | enxerga | métrica |
|---|---|---|
| `scheduler` | o relógio tocou e a chamada não voltou 2xx | derivada de log |
| `job` | a execução nasceu e morreu no meio do trabalho | nativa do Cloud Run |

**Os dois são necessários.** Nas rotinas disparadas como Cloud Run Job via API de
administração (7 das 10 da casa), o Scheduler recebe 200 quando a execução é
*criada* — se o trabalho quebrar depois, ele segue verde. **O verde do Scheduler
é mentira por construção nesses casos**, e só o sensor `job` enxerga a falha.

Há uma terceira morte que **nenhum dos dois pega**: a rotina responde 200 e não
faz nada (processa zero registro). Detectar isso exige olhar o *resultado*, não o
status — é o *dead man's switch*, ainda não construído. Ver seção 7.

## 4. As duas caixas — e a regra que as sustenta

| `caixa` | canal Slack | severidade | notifica |
|---|---|---|---|
| `dinheiro` | `#dinheiro-cliente` | ERROR | toda vez |
| `interno` | `#dado-interno` | WARNING | uma vez por dia |

**A caixa `dinheiro` só recebe o que custa dinheiro ao cliente ou expõe a empresa
a risco legal.** Hoje são três rotinas: a régua de cobrança do `cm-billing`, a
diária do `bjj-system` (expira reserva da loja **e apaga recorte de rosto por
LGPD**) e a mensal do sys-bjj quando for ligada.

**Se a caixa `dinheiro` passar de dois alertas por semana, o desenho falhou.** O
conserto é tirar item do YAML — não criar filtro no Slack. Medição que originou
esse teto: 34 falhas de execução em 30 dias no core, das quais 87% vinham dos
extratores do `cm-analytics`. Ligar tudo com o mesmo peso enterraria o alerta de
cobrança debaixo de dez e-mails semanais de gráfico desatualizado, e em duas
semanas ninguém abriria nenhum — o que é **pior que não ter alerta**, porque dá a
sensação de que alguém está olhando.

Os canais vivem no workspace Slack **CM Ventures**, que também tem canais de
gente. Por isso **silenciar o `#dado-interno` é obrigatório**, não recomendação:
sem isso ele compete com mensagem humana e quem perde é o alerta.

## 5. O canal nasce à mão. Sempre.

O Terraform **não cria** canal de notificação, de propósito. Verificação de e-mail
(clique no link) e autorização do Slack (OAuth) são consentimentos humanos que ele
não enxerga — se gerenciasse o recurso, um `apply` futuro poderia recriá-lo e
**perder a autorização em silêncio**.

O canal se cria no console (**Alerting → Notification channels**) e o Terraform só
consome o id, via `terraform.tfvars` (os `.example` de cada ambiente têm os ids
atuais; `*.tfvars` é gitignored por convenção do repo).

É a diferença central para `modules/monitoring-alert-email`, que cria canal e
política juntos e por isso **não serve para reuso**.

Listar os ids:

```bash
gcloud beta monitoring channels list --project=cm-ventures-core
```

**Canal é por projeto.** O id do `cm-ventures-core` não vale no `bjj-system` —
cada projeto precisa do seu, apontando para o mesmo canal do Slack.

**Gotcha do Slack:** autorizar o app no workspace **não** o coloca nos canais. É
preciso `/invite @Google Cloud Monitoring` dentro de cada canal, senão o teste
falha com `channel_not_found`.

## 6. Armadilhas da API, todas descobertas aplicando

**O Cloud Scheduler não publica métrica no Cloud Monitoring.** Zero descritores
`cloudscheduler.googleapis.com/*` (conferido varrendo os 8.929 descritores do
projeto em 24/09/2026). Ele publica **log**. Por isso o sensor `scheduler` é uma
métrica derivada de log sobre `resource.type="cloud_scheduler_job" AND
severity>=ERROR`. Alertar sobre a métrica inexistente passa no `plan` e nunca
dispara — falha silenciosa dentro da ferramenta anti-falha-silenciosa.

**`notification_rate_limit` só vale para política baseada em log.** Em política de
limiar a API recusa com `Error 400: only log-based alert policies may specify a
notification rate limit`. **Não insista:** o Cloud Monitoring notifica uma vez
quando o incidente *abre* e não renotifica enquanto ele segue aberto, então
`janela: 86400s` produz a digestão de graça. **Quem controla o ritmo é a janela de
agregação.**

**O descritor de uma métrica de log leva alguns minutos para aparecer na API.**
Como a política referencia a métrica pelo tipo, o primeiro `apply` cria a métrica
e morre com `Error 404: Cannot find metric(s) that match type=...`. O módulo já
trata isso com um `time_sleep` disparado pelo id da métrica — não reexecuta nos
applies seguintes. (A espera é fixa onde caberia condicional; funciona, é
grosseiro, e está registrado para revisitar.)

**Cardinalidade é o único jeito de este padrão gerar fatura.** Métrica derivada de
log é cobrada por quantas combinações de rótulo gera: 150 MiB/mês grátis por conta
de faturamento, depois US$ 0,258/MiB. Com rótulo `job_id` (uma dezena de valores)
é de graça. **Nunca use identificador de cliente como rótulo** — `org_id`,
`user_id` e, pior, `request_id` viram milhares de séries. Atenção especial no
`modules/log-error-alert`, cujo comentário sugere `request_id/org_id`.

**Credenciais:** o Terraform usa ADC (`gcloud auth application-default login`), que
é **independente** da conta do `gcloud` (`gcloud config set account`). Trocar uma
não troca a outra. E `USER_PROJECT_DENIED` em comandos de faturamento não é falta
de permissão: é projeto de cota errado — passe `--billing-project=<projeto>`.

## 7. O que ainda não existe

- **Dead man's switch** nas rotinas críticas — o único padrão que pegaria a morte
  da seção 3 ("respondeu 200 e não fez nada"), e o único que teria pego o 401 da
  régua no dia 1 em vez do dia 5. A rotina grava uma marca ao terminar **com
  trabalho feito**; o alerta dispara pela *ausência* da marca.
- **Alertas do Meus Dredinhos** (`md-hom`, `md-prd-490503`) — adiados por decisão,
  MD está em homologação.
- **Uptime externo** — nenhum alerta enxerga "o GCP inteiro caiu". Plano gratuito
  de terceiro resolve.
- **5xx nos serviços** — entra no dia do go-live, não antes. Ver
  [observabilidade.md](observabilidade.md).
- **Erro de CI** — fica fora por decisão: o deploy de homolog do sys-bjj falha de
  propósito, e seria falso positivo diário.

## 8. Como testar sem encostar em produção

Alerta que nunca disparou não é alerta, é decoração. O jeito seguro:

```bash
# 1. job temporário que falha de propósito: caminho inexistente e SEM token OIDC
#    (o Cloud Run recusa antes de chegar na aplicação — não executa nada).
#    "0 0 1 1 *" garante que ele nunca dispara sozinho.
gcloud scheduler jobs create http teste-alerta-temporario \
  --project=<projeto> --location=southamerica-east1 \
  --schedule="0 0 1 1 *" --time-zone="America/Sao_Paulo" \
  --uri="https://<servico>.run.app/internal/caminho-que-nao-existe" \
  --http-method=POST --attempt-deadline=30s --max-retry-attempts=0

# 2. disparar
gcloud scheduler jobs run teste-alerta-temporario --project=<projeto> --location=southamerica-east1

# 3. conferir o Slack, depois apagar
gcloud scheduler jobs delete teste-alerta-temporario --project=<projeto> --location=southamerica-east1
```

Como as políticas de digestão usam `alvo: []`, elas cobrem o job de teste sem
configuração extra.

Tempos medidos no teste de 24/09/2026 no `bjj-system`: log imediato → métrica
contou em ~1 min → incidente aberto em ~3 min → mensagem no Slack. **~3 minutos do
disparo à notificação.**

Um detalhe: com `janela: 86400s` o incidente de teste fica aberto por até 24h,
porque o valor permanece dentro da janela de agregação. Fechar na mão no console
se incomodar.

## 9. Por que este padrão existe

Em 17–21/09/2026 a régua diária de cobrança do `cm-billing` ficou **cinco dias**
respondendo `UNAUTHENTICATED` (faltava `SECURE_PROXY_SSL_HEADER` no Django atrás
do Cloud Run). Ninguém percebeu.

O log do Cloud Scheduler registrava a falha todos os dias, com o status escrito.
**A informação estava lá o tempo todo — não faltava dado, faltava quem olhasse.**

É isso que um alerta faz: transforma dado que existe em alguém sabendo.
