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
  artifact-registry/   # repositório Docker + IAM readers/writers
  scheduler-job/       # Cloud Scheduler → Cloud Run via OIDC (sem worker permanente)
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
    uses: cm-ventures/cm-infra/.github/workflows/django-ci.yml@main
  build:
    needs: ci
    uses: cm-ventures/cm-infra/.github/workflows/build-and-push.yml@main
    with: { image-name: cm-identity, gcp-region: ..., gcp-project-id: ..., artifact-repository: cm-cores, workload-identity-provider: ..., deploy-service-account: ... }
  deploy:
    needs: build
    uses: cm-ventures/cm-infra/.github/workflows/deploy-cloud-run.yml@main
    with: { service: cm-identity, image-uri: ${{ needs.build.outputs.image-uri }}, state-bucket: ..., workload-identity-provider: ..., deploy-service-account: ... }
```

E um `infra/main.tf` fino no core instanciando `modules/cloud-run-service` (e
`scheduler-job` quando houver async), com `backend "gcs" {}` vazio — o workflow
injeta `bucket` e `prefix=<service>/<environment>` no `init`.

## Bootstrap (one-time, requer projeto GCP)

```bash
cd bootstrap
terraform init -backend=false   # primeiro apply com state local
terraform apply -var project_id=... -var github_owner=cm-ventures \
  -var 'github_repositories=["cm-ventures/cm-identity", ...]' \
  -var state_bucket_name=cm-ventures-tf-state
# depois migre o state para o bucket recém-criado:
terraform init -migrate-state \
  -backend-config="bucket=cm-ventures-tf-state" -backend-config="prefix=bootstrap/prod"
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
