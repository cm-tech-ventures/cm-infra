# static-site-iap

Módulo Terraform genérico para publicar um site estático (ex: um dashboard
Evidence.dev) direto num Cloud Run service protegido por **oauth2-proxy (sem
Load Balancer nem domínio próprio)**, com **publicação atômica via
objeto-ponteiro no bucket**.

Não é específico de nenhuma vertical/core — qualquer core da CM Ventures que
precise publicar um site estático com controle de acesso via login Google pode
reutilizá-lo.

## Arquitetura (revisão de 2026-08-01, 2ª parte — CMV-346, "oauth2-proxy")

```
cliente --HTTPS (*.run.app)--> [container oauth2-proxy] --localhost--> [container proxy]
                                  login Google +                        lê current-release
                                  allowlist de e-mails                  e serve releases/<versão>/...
                                                                                |
                                                                                v
                                                                        bucket GCS (privado)
```

- **Bucket único**, privado (`public_access_prevention = "enforced"`). O job
  de publicação escreve cada build em `releases/<versão>/...` e, só depois de
  dlt+dbt (testes + freshness) passarem, sobrescreve o **objeto-ponteiro**
  (`current-release` por padrão) com o texto da versão vigente.
- **Um único Cloud Run service, dois containers (sidecar)**:
  - `oauth2-proxy`: container de ingress, único com porta exposta no
    serviço. Faz login Google, valida o e-mail contra uma allowlist e só
    então repassa a requisição para o upstream via `localhost`.
  - `proxy`: leitor read-only do bucket (lê o ponteiro e serve os arquivos da
    versão apontada). **Sem porta exposta no ingress** — só recebe tráfego
    do oauth2-proxy.
- `min_instance_count = 0` (nenhum worker permanente).
- `roles/run.invoker` do serviço é `allUsers` — ver seção "Postura de
  segurança" abaixo, é intencional.
- **Sem Load Balancer, sem IP global, sem certificado gerenciado** — o
  próprio Cloud Run já serve HTTPS na URL `*.run.app`.

### Por que essa revisão (histórico)

- **v1**: tentava aplicar IAP em `google_compute_backend_bucket` — recurso
  sem suporte a `iap {}` no provider Terraform.
- **v2** (CMV-259): Cloud Run "proxy" atrás de um Serverless NEG +
  `google_compute_backend_service` (que tem `iap {}` nativo) por trás de um
  Load Balancer HTTPS com certificado gerenciado para
  `cm-analytics-dashboard.cm-ventures.com`. Esse domínio **não pertence à
  empresa** (registrado por terceiros, DNS na Netfirms) — o certificado
  gerenciado nunca saiu de `PROVISIONING` e o dashboard ficou inacessível.
- **v3** (CMV-346, 1ª revisão): eliminou o LB e usou **IAP nativo do Cloud
  Run** (GA, sem exigir domínio/certificado), servindo na URL `*.run.app`.
  **Abandonada** por um bug confirmado da plataforma GCP — ver seção
  "Por que não IAP nativo" abaixo.
- **v4** (CMV-346, 2ª revisão, **atual**): substitui o IAP nativo por
  **oauth2-proxy** como sidecar no mesmo Cloud Run service. Mantém a URL
  `*.run.app`, custo fixo de serving ~zero, e evita o bug do IAP nativo —
  a autenticação passa a ser 100% da aplicação, não da borda do GCP.

## Postura de segurança: `allUsers` invoker + auth na aplicação

Sem IAP não há mais gate no IAM/rede do GCP na frente do Cloud Run — por
isso o invoker do serviço é `allUsers` (`roles/run.invoker`). Isso é uma
**mudança de postura de segurança real** em relação às v2/v3 (onde o gate
era na borda do GCP): qualquer requisição chega ao container `oauth2-proxy`
(que responde com a tela de login Google), mas **ninguém sem sessão válida +
e-mail na allowlist chega ao container `proxy`/ao conteúdo estático** — o
`proxy` não tem porta exposta no ingress, só fala com o `oauth2-proxy` via
`localhost`.

