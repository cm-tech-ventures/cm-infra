# static-site-iap

Módulo Terraform genérico para publicar um site estático (ex: um dashboard
Evidence.dev) direto num Cloud Run service protegido por **IAP nativo (sem
Load Balancer nem domínio próprio)**, com **publicação atômica via
objeto-ponteiro no bucket**.

Não é específico de nenhuma vertical/core — qualquer core da CM Ventures que
precise publicar um site estático com controle de acesso via login Google pode
reutilizá-lo.

## Arquitetura (revisão de 2026-08-01 — CMV-346, "sem domínio próprio")

```
cliente --HTTPS (*.run.app)--> IAP nativo do Cloud Run --> Cloud Run "proxy"
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
  apontada. `ingress = INGRESS_TRAFFIC_ALL` + `iap_enabled = true`: a URL
  `*.run.app` é pública no sentido de rede, mas o IAP intercepta toda
  requisição antes do container e exige login Google + autorização IAM.
- **Sem Load Balancer, sem IP global, sem certificado gerenciado** — o
  próprio Cloud Run já serve HTTPS na URL `*.run.app`.

### Por que essa revisão (histórico)

A v1 tentava aplicar IAP em `google_compute_backend_bucket` — recurso sem
suporte a `iap {}` no provider Terraform. A v2 (CMV-259) passou para um Cloud
Run "proxy" atrás de um Serverless NEG + `google_compute_backend_service`
(que tem `iap {}` nativo) por trás de um Load Balancer HTTPS com certificado
gerenciado para `cm-analytics-dashboard.cm-ventures.com`.

Esse domínio **não pertence à empresa** (registrado por terceiros, DNS na
Netfirms) — o certificado gerenciado nunca saiu de `PROVISIONING` e o
dashboard ficou inacessível (bug CMV-346). O board decidiu (2026-08-01) não
usar domínio próprio por ora: esta v3 elimina o LB por completo e usa o IAP
nativo do Cloud Run (GA, sem exigir domínio/certificado), servindo na URL
`*.run.app`. Reduz custo fixo de serving a praticamente zero (elimina
~US$18/mês de LB + IP + cert) e simplifica o módulo.

## Pré-requisito: IAP habilitado no projeto

Diferente da v2 (que exigia criar manualmente um OAuth Client ID/Secret e
passá-los ao módulo), o IAP nativo do Cloud Run reaproveita a "brand"
(OAuth consent screen) já configurada no projeto GCP — não recebe
`client_id`/`client_secret` por recurso. Pré-requisitos:

1. API `iap.googleapis.com` habilitada no projeto.
2. OAuth consent screen ("brand") já configurada (mesmo pré-requisito
   manual da v2 — feito uma única vez, não muda com esta revisão).

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

## Nota de validação pendente (CMV-346)

O campo `iap_enabled` em `google_cloud_run_v2_service` e o recurso
`google_iap_web_cloud_run_service_iam_member` foram escritos com base na
documentação pública do IAP nativo em Cloud Run — **confirmar contra um
`terraform plan` real** (ou `terraform providers schema -json`) antes do
primeiro apply desta revisão, do mesmo jeito que a v1→v2 foi validada. Se o
provider fixado em `versions.tf` não expuser esses recursos, ajustar a
version constraint antes de prosseguir.

## Variáveis principais

| Variável | Descrição |
|---|---|
| `name` | Nome base do site (prefixo de todos os recursos) |
| `project_id` | Projeto GCP |
| `region` | Região do bucket e do Cloud Run proxy |
| `iap_authorized_members` | Lista de identidades IAM autorizadas (`user:...`, `group:...`) |
| `runtime_service_account_email` | SA do job de publicação (write no bucket) |
| `proxy_image` | Imagem do serviço Cloud Run proxy |
| `proxy_max_instances` | Máximo de instâncias do proxy (min é sempre 0) |
| `pointer_object_name` | Nome do objeto-ponteiro no bucket (default `current-release`) |

## Outputs principais

`bucket_name`, `pointer_object_name`, `proxy_service_name`,
`proxy_service_account_email`, `dashboard_url` (URL `*.run.app` do dashboard).
