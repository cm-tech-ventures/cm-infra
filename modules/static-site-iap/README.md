# static-site-iap

Módulo Terraform genérico para publicar um site estático (ex: um dashboard
Evidence.dev) atrás de um Load Balancer HTTPS externo protegido por
Identity-Aware Proxy (IAP), com **publicação atômica via padrão blue/green a
nível de Load Balancer**.

Não é específico de nenhuma vertical/core — qualquer core da CM Ventures que
precise publicar um site estático com controle de acesso via login Google pode
reutilizá-lo.

## O que o módulo cria

- Dois buckets GCS privados: `<name>-blue` e `<name>-green` (sem acesso
  público — `public_access_prevention = "enforced"`; o único caminho de leitura
  é através do Load Balancer + IAP).
- Dois `google_compute_backend_bucket` (um por cor), cada um com IAP habilitado
  via `gcloud` (ver seção "Limitação conhecida do provider" abaixo — o bloco
  `iap {}` nativo do Terraform não está disponível para este tipo de recurso).
- Um `google_compute_url_map` cujo `default_service` aponta para o backend da
  cor ativa.
- Load Balancer HTTPS externo padrão: IP global reservado, certificado gerenciado,
  proxy HTTPS e regra de encaminhamento global.
- Um `google_project_iam_custom_role` granular (só `compute.urlMaps.get` e
  `compute.urlMaps.update`) concedido à service account de runtime — evita usar
  o papel amplo `roles/compute.loadBalancerAdmin`.
- `roles/storage.objectAdmin` nos dois buckets para a mesma service account (ela
  precisa escrever os arquivos do site).
- `roles/iap.httpsResourceAccessor` para o grupo Google autorizado, em cada
  backend bucket.

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

Sem esse passo manual prévio, o `null_resource`/`local-exec` que habilita o IAP
no backend bucket (ver seção de limitação do provider abaixo) falha, pois o
`gcloud compute backend-buckets update --iap=...` exige um client OAuth já
existente.

## Pré-requisito: grupo Google autorizado

`iap_authorized_group` deve ser um Google Group já existente no Workspace da
empresa (ex: `group:board-and-md-owner@cm-ventures.com`), contendo exatamente
as pessoas com direito de ver o dashboard (board + dono do MD). Gerenciar
membros do grupo é responsabilidade de quem administra o Workspace, fora deste
módulo — o Terraform só concede o papel de IAP ao grupo, não gerencia seus
membros.

## Como funciona a publicação atômica (blue/green no Load Balancer)

Diferente de um blue/green "a nível de arquivo" (sobrescrever os arquivos do
mesmo bucket em produção), este módulo mantém **dois buckets e dois backends
sempre vivos**. A cor "ativa" é apenas qual backend o `url_map` aponta como
`default_service`.

O fluxo de publicação (implementado em `cm-analytics/scripts/publish_atomic.sh`,
fora deste módulo) é:

1. Rodar a extração (dlt) e a transformação (dbt build — inclui testes e
   checagem de freshness). Se qualquer uma falhar, o script para aqui.
2. Só se o passo anterior passou: build do Evidence.
3. Descobrir qual cor está **inativa** (standby) lendo o `url_map` atual
   (`gcloud compute url-maps describe`).
4. Sincronizar os arquivos da build nova para o bucket standby
   (`gsutil -m rsync`) — o bucket ativo (servindo produção agora) não é tocado.
5. **Só então**, com os arquivos já validados e no lugar, trocar o
   `default_service` do `url_map` para o backend do bucket que acabou de
   receber a build nova (`gcloud compute url-maps set-default-service`).

O passo 5 é uma única chamada de API — a troca é atômica do ponto de vista de
quem acessa o site: nunca existe uma janela em que o LB serve arquivos
parcialmente escritos, e se qualquer passo anterior falhar, o `url_map`
continua apontando para a build anterior (que continua no ar, sem downtime e
sem qualquer rollback manual).

## Quem flipa o `url_map`: o job, não o Terraform

O bloco `lifecycle { ignore_changes = [default_service] }` no recurso
`google_compute_url_map.site` existe justamente para isso: depois do primeiro
`apply` (que define a cor inicial via `active_color`), o Terraform **nunca mais
tenta corrigir/reverter** o `default_service` — quem manda nele a partir daí é
o job de publicação, via chamada direta à Compute API. Se o Terraform não
ignorasse essa mudança, o próximo `terraform apply` de rotina reverteria
silenciosamente a última publicação para a cor definida em `active_color`,
quebrando o próprio propósito do blue/green.

Isso implica que `active_color` na configuração Terraform **não reflete
necessariamente qual cor está ativa em produção** depois do primeiro apply —
ele só importa no bootstrap inicial do módulo. Para saber a cor ativa real,
consulte o `url_map` diretamente (`gcloud compute url-maps describe <nome>`).

## Nome do resource IAM do IAP

O recurso `google_iap_web_backend_service_iam_member`, usado neste módulo para
conceder `roles/iap.httpsResourceAccessor` no backend bucket, foi verificado
nesta implementação via `terraform providers schema -json` contra o provider
`hashicorp/google` v6.50.0: existe no provider `google` padrão (não exige
`google-beta`) e aceita o argumento `web_backend_service = <nome do backend
bucket>`. Recomenda-se reconferir contra a versão do provider efetivamente
pinada no lockfile do ambiente-alvo antes do apply em produção.

## Limitação conhecida do provider: IAP em `google_compute_backend_bucket`

Ao rodar `terraform validate` durante o desenvolvimento deste módulo, foi
constatado que `google_compute_backend_bucket` **não aceita** o bloco `iap {}`
(testado nos providers `google` e `google-beta`, ambos v6.50.0, via
`terraform providers schema -json`). O bloco `iap {}` só existe no recurso
`google_compute_backend_service` (backends de instância/NEG), não no de bucket
GCS — apesar de a API REST do Compute Engine aceitar IAP em backend buckets.

Para não bloquear o módulo nessa lacuna do provider, o IAP dos backend buckets
é configurado via um `null_resource` com provisioner `local-exec` que chama
`gcloud compute backend-buckets update --iap=...` logo após o backend bucket
ser criado. Isso sai do caminho 100% declarativo do Terraform para esse campo
específico (exige `gcloud` autenticado disponível no ambiente que roda o
apply) e deve ser substituído por um bloco nativo assim que o provider passar
a suportar `iap` em `google_compute_backend_bucket`.

## Variáveis principais

| Variável | Descrição |
|---|---|
| `name` | Nome base do site (prefixo de todos os recursos) |
| `project_id` | Projeto GCP |
| `region` | Região dos buckets GCS |
| `iap_oauth_client_id` / `iap_oauth_client_secret` | Credenciais OAuth do IAP (ver pré-requisito manual acima) |
| `iap_authorized_group` | Grupo Google autorizado (`group:...`) |
| `runtime_service_account_email` | SA que escreve nos buckets e flipa o url_map (normalmente `service_account_email` do módulo `cloud-run-job` do pipeline) |
| `active_color` | Cor ativa no apply inicial (`"blue"` por padrão) |

## Outputs principais

`bucket_names`, `backend_bucket_names`, `url_map_name`, `load_balancer_ip`.