Aprovado explicitamente pelo CTO na CMV-346 (2ª revisão), com as seguintes
condições obrigatórias, refletidas neste módulo:

- Imagem do oauth2-proxy **fixada por tag/digest específico** (nunca
  `:latest` — validado em `variables.tf`).
- `--cookie-secure=true` sempre, `--cookie-expire` configurável e ≤ 24h
  (default `12h`, validado em `variables.tf`).
- Container `proxy` sem porta exposta no ingress — só o `oauth2-proxy`
  recebe tráfego externo.

## Por que não IAP nativo (evidência do bug, para avaliar reversão futura)

O IAP nativo em Cloud Run (v3) negava todos os usuários autorizados mesmo
com a IAM policy correta (`roles/iap.httpsResourceAccessor` para os e-mails
esperados, confirmado via `gcloud iap web get-iam-policy` e via REST direto,
sem cache). Os Data Access audit logs de `iap.googleapis.com` mostraram cada
avaliação de `iap.webServiceVersions.accessViaIAP` contra
`resourceName: projects//locations/southamerica-east1/services/...`
(**projeto vazio**) — nunca poderia haver match contra a policy real, que
vive em `projects/857737530765/iap_web/cloud_run-southamerica-east1/...`.

Ciclo de remediação testado (`gcloud run services update <serviço> --no-iap`
seguido de `--iap`, aplicado às 12:56 UTC de 2026-08-01) **não corrigiu** o
contexto interno: a IAM policy sobreviveu intacta (mesmo etag) e as
tentativas de login subsequentes (13:03 e 13:05 UTC) continuaram sendo
negadas com o mesmo `resourceName` malformado.

**Conclusão do board**: bug da integração nativa IAP↔Cloud Run, provavelmente
relacionado a projeto GCP sem organização/Workspace (contas Google
individuais, sem Google Workspace). Decisão: abandonar IAP nativo, não
depurar produto do Google.

**Se o Google corrigir esse bug no futuro**, a volta ao IAP nativo é barata:
reverter este módulo para o commit anterior a esta revisão do README
(remove o sidecar oauth2-proxy, os secrets de cookie/allowlist e o invoker
`allUsers`; re-adiciona `iap_enabled`, `google_iap_web_cloud_run_service_iam_member`
e o invoker do service agent do IAP) — ver commits `807b558`..`63bd63d` no
histórico deste módulo para o desenho v3 completo.

## Pré-requisito manual: OAuth client + redirect URI

O oauth2-proxy reaproveita o **mesmo OAuth client (brand) já configurado**
para as revisões anteriores deste módulo — não cria um novo. Único passo
manual necessário nesta revisão: depois que a URL final `*.run.app` do
serviço estiver disponível (só se sabe após o primeiro apply, pois inclui um
hash gerado pelo Cloud Run), **atualizar a redirect URI do OAuth client no
console GCP** para `https://<url-do-serviço>/oauth2/callback`
(`var.oauth2_proxy_redirect_url` deve refletir esse mesmo valor).

## Secrets consumidos (Secret Manager)

Nenhum desses valores é hardcoded no Terraform — todos vêm de secrets já
existentes ou criados pelo root module que instancia este módulo:

| Secret (referenciado por ID) | Variável | Conteúdo |
|---|---|---|
| `oauth_client_id_secret_id` | `OAUTH2_PROXY_CLIENT_ID` | client_id do OAuth client (reaproveitado das revisões anteriores) |
| `oauth_client_secret_secret_id` | `OAUTH2_PROXY_CLIENT_SECRET` | client_secret do OAuth client |
| `cookie_secret_id` | `OAUTH2_PROXY_COOKIE_SECRET` | 32 bytes aleatórios (cookie de sessão) |
| `allowed_emails_secret_id` | montado como arquivo em `/etc/oauth2-proxy/allowed-emails` | allowlist de e-mails, um por linha |

## Como funciona a publicação atômica (objeto-ponteiro no bucket)

