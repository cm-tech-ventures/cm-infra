# static-site-iap

Módulo Terraform genérico para publicar um site estático (ex: um dashboard
Evidence.dev) atrás de um Load Balancer HTTPS externo protegido por
Identity-Aware Proxy (IAP), com **publicação atômica via objeto-ponteiro no
bucket**.

Não é específico de nenhuma vertical/core — qualquer core da CM Ventures que
precise publicar um site estático com controle de acesso via login Google pode
reutilizá-lo.

## Arquitetura (revisão de 2026-08-01 — ADR-003, adendo)

```
cliente --HTTPS--> LB (IAP) --> backend_service --> Serverless NEG --> Cloud Run "proxy"
                                                                              |
                                                                     lê current-release
                                                                     e serve releases/<versão>/...
                                                                              |
                                                                              v
                                                                       bucket GCS (privado)
```

- **Bucket único**, privado (`public_access_prevention = "enforced"`). O job
  de publicação escreve cada build em `releases/<versão>/...` e, só depois de
  dlt+dbt (testes + freshness) passarem, sobrescreve o **objeto-ponteiro**
  (`current-release` por padrão) com o texto da versão vigente.
- **Cloud Run service "proxy"**: stateless, `min_instance_count = 0` (nenhum
  worker permanente), somente leitura do bucket via a própria service account
  (ADC), sem lógica de negócio. Lê o ponteiro e serve os arquivos da versão
  apontada. Ingress restrito a `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` — a
  URL `*.run.app` não serve o dashboard; só é alcançável pelo LB.
- **Serverless NEG + `google_compute_backend_service`**: ao contrário de
  `google_compute_backend_bucket`, este recurso **suporta o bloco `iap {}`
  nativo** do provider Terraform — sem `null_resource`/`local-exec`.
- **Load Balancer HTTPS externo**: IP global, certificado gerenciado, proxy
  HTTPS e regra de encaminhamento — como antes.

### Por que essa revisão (histórico)

A primeira versão deste módulo tentava aplicar IAP em
`google_compute_backend_bucket`. Verificado via `terraform providers schema
-json` (providers `google`/`google-beta` v6.50.0) que esse recurso **não
expõe** o bloco `iap {}` no Terraform (só existe na API REST, não coberta pelo
provider) — só `google_compute_backend_service` tem esse bloco. A segunda
versão contornava isso com blue/green de dois backend buckets + IAP habilitado
via `null_resource`/`local-exec` chamando `gcloud`/`curl` diretamente na API.

O CTO decidiu (adendo ao ADR-003) trocar a arquitetura por completo: em vez de
servir o bucket diretamente, um Cloud Run service proxy mínimo senta atrás de
um Serverless NEG + `google_compute_backend_service`, que tem IAP nativo. Isso
elimina o `null_resource` frágil **e** simplifica a publicação atômica: sai do
nível "LB/url_map" e vira uma escrita de objeto único no bucket (ver seção
abaixo), que é atômica por natureza no GCS.

## Pré-requisito manual obrigatório: OAuth brand do IAP

O IAP exige um **OAuth consent screen ("brand") e um OAuth Client ID/Secret**
associados ao projeto GCP. Isso **não é totalmente terraformável** — a criação
da "brand" (tela de consentimento OAuth) exige permissão de administrador da
organização/Workspace e, na prática, é feita manualmente uma única vez pelo
console do GCP:

1. Console GCP → "APIs & Services" → "OAuth consent screen": configurar a
   brand do projeto (nome, domínio, e-mail de suporte).
2. Console GCP → "APIs & Services" → "Credentials" → "Create OAuth client ID"
   (tipo "Web application"): gera o `client_id` e o `client_secret`.
3. Esses dois valores são passados para este módulo como
   `iap_oauth_client_id` / `iap_oauth_client_secret` (variáveis `sensitive`,
   nunca commitar em `.tfvars` versionado — usar Secret Manager ou variável de
   ambiente `TF_VAR_...` injetada pelo CI).

## Pré-requisito: membros autorizados

`iap_authorized_members` é uma lista de identidades IAM (uma entrada por
pessoa ou grupo) com direito de ver o dashboard. Formatos aceitos:
`user:pessoa@dominio.com`, `group:nome@googlegroups.com`,
`serviceAccount:...`, `domain:...`.

Em conta GCP sem organização/Workspace não existe domínio para um Google
Group gerenciado — nesse caso liste cada pessoa diretamente com `user:...`
(ex: `["user:board@cm-ventures.com", "user:dono-md@cm-ventures.com"]`). Se no
futuro a empresa tiver Workspace, prefira consolidar em um único
`group:...@googlegroups.com` ou grupo de domínio, e gerenciar a lista de
membros fora do Terraform (responsabilidade de quem administra o grupo) — o
Terraform só concede o papel de IAP a cada identidade da lista, não gerencia
membros de grupo.

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

Diferente da versão blue/green anterior, a SA de runtime **não precisa de
nenhuma permissão de rede/LB**: não existe mais custom role para flipar
`url_map` — o Terraform gerencia o `url_map` por inteiro, normalmente, sem
`lifecycle.ignore_changes`.

## O container do proxy

`var.proxy_image` é a imagem do serviço Cloud Run proxy — stateless, somente
leitura do bucket via ADC, sem lógica de negócio. Requisitos:

- Lê o objeto `var.pointer_object_name` no bucket `var.name-site` para saber
  a versão vigente.
- Serve os arquivos de `releases/<versão>/<path solicitado>` (ex: via
  streaming do GCS, sem baixar tudo em disco).
- Sem rota de escrita, sem estado local persistente entre requests.

A imagem é publicada pelo workflow reusável `build-and-push` do repositório do
core (ex: `cm-analytics`), não gerenciada por este módulo — o
`lifecycle.ignore_changes` no `google_cloud_run_v2_service.proxy` evita que um
`terraform apply` de rotina reverta um rollout de imagem novo.

## Nome do resource IAM do IAP

O recurso `google_iap_web_backend_service_iam_member`, usado neste módulo para
conceder `roles/iap.httpsResourceAccessor` no backend service, aceita o
argumento `web_backend_service = <nome do backend service>` no provider
`google` padrão (sem exigir `google-beta`).

## Variáveis principais

| Variável | Descrição |
|---|---|
| `name` | Nome base do site (prefixo de todos os recursos) |
| `project_id` | Projeto GCP |
| `region` | Região do bucket e do Cloud Run proxy |
| `iap_oauth_client_id` / `iap_oauth_client_secret` | Credenciais OAuth do IAP (ver pré-requisito manual acima) |
| `iap_authorized_members` | Lista de identidades IAM autorizadas (`user:...`, `group:...`) |
| `runtime_service_account_email` | SA do job de publicação (write no bucket) |
| `proxy_image` | Imagem do serviço Cloud Run proxy |
| `proxy_max_instances` | Máximo de instâncias do proxy (min é sempre 0) |
| `pointer_object_name` | Nome do objeto-ponteiro no bucket (default `current-release`) |

## Outputs principais

`bucket_name`, `pointer_object_name`, `backend_service_name`,
`proxy_service_name`, `proxy_service_account_email`, `url_map_name`,
`load_balancer_ip`.
