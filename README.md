# cm-infra

Infraestrutura reutilizável dos cores da CM Ventures: módulos Terraform, reusable
workflows do GitHub Actions e bootstrap de Workload Identity Federation (GitHub → GCP).

Contrato de design: documento `design` em CMV-4 (revisão CTO). Invariantes:

- **1 service account por core**, permissões mínimas — nunca SA compartilhada.
- **Zero segredo no TF state** — só referências a Secret Manager (`secret_key_ref`).
- **Módulos genéricos** — nenhum conceito de vertical em recurso algum.
- **Sem acoplamento entre schemas** — cada core tem schema Postgres e credencial próprios.
- Ambiente parametrizado (`environment`) — `prod` hoje, pronto para `staging`.

## Layout

```
modules/
  cloud-run-service/   # serviço + SA dedicada + secrets (refs) + domínio opcional
  cloud-run-job/       # job batch (disparado pelo Scheduler via Run Admin API)
  artifact-registry/   # repositório Docker + IAM readers/writers
  scheduler-job/       # Cloud Scheduler → Cloud Run via OIDC (sem worker permanente)
  static-site-iap/     # site estático atrás de IAP
  alerta-generico/     # alerta de rotina agendada (ver docs/alertas.md)
  log-error-alert/     # alerta de erro de aplicação (ver docs/observabilidade.md)
  monitoring-alert-email/  # LEGADO: cria canal E política juntos; não reusar
catalogo/
  rotinas.yaml         # RETRATO das rotinas agendadas (não é fonte; ver o topo do arquivo)
environments/          # instâncias com state próprio
  keepalive/           # keep-alive dos bancos Supabase free-tier
  alertas-core/        # alertas de rotina do cm-ventures-core (catálogo em YAML)
  alertas-bjj/         # idem, projeto bjj-system (outra conta GCP, outro state)
  log-sinks/           # sinks de eventos dos 3 projetos para o bronze_logs
  billing-export-acesso/  # leitura no billing_export (export de faturamento, fora de TF)
docs/                  # padrões da casa — ler antes de criar recurso novo
.github/workflows/     # reusable workflows (workflow_call)
  django-ci.yml        # ruff + pytest + contrato OpenAPI (spectacular diff)
  build-and-push.yml   # build Docker + push AR via WIF; output image-uri com digest
  deploy-cloud-run.yml # terraform init (backend GCS por serviço/env) + apply
bootstrap/             # one-time: APIs, bucket de state, WIF pool/provider, SA de deploy
```

## Uso num core (~10 linhas de workflow)

```yaml
jobs:
  ci:
    uses: cm-tech-ventures/cm-infra/.github/workflows/django-ci.yml@main
  build:
    needs: ci
    uses: cm-tech-ventures/cm-infra/.github/workflows/build-and-push.yml@main
    with: { image-name: cm-identity, gcp-region: ..., gcp-project-id: ..., artifact-repository: cm-cores, workload-identity-provider: ..., deploy-service-account: ... }
  deploy:
    needs: build
    uses: cm-tech-ventures/cm-infra/.github/workflows/deploy-cloud-run.yml@main
    with: { service: cm-identity, image-uri: ${{ needs.build.outputs.image-uri }}, state-bucket: ..., workload-identity-provider: ..., deploy-service-account: ... }
```

E um `infra/main.tf` fino no core instanciando `modules/cloud-run-service` (e
`scheduler-job` quando houver async), com `backend "gcs" {}` vazio — o workflow
injeta `bucket` e `prefix=<service>/<environment>` no `init`.

## Bootstrap (one-time, requer projeto GCP)

O bootstrap **já foi aplicado**; o state vive em `gs://cm-ventures-core-tfstate`,
prefixo `bootstrap/prod`. Para planejar/aplicar sobre o que existe:

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars   # valores reais, ignorado pelo git
terraform init \
  -backend-config="bucket=cm-ventures-core-tfstate" -backend-config="prefix=bootstrap/prod"
terraform plan   # tem que dar "No changes"; qualquer destroy = input faltando
```

**Nunca rode o plan passando variáveis soltas na linha de comando.** Elas não
têm default, e um valor errado (uma lista vazia, por exemplo) faz o Terraform
propor destruir permissões reais de deploy. Use sempre o `terraform.tfvars`.

Do zero, num projeto novo (não é o caso do core):

```bash
terraform init -backend=false   # primeiro apply com state local
terraform apply -var-file=terraform.tfvars
terraform init -migrate-state \
  -backend-config="bucket=<bucket>" -backend-config="prefix=bootstrap/prod"
```

Outputs do bootstrap (`workload_identity_provider`, `deploy_service_account`,
`state_bucket`, `artifact_repository_url`) são os valores passados aos reusable
workflows pelos cores. Nenhuma chave JSON de service account existe em lugar nenhum.

## Estado e ambientes

- Backend GCS versionado, lock nativo; **um state por core**: `prefix=<service>/<env>`.
- `environment` é variável em todos os módulos/workflows (default `prod`); para
  `staging`, novo GitHub Environment + mesmo bucket com prefix `<service>/staging`.

## Validação local (sem cloud)

```bash
terraform -chdir=modules/cloud-run-service init -backend=false && terraform -chdir=modules/cloud-run-service validate
# idem para os demais módulos e bootstrap; tflint opcional
```

## Documentação

| Documento | Para quê |
|---|---|
| [docs/permissoes.md](docs/permissoes.md) | **Dar, conferir ou tirar permissão de nuvem.** As 4 regras, quem aplica o quê, o que dá para condicionar e como revogar. |
| [docs/alertas.md](docs/alertas.md) | **Criar um alerta de rotina agendada.** O padrão da casa: catálogo em YAML, dois sensores, duas caixas no Slack. |
| [docs/observabilidade.md](docs/observabilidade.md) | Log estruturado e alerta de erro de aplicação (5xx, exceção). |
| [docs/keepalive.md](docs/keepalive.md) | Keep-alive dos bancos Supabase free-tier. |
| [docs/ops-semanal.md](docs/ops-semanal.md) | Rotina semanal de operação. |
| [docs/supabase-projects.md](docs/supabase-projects.md) | Inventário dos projetos Supabase. |
| [docs/adr/](docs/adr/) | Decisões de arquitetura. |

**Este repo não tem CI.** Qualquer mudança de Terraform exige mostrar o `plan`
literal ao Carlos antes de qualquer `apply`.