1. O job de publicação (`cm-analytics/scripts/publish_atomic.sh`, fora deste
   módulo) roda a extração (dlt) e a transformação (dbt build — inclui testes
   e checagem de freshness). Se qualquer uma falhar, o script para aqui e o
   bucket não é tocado.
2. Só se o passo anterior passou: build do Evidence.
3. O script gera um identificador de versão (ex: timestamp/SHA) e envia a
   build para `releases/<versão>/...` no bucket — um caminho novo, que ainda
   não está sendo servido por ninguém.
4. **Só então**, com os arquivos já validados e no lugar, o script sobrescreve
   o objeto-ponteiro (`current-release`) com o texto `<versão>`.
5. O proxy lê o ponteiro a cada request (ou com cache curto, ex. ≤30s) e serve
   os arquivos de `releases/<versão-apontada>/...`.

A escrita do passo 4 é uma escrita de objeto único no GCS — atômica por
natureza (nunca existe uma leitura parcial/corrompida do ponteiro). Se
qualquer etapa anterior falhar, o ponteiro não é tocado e o site continua
servindo a build anterior, sem downtime e sem rollback manual.

## Quem escreve no bucket

Só a service account de runtime do job de publicação
(`runtime_service_account_email`) tem `roles/storage.objectAdmin` no bucket.
A service account do proxy (`google_service_account.proxy`, criada por este
módulo) tem apenas `roles/storage.objectViewer` — nunca escreve.

## O container `proxy` (upstream)

`var.proxy_image` é a imagem do container upstream — stateless, somente
leitura do bucket via ADC, sem lógica de negócio. Requisitos:

- Escuta em `localhost` na porta `var.proxy_internal_port` (via env `PORT`
  injetada pelo módulo) — **não** na porta pública `$PORT` que o Cloud Run
  injetaria por padrão (essa é do container `oauth2-proxy`).
- Lê o objeto `var.pointer_object_name` no bucket `var.name-site` para saber
  a versão vigente.
- Serve os arquivos de `releases/<versão>/<path solicitado>` (ex: via
  streaming do GCS, sem baixar tudo em disco).
- Sem rota de escrita, sem estado local persistente entre requests.

A imagem é publicada pelo workflow reusável `build-and-push` do repositório do
core (ex: `cm-analytics`), não gerenciada por este módulo — o
`lifecycle.ignore_changes` no `google_cloud_run_v2_service.proxy` evita que um
`terraform apply` de rotina reverta um rollout de imagem novo (tanto do
`proxy` quanto do `oauth2-proxy`, se o pin de versão mudar via variável).

## Variáveis principais

| Variável | Descrição |
|---|---|
| `name` | Nome base do site (prefixo de todos os recursos) |
| `project_id` | Projeto GCP |
| `region` | Região do bucket e do Cloud Run |
| `runtime_service_account_email` | SA do job de publicação (write no bucket) |
| `proxy_image` | Imagem do container upstream (leitor do bucket) |
| `proxy_internal_port` | Porta interna (localhost) do container `proxy` (default `8081`) |
| `proxy_max_instances` | Máximo de instâncias do serviço (min é sempre 0) |
| `pointer_object_name` | Nome do objeto-ponteiro no bucket (default `current-release`) |
| `oauth2_proxy_image` | Imagem do oauth2-proxy, fixada por tag/digest específico |
| `oauth2_proxy_port` | Porta pública do oauth2-proxy (default `8080`) |
| `oauth2_proxy_redirect_url` | URL de callback OAuth (`https://.../oauth2/callback`) |
| `oauth2_proxy_cookie_expire` | Expiração do cookie de sessão, ≤ 24h (default `12h`) |
| `oauth_client_id_secret_id` / `oauth_client_secret_secret_id` | Secrets do OAuth client |
| `cookie_secret_id` | Secret do cookie_secret do oauth2-proxy |
| `allowed_emails_secret_id` | Secret da allowlist de e-mails |

## Outputs principais

`bucket_name`, `pointer_object_name`, `proxy_service_name`,
`proxy_service_account_email`, `dashboard_url` (URL `*.run.app` do dashboard).
